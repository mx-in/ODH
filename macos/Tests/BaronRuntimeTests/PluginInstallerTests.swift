import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

@Suite(.serialized)
struct PluginInstallerTests {
    let location = PluginDataLocation.temporary()
    let secrets = SecretStore(servicePrefix: "org.odh.baron.test.\(UUID().uuidString).")
    var data: PluginDataManager {
        PluginDataManager(stores: PluginStores(location: location), preferences: PreferencesStore(location: location), secrets: secrets,
                          grants: GrantStore(folder: location.dataRoot))
    }
    var installer: PluginInstaller { PluginInstaller(root: location.dataRoot.deletingLastPathComponent().appendingPathComponent("Plugins"), data: data) }

    func package(version: String, permissions: [String] = [], source: PluginSource? = nil) throws -> PluginPackage {
        let folder = try Packages.folder(version: version, permissions: permissions)
        return try PackageReader.read(folder: folder, source: source ?? .folder("/dev/plugin"))
    }

    @Test func installsAFreshPackageIntoItsVersionFolder() async throws {
        let installer = self.installer
        let plan = await installer.plan(try package(version: "1.0.0"))
        #expect(plan.kind == .fresh && plan.needsSheet)
        try await installer.install(plan, consented: true)
        let installed = await installer.installed()
        #expect(installed.map(\.plugin.id) == ["org.example.pkg"])
        #expect(installed[0].plugin.package.path.hasSuffix("Plugins/org.example.pkg/1.0.0"))
        #expect(FileManager.default.fileExists(atPath: installed[0].plugin.package.appendingPathComponent("dist/main.js").path))
        // A new installer reads the registry back.
        #expect(await PluginInstaller(root: installer.root, data: data).installed().count == 1)
    }

    @Test func copiesOnlyWhatThePackageShips() async throws {
        let installer = self.installer
        let folder = try Packages.folder()
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("src"), withIntermediateDirectories: true)
        try Data("export {}".utf8).write(to: folder.appendingPathComponent("src/main.ts"))
        try await installer.install(await installer.plan(PackageReader.read(folder: folder, source: .folder(folder.path))), consented: true)
        let copied = try FileManager.default.contentsOfDirectory(atPath: installer.folder("org.example.pkg", version: "1.0.0").path).sorted()
        #expect(copied == ["dist", "manifest.json"])
    }

    @Test func updatesSilentlyWithoutNewPermissionsAndKeepsThePreviousUntilLoaded() async throws {
        let installer = self.installer
        try await installer.install(await installer.plan(try package(version: "1.0.0", permissions: ["secrets"])), consented: true)
        let update = await installer.plan(try package(version: "1.1.0", permissions: ["secrets"]))
        #expect(update.kind == .update(from: "1.0.0", addsPermissions: []) && !update.needsSheet)
        try await installer.install(update, consented: false)
        #expect(await installer.record("org.example.pkg")?.version == "1.1.0")
        #expect(FileManager.default.fileExists(atPath: await installer.folder("org.example.pkg", version: "1.0.0").path))
        try await installer.confirmLoaded("org.example.pkg")
        #expect(!FileManager.default.fileExists(atPath: await installer.folder("org.example.pkg", version: "1.0.0").path))
    }

    @Test func anUpdateAddingPermissionsWaitsForConsentWhileTheOldVersionWorks() async throws {
        let installer = self.installer
        try await installer.install(await installer.plan(try package(version: "1.0.0")), consented: true)
        let update = await installer.plan(try package(version: "2.0.0", permissions: ["clipboard.read"]))
        #expect(update.kind == .update(from: "1.0.0", addsPermissions: ["clipboard.read"]) && update.needsSheet)
        try await installer.install(update, consented: false)
        let record = await installer.record("org.example.pkg")
        #expect(record?.version == "1.0.0" && record?.pending?.newPermissions == ["clipboard.read"])
        #expect(await installer.installed().first?.plugin.manifest.version == "1.0.0")
        try await installer.acceptPending("org.example.pkg")
        #expect(await installer.installed().first?.plugin.manifest.version == "2.0.0")
    }

    @Test func decliningKeepsTheOldVersion() async throws {
        let installer = self.installer
        try await installer.install(await installer.plan(try package(version: "1.0.0")), consented: true)
        try await installer.install(await installer.plan(try package(version: "2.0.0", permissions: ["clipboard.read"])), consented: false)
        try await installer.declinePending("org.example.pkg")
        #expect(await installer.record("org.example.pkg")?.pending == nil)
        #expect(!FileManager.default.fileExists(atPath: await installer.folder("org.example.pkg", version: "2.0.0").path))
    }

    @Test func asksBeforeReinstallingOrDowngradingAndWarnsAboutAnotherSource() async throws {
        let installer = self.installer
        try await installer.install(await installer.plan(try package(version: "2.0.0")), consented: true)
        #expect(await installer.plan(try package(version: "2.0.0")).kind == .reinstall)
        let older = await installer.plan(try package(version: "1.0.0", source: .file("/Downloads/x.baronplugin")))
        #expect(older.kind == .downgrade(from: "2.0.0") && older.needsSheet)
        #expect(older.otherSource == .folder("/dev/plugin"))
    }

    @Test func uninstallLeavesNothingOnDiskOrInTheKeychain() async throws {
        let installer = self.installer
        let data = self.data
        try await installer.install(await installer.plan(try package(version: "1.0.0")), consented: true)
        try await data.stores.storage(for: "org.example.pkg").set("k", .string("v"))
        try await data.preferences.set("p", to: .string("v"), pluginID: "org.example.pkg")
        try secrets.set("apiKey", "sk", pluginID: "org.example.pkg")
        await data.grants.record(.alwaysAllow, for: "network:dict.cn", pluginID: "org.example.pkg")
        try await PluginInstaller(root: installer.root, data: data).uninstall("org.example.pkg")
        #expect(!FileManager.default.fileExists(atPath: installer.root.appendingPathComponent("org.example.pkg").path))
        #expect(!FileManager.default.fileExists(atPath: location.dataRoot.appendingPathComponent("org.example.pkg").path))
        #expect(!FileManager.default.fileExists(atPath: location.cacheRoot.appendingPathComponent("org.example.pkg").path))
        #expect(secrets.keys(pluginID: "org.example.pkg").isEmpty)
        #expect(await PluginInstaller(root: installer.root, data: data).installed().isEmpty)
    }
}
