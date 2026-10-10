import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

/// The sandboxed helper's code path, through a real NSXPCConnection to an anonymous listener in this process.
@Suite(.serialized)
struct HelperTests {
    nonisolated(unsafe) static let listenerDelegate = PluginHostListener()
    nonisolated(unsafe) static let listener: NSXPCListener = {
        let listener = NSXPCListener.anonymous()
        listener.delegate = listenerDelegate
        listener.resume()
        return listener
    }()

    func runtime(_ host: PluginHost, answer: @escaping @Sendable (HostCall) -> Result<JSONValue, HostError> = { _ in .success(.string("!")) },
                 limits: RuntimeLimits = RuntimeLimits()) -> PluginRuntime {
        PluginRuntime(handler: ScriptedHost(answer: answer), limits: limits, engines: host.engineFactory)
    }

    @Test func runsAnActionWithAHostCallInTheHelper() async throws {
        let host = PluginHost(endpoint: Self.listener.endpoint)
        let runtime = runtime(host)
        let plugin = try makePlugin("""
        globalThis.__baronPlugin = { actions: { async run(ctx, host) {
            const suffix = await host.storage.get("suffix");
            await new Promise((resolve) => setTimeout(resolve, 10));
            return { type: "replace", text: ctx.text.toUpperCase() + suffix };
        } } };
        """)
        await runtime.register(plugin)
        let result = try await runtime.dispatch(plugin.id, .action, name: "run", payload: DispatchPayload(context: .object(["text": .string("fox")]))).get()
        #expect(result == .object(["type": .string("replace"), "text": .string("FOX!")]))
    }

    @Test func reportsCodeThatThrowsWhileLoading() async throws {
        let host = PluginHost(endpoint: Self.listener.endpoint)
        let runtime = runtime(host)
        let plugin = try makePlugin("throw new Error('nope')")
        await runtime.register(plugin)
        let state = await runtime.load(plugin.id)
        guard case .broken(let reason) = state else { Issue.record("not broken: \(state)"); return }
        #expect(reason.contains("nope"))
    }

    @Test func losingTheHelperMidActionGivesUnavailableAndTheNextActionWorks() async throws {
        let host = PluginHost(endpoint: Self.listener.endpoint)
        let runtime = runtime(host)
        let plugin = try makePlugin("""
        globalThis.__baronPlugin = { actions: {
            async slow() { await new Promise((resolve) => setTimeout(resolve, 5000)); return { type: "copy", text: "late" }; },
            fast() { return { type: "copy", text: "fine" }; },
        } };
        """)
        await runtime.register(plugin)
        async let slow = runtime.dispatch(plugin.id, .action, name: "slow", payload: DispatchPayload())
        try await Task.sleep(for: .milliseconds(300))
        host.restart()
        #expect(await slow.failure?.code == "unavailable")
        let next = try await runtime.dispatch(plugin.id, .action, name: "fast", payload: DispatchPayload()).get()
        #expect(next["text"] == .string("fine"))
    }

    @Test func restartsAHelperAboveItsMemoryLimit() async throws {
        let host = PluginHost(endpoint: Self.listener.endpoint, memoryLimit: 1)
        let runtime = runtime(host)
        let plugin = try makePlugin("globalThis.__baronPlugin = { actions: { run() { return { type: 'copy', text: 'x' }; } } };")
        await runtime.register(plugin)
        _ = try await runtime.dispatch(plugin.id, .action, name: "run", payload: DispatchPayload()).get()
        #expect(await host.footprint() > 1)
        #expect(await runtime.isLoaded(plugin.id))
        await host.checkMemory()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!(await runtime.isLoaded(plugin.id)))
        // The next action starts the helper again.
        #expect(try await runtime.dispatch(plugin.id, .action, name: "run", payload: DispatchPayload()).get()["text"] == .string("x"))
    }
}
