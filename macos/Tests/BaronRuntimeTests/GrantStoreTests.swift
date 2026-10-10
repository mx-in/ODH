import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

func pluginWith(permissions: [String], optional: [String] = []) throws -> RuntimePlugin {
    let plugin = try makePlugin("globalThis.__baronPlugin = { actions: { run() {} } };")
    var manifest = plugin.manifest
    manifest.permissions = permissions
    manifest.optionalPermissions = optional
    return RuntimePlugin(manifest: manifest, package: plugin.package)
}

struct GrantStoreTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("baron-grants-\(UUID().uuidString)")
    let clock = TestClock()
    var store: GrantStore { GrantStore(folder: folder, now: { [clock] in clock.now }) }

    @Test func startsWithTheInstallPermissions() async throws {
        let plugin = try pluginWith(permissions: ["secrets", "network:dict.cn"], optional: ["network:*"])
        let set = await store.grantedSet(for: plugin)
        #expect(set.holds(.secrets) && !set.holds(.clipboardRead))
        #expect(set.networkPermission(covering: URL(string: "https://dict.cn/x")!) != nil)
        #expect(set.networkPermission(covering: URL(string: "https://evil.example/")!) == nil)
        #expect(set.mayRequest(PluginPermission("network:evil.example")!))
        #expect(!set.mayRequest(.clipboardRead))
    }

    @Test func alwaysAllowIsSavedAndSurvivesANewStore() async throws {
        let plugin = try pluginWith(permissions: [], optional: ["network:*"])
        await store.record(.alwaysAllow, for: "network:dict.cn", pluginID: plugin.id)
        let reopened = GrantStore(folder: folder)
        #expect(await reopened.grantedSet(for: plugin).networkPermission(covering: URL(string: "https://dict.cn/")!) != nil)
        #expect(await reopened.runtimeGrants(for: plugin.id).map(\.permission) == ["network:dict.cn"])
    }

    @Test func denyLastsADay() async throws {
        let plugin = try pluginWith(permissions: [], optional: ["network:*"])
        let store = self.store
        await store.record(.deny, for: "network:dict.cn", pluginID: plugin.id)
        #expect(await store.grantedSet(for: plugin).recentlyDenied == ["network:dict.cn"])
        clock.advance(GrantStore.denyLasts + 1)
        #expect(await store.grantedSet(for: plugin).recentlyDenied.isEmpty)
    }

    @Test func allowOnceLastsTenMinutesInMemory() async throws {
        let plugin = try pluginWith(permissions: [], optional: ["network:*"])
        let store = self.store
        await store.record(.allowOnce, for: "network:dict.cn", pluginID: plugin.id)
        #expect(await store.grantedSet(for: plugin).networkPermission(covering: URL(string: "https://dict.cn/")!) != nil)
        #expect(await GrantStore(folder: folder).grantedSet(for: plugin).networkPermission(covering: URL(string: "https://dict.cn/")!) == nil)
        clock.advance(GrantStore.allowOnceLasts + 1)
        #expect(await store.grantedSet(for: plugin).networkPermission(covering: URL(string: "https://dict.cn/")!) == nil)
    }

    @Test func aNewAnswerReplacesTheOldAndRevokingRemovesIt() async throws {
        let plugin = try pluginWith(permissions: [], optional: ["network:*"])
        let store = self.store
        await store.record(.deny, for: "network:dict.cn", pluginID: plugin.id)
        await store.record(.alwaysAllow, for: "network:dict.cn", pluginID: plugin.id)
        #expect(await store.runtimeGrants(for: plugin.id).map(\.answer) == [.alwaysAllow])
        await store.revoke("network:dict.cn", pluginID: plugin.id)
        #expect(await store.runtimeGrants(for: plugin.id).isEmpty)
    }
}
