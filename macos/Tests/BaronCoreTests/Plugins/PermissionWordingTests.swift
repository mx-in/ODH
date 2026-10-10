import Foundation
import Testing
@testable import BaronCore

struct PermissionWordingTests {
    @Test func phrasesEachPermission() {
        #expect(PermissionWording.phrase(PluginPermission("network:dict.cn")!) == "connect to dict.cn")
        #expect(PermissionWording.phrase(PluginPermission("network:*.youdao.com")!) == "connect to any site under youdao.com")
        #expect(PermissionWording.phrase(PluginPermission("network:api.example.com:8443")!) == "connect to api.example.com on port 8443")
        #expect(PermissionWording.phrase(PluginPermission("network:http://example.com")!) == "connect to example.com without encryption")
        #expect(PermissionWording.phrase(PluginPermission("network:127.0.0.1:8765")!) == "connect to apps on this Mac (127.0.0.1:8765)")
        #expect(PermissionWording.promptTitle(pluginName: "Define", permission: .clipboardRead) == "“Define” wants to read your clipboard.")
    }

    @Test func groupsODHsPermissions() throws {
        let odh = ManifestCorpusCase.root.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("plugins/odh")
        let manifest = try #require(ManifestValidator().validate(package: odh).manifest)
        let summary = PermissionWording.summary(of: manifest)
        #expect(summary.reads == ["Read the sentence around what you select", "Read the paragraph around what you select",
                                  "See the web page address", "See the window title and file name"])
        #expect(summary.connectsTo.first == "dict.youdao.com")
        #expect(summary.connectsTo.contains("apps on this Mac (127.0.0.1:8765)"))
        #expect(summary.connectsTo.last == "May ask to connect to other websites")
        #expect(summary.disclosures == ["Runs code it downloads, which keeps the plugin's permissions."])
        #expect(summary.can.isEmpty && summary.stores.isEmpty)
    }
}
