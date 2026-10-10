import BaronCore
import Testing
@testable import BaronRuntime

struct IdleTests {
    let counter = """
    globalThis.loads = (globalThis.loads ?? 0) + 1;
    let count = 0;
    globalThis.__baronPlugin = { actions: {
        count() { return { type: 'copy', text: String(++count) }; },
        longWait() { return new Promise((resolve) => setTimeout(resolve, 600)); },
    } };
    """

    func runtime(idle: Duration) async throws -> (PluginRuntime, String) {
        var limits = RuntimeLimits.fast
        limits.idle = idle
        limits.action = .seconds(2)
        let plugin = try makePlugin(counter)
        let runtime = PluginRuntime(handler: ScriptedHost(), limits: limits)
        await runtime.register(plugin)
        return (runtime, plugin.id)
    }

    func count(_ runtime: PluginRuntime, _ id: String) async throws -> JSONValue? {
        try await runtime.dispatch(id, .action, name: "count", payload: DispatchPayload()).get()["text"]
    }

    @Test func unloadsWhenIdleAndStartsFreshOnTheNextDispatch() async throws {
        let (runtime, id) = try await runtime(idle: .milliseconds(150))
        #expect(try await count(runtime, id) == .string("1"))
        #expect(try await count(runtime, id) == .string("2"))
        try await Task.sleep(for: .milliseconds(400))
        #expect(await runtime.isLoaded(id) == false)
        #expect(await runtime.state(of: id) == .unloaded)
        #expect(try await count(runtime, id) == .string("1"))
    }

    @Test func aRunningDispatchKeepsThePluginLoaded() async throws {
        let (runtime, id) = try await runtime(idle: .milliseconds(150))
        _ = try await runtime.dispatch(id, .action, name: "longWait", payload: DispatchPayload()).get()
        #expect(await runtime.isLoaded(id))
    }

    @Test func reloadStartsAFreshContext() async throws {
        let (runtime, id) = try await runtime(idle: .seconds(60))
        #expect(try await count(runtime, id) == .string("1"))
        await runtime.reload(id)
        #expect(await runtime.isLoaded(id) == false)
        #expect(try await count(runtime, id) == .string("1"))
    }
}
