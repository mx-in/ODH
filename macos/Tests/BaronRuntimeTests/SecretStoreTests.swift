import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

@Suite(.serialized)
struct SecretStoreTests {
    let store = SecretStore(servicePrefix: "org.odh.baron.test.\(UUID().uuidString).")
    let pluginID = "org.example.secrets"

    @Test func storesUpdatesAndRemovesSecrets() throws {
        defer { try? store.removeAll(pluginID: pluginID) }
        #expect(try store.get("apiKey", pluginID: pluginID) == nil)
        try store.set("apiKey", "sk-1", pluginID: pluginID)
        try store.set("apiKey", "sk-2", pluginID: pluginID)
        #expect(try store.get("apiKey", pluginID: pluginID) == "sk-2")
        try store.set("token", "t", pluginID: pluginID)
        #expect(store.keys(pluginID: pluginID) == ["apiKey", "token"])
        try store.remove("apiKey", pluginID: pluginID)
        #expect(try store.get("apiKey", pluginID: pluginID) == nil)
        try store.removeAll(pluginID: pluginID)
        #expect(store.keys(pluginID: pluginID).isEmpty)
    }

    @Test func keepsPluginsApart() throws {
        defer { try? store.removeAll(pluginID: "org.example.a"); try? store.removeAll(pluginID: "org.example.b") }
        try store.set("k", "a's", pluginID: "org.example.a")
        #expect(try store.get("k", pluginID: "org.example.b") == nil)
    }

    @Test func refusesOversizedSecrets() {
        #expect(throws: HostError.self) { try store.set("big", String(repeating: "x", count: SecretStore.valueLimit + 1), pluginID: pluginID) }
    }

    @Test func pluginCodeNeedsThePermission() async throws {
        defer { try? store.removeAll(pluginID: "org.example.test") }
        let gate = PermissionGate(grants: GrantStore(folder: PluginDataLocation.temporary().dataRoot), actions: UserActionTracker())
        let code = """
        globalThis.__baronPlugin = { actions: { async run(ctx, host) {
            try { await host.secrets.set('k', 'v'); return { type: 'copy', text: await host.secrets.get('k') }; }
            catch (e) { return { type: 'copy', text: e.code }; }
        } } };
        """
        for (permissions, expected) in [([String](), "permission_denied"), (["secrets"], "v")] {
            let plugin = try pluginWith(permissions: permissions)
            let runnable = RuntimePlugin(manifest: plugin.manifest, package: try makePlugin(code).package)
            let runtime = PluginRuntime(handler: HostRouter(services: [SecretService(store: store)], gate: gate), limits: .fast)
            await runtime.register(runnable)
            #expect(try await runtime.dispatch(runnable.id, .action, name: "run", payload: DispatchPayload()).get()["text"] == .string(expected))
        }
    }
}
