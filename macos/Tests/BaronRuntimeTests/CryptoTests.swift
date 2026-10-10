import Testing
@testable import BaronRuntime

struct CryptoTests {
    func engine() async throws -> JSCEngineContext {
        let engine = JSCEngineContext(pluginID: "org.example.crypto")
        try await engine.installNative(send: { _ in })
        try await engine.evaluate(Prelude.source, sourceURL: "prelude.js")
        return engine
    }

    @Test func digestsMatchKnownValues() async throws {
        let engine = try await engine()
        try await engine.evaluate("""
        globalThis.out = {};
        for (const a of ["SHA-1", "SHA-256"]) crypto.subtle.digest(a, new TextEncoder().encode("abc"))
            .then((b) => out[a] = Array.from(new Uint8Array(b), (x) => x.toString(16).padStart(2, "0")).join(""));
        """)
        try await Task.sleep(for: .milliseconds(20))
        #expect(try await engine.evaluate("out['SHA-1']") == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(try await engine.evaluate("out['SHA-256']") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func randomValuesAndUUIDs() async throws {
        let engine = try await engine()
        #expect(try await engine.evaluate("crypto.getRandomValues(new Uint8Array(32)).some((x) => x !== 0)") == "true")
        #expect(try await engine.evaluate("/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(crypto.randomUUID())") == "true")
    }

    @Test func unknownDigestsAreRefused() {
        #expect(JSCEngineContext.digest("MD5", "YWJj") == nil)
        #expect(JSCEngineContext.digest("SHA-1", "***") == nil)
    }
}
