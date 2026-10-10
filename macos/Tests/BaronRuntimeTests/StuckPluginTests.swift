import BaronCore
import Testing
@testable import BaronRuntime

struct StuckPluginTests {
    @Test func aPluginStuckInALoopIsSuspendedAndOthersKeepWorking() async throws {
        let stuck = try makePlugin("globalThis.__baronPlugin = { actions: { run() { while (true) {} } } };", id: "org.example.stuck")
        let healthy = try makePlugin("globalThis.__baronPlugin = { actions: { run() { return { type: 'copy', text: 'ok' }; } } };", id: "org.example.healthy")
        var limits = RuntimeLimits.fast
        limits.action = .seconds(5)
        let runtime = PluginRuntime(handler: ScriptedHost(), limits: limits)
        await runtime.register(stuck)
        await runtime.register(healthy)

        let clock = ContinuousClock()
        let start = clock.now
        let result = await runtime.dispatch(stuck.id, .action, name: "run", payload: DispatchPayload())
        #expect(result.failure?.code == "unavailable")
        #expect(clock.now - start < .seconds(2))
        guard case .suspended(let reason) = await runtime.state(of: stuck.id) else { Issue.record("not suspended"); return }
        #expect(reason.contains("stopped responding"))

        #expect(try await runtime.dispatch(healthy.id, .action, name: "run", payload: DispatchPayload()).get()["text"] == .string("ok"))
        #expect(await runtime.dispatch(stuck.id, .action, name: "run", payload: DispatchPayload()).failure?.code == "unavailable")
    }

    @Test func threeTimeoutsSuspendAndReenablingRestores() async throws {
        let plugin = try makePlugin("""
        globalThis.__baronPlugin = { actions: { slow() { return new Promise(() => {}); }, quick() { return { type: 'copy', text: 'ok' }; } } };
        """)
        var limits = RuntimeLimits.fast
        limits.action = .milliseconds(50)
        let runtime = PluginRuntime(handler: ScriptedHost(), limits: limits)
        await runtime.register(plugin)
        for _ in 0..<2 {
            #expect(await runtime.dispatch(plugin.id, .action, name: "slow", payload: DispatchPayload()).failure?.code == "timeout")
        }
        #expect(await runtime.state(of: plugin.id) == .ready)
        #expect(await runtime.dispatch(plugin.id, .action, name: "slow", payload: DispatchPayload()).failure?.code == "timeout")
        guard case .suspended(let reason) = await runtime.state(of: plugin.id) else { Issue.record("not suspended"); return }
        #expect(reason.contains("ran out of time 3 times"))

        await runtime.reenable(plugin.id)
        #expect(await runtime.state(of: plugin.id) == .unloaded)
        #expect(try await runtime.dispatch(plugin.id, .action, name: "quick", payload: DispatchPayload()).get()["text"] == .string("ok"))
    }
}
