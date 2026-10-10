import Testing
@testable import BaronCore

struct HostMethodRequirementTests {
    @Test func followsTheDesignsNamespaceRules() {
        #expect(HostMethodRequirement.of(namespace: "clipboard", method: "readText") == .init(permission: .clipboardRead, needsUserAction: true))
        #expect(HostMethodRequirement.of(namespace: "clipboard", method: "writeText") == .init(needsUserAction: true))
        #expect(HostMethodRequirement.of(namespace: "selection", method: "replace") == .init(permission: .selectionReplace, needsUserAction: true))
        #expect(HostMethodRequirement.of(namespace: "secrets", method: "get")?.permission == .secrets)
        #expect(HostMethodRequirement.of(namespace: "http", method: "fetch")?.checksNetwork == true)
        #expect(HostMethodRequirement.of(namespace: "ui", method: "openUrl")?.needsUserAction == true)
        #expect(HostMethodRequirement.of(namespace: "permissions", method: "request")?.needsUserAction == true)
        #expect(HostMethodRequirement.of(namespace: "storage", method: "set") == .init())
        #expect(HostMethodRequirement.of(namespace: "ui", method: "toast") == .init())
    }

    @Test func unknownMethodsHaveNoRequirement() {
        #expect(HostMethodRequirement.of(namespace: "fs", method: "read") == nil)
        #expect(HostMethodRequirement.of(namespace: "ui", method: "alert") == nil)
    }

    @Test func coversEveryMethodOfTheHostInterface() {
        // The methods of host.ts's Host interface (apiVersion 1).
        let host = ["log.debug", "log.info", "log.warn", "log.error", "http.fetch", "http.cancel", "clipboard.readText", "clipboard.writeText",
                    "selection.replace", "storage.get", "storage.set", "storage.remove", "storage.keys", "storage.usage",
                    "cache.get", "cache.set", "cache.remove", "cache.clear", "secrets.get", "secrets.set", "secrets.remove",
                    "text.segment", "ui.toast", "ui.openUrl", "ui.openWebView", "ui.show", "ui.openSettings", "ui.postMessage", "ui.closeView",
                    "permissions.query", "permissions.request"]
        #expect(HostMethodRequirement.allMethods == host.sorted())
    }
}
