import BaronCore
import Testing
@testable import BaronRuntime

struct DispatchTests {
    let context: JSONValue = .object(["text": .string("fox"), "source": .string("ax-text"), "editable": .bool(true),
                                      "app": .object(["id": .string("a"), "name": .string("A"), "pid": .number(1)]), "platform": .string("macos")])

    func runtime(_ bundle: String, host: ScriptedHost = ScriptedHost()) async throws -> (PluginRuntime, String) {
        let plugin = try makePlugin(bundle)
        let runtime = PluginRuntime(handler: host, limits: .fast)
        await runtime.register(plugin)
        return (runtime, plugin.id)
    }

    @Test func runsAnActionWithTheContextAndEnvironment() async throws {
        let (runtime, id) = try await runtime("""
        globalThis.__baronPlugin = { actions: { run(ctx, host) {
            return { type: "toast", message: ctx.text + " " + host.environment.pluginVersion + " " + host.preferences.deck };
        } } };
        """)
        let result = await runtime.dispatch(id, .action, name: "run", payload: DispatchPayload(preferences: ["deck": .string("Default")], context: context))
        #expect(try result.get() == .object(["type": .string("toast"), "message": .string("fox 1.0.0 Default")]))
    }

    @Test func relaysHostCallsToTheHandler() async throws {
        let host = ScriptedHost { call in call.namespace == "storage" ? .success(.string("!")) : .failure(.notFound("no")) }
        let (runtime, id) = try await runtime("globalThis.__baronPlugin = { actions: { async run(ctx, host) { return { type: 'copy', text: ctx.text + await host.storage.get('x') }; } } };", host: host)
        #expect(try await runtime.dispatch(id, .action, name: "run", payload: DispatchPayload(context: context)).get()["text"] == .string("fox!"))
    }

    @Test func returnsPluginAndHostErrors() async throws {
        let host = ScriptedHost { _ in .failure(HostError("permission_denied", "no network")) }
        let (runtime, id) = try await runtime("""
        globalThis.__baronPlugin = { actions: {
            bad() { throw new Error('broken word') },
            async denied(ctx, host) { await host.http.fetch('https://x.example') },
        } };
        """, host: host)
        let bad = await runtime.dispatch(id, .action, name: "bad", payload: DispatchPayload(context: context))
        #expect((bad.failure?.code, bad.failure?.message) == ("plugin_error", "broken word"))
        #expect(await runtime.dispatch(id, .action, name: "denied", payload: DispatchPayload(context: context)).failure?.code == "permission_denied")
        #expect(await runtime.dispatch(id, .action, name: "missing", payload: DispatchPayload(context: context)).failure?.code == "not_found")
    }

    @Test func timesOutAndAbortsTheSignal() async throws {
        let (runtime, id) = try await runtime("""
        globalThis.aborted = false;
        globalThis.__baronPlugin = { actions: { slow(ctx, host) {
            return new Promise((resolve) => host.signal.addEventListener('abort', () => { globalThis.aborted = true; resolve(); }));
        }, quick() { return globalThis.aborted ? { type: 'copy', text: 'aborted' } : undefined; } } };
        """)
        let clock = ContinuousClock()
        let start = clock.now
        let result = await runtime.dispatch(id, .action, name: "slow", payload: DispatchPayload(context: context))
        #expect(result.failure?.code == "timeout")
        #expect(clock.now - start < .seconds(1))
        try await Task.sleep(for: .milliseconds(20))
        #expect(try await runtime.dispatch(id, .action, name: "quick", payload: DispatchPayload(context: context)).get()["text"] == .string("aborted"))
    }

    @Test func servesOptionsButtonsAndLifecycle() async throws {
        let (runtime, id) = try await runtime("""
        globalThis.__baronPlugin = { actions: { run() {} },
            options: { decks: (prefs) => [{ value: prefs.url, title: 'Deck' }] },
            buttons: { test: () => ({ message: 'ok' }) },
            lifecycle: { onUpdate: ({ previousVersion }) => { globalThis.previous = previousVersion; } } };
        """)
        #expect(try await runtime.dispatch(id, .options, name: "decks", payload: DispatchPayload(preferences: ["url": .string("u")])).get() == .array([.object(["value": .string("u"), "title": .string("Deck")])]))
        #expect(try await runtime.dispatch(id, .button, name: "test", payload: DispatchPayload()).get()["message"] == .string("ok"))
        _ = try await runtime.dispatch(id, .lifecycle, name: "onUpdate", payload: DispatchPayload(arguments: [.object(["previousVersion": .string("0.9.0")])])).get()
        #expect(try await runtime.dispatch(id, .lifecycle, name: "onInstall", payload: DispatchPayload()).get() == .null)
    }
}
