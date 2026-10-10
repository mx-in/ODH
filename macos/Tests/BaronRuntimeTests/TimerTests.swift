import Testing
@testable import BaronRuntime

struct TimerTests {
    func engine(_ outbox: Outbox) async throws -> JSCEngineContext {
        let engine = JSCEngineContext(pluginID: "org.example.timers")
        try await engine.installNative(send: { outbox.append($0) })
        try await engine.evaluate(Prelude.source, sourceURL: "prelude.js")
        return engine
    }

    func logs(_ outbox: Outbox) -> [String] {
        outbox.all.filter { $0["ns"] as? String == "log" }.compactMap { ($0["args"] as? [String])?.first }
    }

    @Test func timeoutsFireInDelayOrder() async throws {
        let outbox = Outbox()
        let engine = try await engine(outbox)
        try await engine.evaluate("setTimeout(() => console.log('late'), 30); setTimeout(() => console.log('early'), 5);")
        _ = try await outbox.wait { ($0["args"] as? [String])?.first == "late" }
        #expect(logs(outbox) == ["early", "late"])
        #expect(engine.pendingTimerCount == 0)
    }

    @Test func intervalsRepeatUntilCleared() async throws {
        let outbox = Outbox()
        let engine = try await engine(outbox)
        try await engine.evaluate("let n = 0; const id = setInterval(() => { console.log('tick ' + ++n); if (n === 3) clearInterval(id); }, 2);")
        _ = try await outbox.wait { ($0["args"] as? [String])?.first == "tick 3" }
        try await Task.sleep(for: .milliseconds(30))
        #expect(logs(outbox) == ["tick 1", "tick 2", "tick 3"])
        #expect(engine.pendingTimerCount == 0)
    }

    @Test func clearedTimeoutsNeverFire() async throws {
        let outbox = Outbox()
        let engine = try await engine(outbox)
        try await engine.evaluate("clearTimeout(setTimeout(() => console.log('no'), 5)); setTimeout(() => console.log('yes'), 15);")
        _ = try await outbox.wait { ($0["args"] as? [String])?.first == "yes" }
        #expect(logs(outbox) == ["yes"])
    }

    @Test func unloadingDropsPendingTimers() async throws {
        let outbox = Outbox()
        let engine = try await engine(outbox)
        try await engine.evaluate("setTimeout(() => console.log('never'), 20)")
        #expect(engine.pendingTimerCount == 1)
        engine.unload()
        try await Task.sleep(for: .milliseconds(40))
        #expect(logs(outbox).isEmpty)
    }
}
