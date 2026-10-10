import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

struct PermissionGateTests {
    let gate = PermissionGate(grants: GrantStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("baron-gate-\(UUID().uuidString)")),
                              actions: UserActionTracker())

    func check(_ ns: String, _ method: String, _ plugin: RuntimePlugin) async -> HostError? {
        await gate.check(HostCall(id: 1, namespace: ns, method: method, arguments: []), plugin)
    }

    @Test func refusesMethodsWithoutTheirPermission() async throws {
        let plugin = try pluginWith(permissions: [])
        gate.actions.record(plugin.id)
        let error = await check("clipboard", "readText", plugin)
        #expect(error?.code == "permission_denied")
        #expect(error?.data == .object(["permission": .string("clipboard.read"), "requestable": .bool(false)]))
        #expect(await check("secrets", "get", plugin)?.code == "permission_denied")
        #expect(await check("selection", "replace", plugin)?.code == "permission_denied")
    }

    @Test func saysWhenAPermissionCanBeAskedFor() async throws {
        let plugin = try pluginWith(permissions: [], optional: ["clipboard.read"])
        gate.actions.record(plugin.id)
        #expect(await check("clipboard", "readText", plugin)?.data?["requestable"] == .bool(true))
    }

    @Test func refusesSideEffectsWithoutARecentClick() async throws {
        let plugin = try pluginWith(permissions: ["selection.replace"])
        #expect(await check("selection", "replace", plugin)?.code == "user_action_required")
        #expect(await check("clipboard", "writeText", plugin)?.code == "user_action_required")
        #expect(await check("ui", "openUrl", plugin)?.code == "user_action_required")
        gate.actions.record(plugin.id)
        #expect(await check("selection", "replace", plugin) == nil)
        #expect(await check("clipboard", "writeText", plugin) == nil)
    }

    @Test func letsFreeMethodsThrough() async throws {
        let plugin = try pluginWith(permissions: [])
        for (ns, method) in [("storage", "set"), ("log", "info"), ("ui", "toast"), ("text", "segment"), ("http", "fetch"), ("permissions", "query")] {
            #expect(await check(ns, method, plugin) == nil, "\(ns).\(method)")
        }
    }

    @Test func pluginCodeSeesTheRefusals() async throws {
        let plugin = try pluginWith(permissions: [])
        let runtime = PluginRuntime(handler: HostRouter(services: [StubClipboard()], gate: gate), limits: .fast)
        await runtime.register(RuntimePlugin(manifest: plugin.manifest, package: try makePlugin("""
        globalThis.__baronPlugin = { actions: { async run(ctx, host) {
            try { await host.clipboard.writeText('x'); return { type: 'copy', text: 'wrote' }; }
            catch (e) { return { type: 'copy', text: e.code }; }
        } } };
        """).package))
        #expect(try await runtime.dispatch(plugin.id, .action, name: "run", payload: DispatchPayload()).get()["text"] == .string("user_action_required"))
    }
}

struct StubClipboard: HostService {
    let namespace = "clipboard"
    func call(_ method: String, _ arguments: HostArguments, plugin: RuntimePlugin) async throws -> JSONValue { .null }
}
