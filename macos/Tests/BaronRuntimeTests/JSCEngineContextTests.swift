import Testing
@testable import BaronRuntime

struct JSCEngineContextTests {
    @Test func evaluatesScripts() async throws {
        let engine = JSCEngineContext(pluginID: "org.example.a")
        #expect(try await engine.evaluate("1 + 2") == "3")
        #expect(try await engine.evaluate("var x = 1") == nil)
    }

    /// JavaScriptCore adds only `console`, which the prelude replaces.
    @Test func startsBareWithOnlyTheLanguageBuiltIns() async throws {
        let engine = JSCEngineContext(pluginID: "org.example.a")
        #expect(try await engine.evaluate("[typeof setTimeout, typeof URL, typeof console, typeof fetch, typeof Promise, typeof JSON].join()")
            == "undefined,undefined,object,undefined,function,object")
    }

    @Test func reportsExceptionsWithTheirLine() async throws {
        let engine = JSCEngineContext(pluginID: "org.example.a")
        await #expect(throws: JSCEngineContext.EngineError.exception("Error: boom (line 2)")) {
            try await engine.evaluate("1;\nthrow new Error('boom')")
        }
    }

    @Test func keepsPluginsApart() async throws {
        let a = JSCEngineContext(pluginID: "org.example.a")
        let b = JSCEngineContext(pluginID: "org.example.b")
        try await a.evaluate("globalThis.secret = 42")
        #expect(try await b.evaluate("typeof secret") == "undefined")
        #expect(try await a.evaluate("secret") == "42")
    }

    @Test func refusesWorkAfterUnloading() async throws {
        let engine = JSCEngineContext(pluginID: "org.example.a")
        engine.unload()
        await #expect(throws: JSCEngineContext.EngineError.unloaded) { try await engine.evaluate("1") }
    }
}
