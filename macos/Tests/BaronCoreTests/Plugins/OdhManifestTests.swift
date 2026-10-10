import Foundation
import Testing
@testable import BaronCore

/// ODH's manifest (plugins/odh) is the first real plugin manifest; Baron must accept it.
struct OdhManifestTests {
    static let package = ManifestCorpusCase.root.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("plugins/odh")

    @Test func validates() throws {
        let result = ManifestValidator(environment: ManifestEnvironment(baronVersion: "0.1.0", platform: .macos, apiVersions: 1...1)).validate(package: Self.package)
        #expect(result.issues == [])
        let manifest = try #require(result.manifest)
        #expect(manifest.actions.map(\.id) == ["lookup"])
        #expect(manifest.actions.first?.autoRun == .allowed)
    }

    @Test func showsItsTitleInEnglishAndChinese() throws {
        let manifest = try #require(ManifestValidator().validate(package: Self.package).manifest)
        let title = try #require(manifest.actions.first?.title)
        #expect(PluginLocalizer(package: Self.package, defaultLocale: "en", preferredLanguages: ["en-US"]).resolve(title) == "Look up")
        #expect(PluginLocalizer(package: Self.package, defaultLocale: "en", preferredLanguages: ["zh-Hans-CN"]).resolve(title) == "查词")
        #expect(PluginLocalizer(package: Self.package, defaultLocale: "en", preferredLanguages: ["zh-Hant-TW"]).resolve(manifest.name) == "在線詞典助手")
    }
}
