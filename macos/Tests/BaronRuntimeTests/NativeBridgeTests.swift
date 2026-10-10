import Testing
@testable import BaronRuntime

struct NativeBridgeTests {
    func loadedEngine(_ outbox: Outbox, plugin: String) async throws -> JSCEngineContext {
        let engine = JSCEngineContext(pluginID: "org.example.a")
        try await engine.installNative(send: { outbox.append($0) })
        try await engine.evaluate(Prelude.source, sourceURL: "prelude.js")
        try await engine.evaluate(plugin)
        return engine
    }

    @Test func thePreludeTakesTheNativeObject() async throws {
        let engine = try await loadedEngine(Outbox(), plugin: "")
        #expect(try await engine.evaluate("[typeof __baronNative, typeof __baronReceive, typeof URL].join()") == "undefined,function,function")
    }

    @Test func runsAnActionAndAHostCallEndToEnd() async throws {
        let outbox = Outbox()
        let engine = try await loadedEngine(outbox, plugin: """
        globalThis.__baronPlugin = { actions: { async shout(ctx, host) {
            return { type: "replace", text: ctx.text.toUpperCase() + await host.storage.get("suffix") };
        } } };
        """)
        engine.deliver(Envelopes.dispatch(id: 5, action: "shout"))
        let call = try await outbox.wait { $0["kind"] as? String == "call" && $0["ns"] as? String == "storage" }
        engine.deliver(Envelopes.result(id: call["id"] as! Int, value: "!"))
        let result = try await outbox.wait { $0["kind"] as? String == "result" && $0["id"] as? Int == 5 }
        #expect(result["ok"] as? Bool == true)
        #expect((result["value"] as? [String: Any])?["text"] as? String == "FOX!")
    }

    @Test func pluginErrorsComeBackAsResults() async throws {
        let outbox = Outbox()
        let engine = try await loadedEngine(outbox, plugin: "globalThis.__baronPlugin = { actions: { bad() { throw new TypeError('no word') } } };")
        engine.deliver(Envelopes.dispatch(id: 1, action: "bad"))
        let result = try await outbox.wait { $0["kind"] as? String == "result" }
        let error = result["error"] as? [String: Any]
        #expect(error?["code"] as? String == "plugin_error")
        #expect(error?["message"] as? String == "no word")
    }
}
