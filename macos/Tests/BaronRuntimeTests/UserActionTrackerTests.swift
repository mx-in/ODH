import Testing
@testable import BaronRuntime

struct UserActionTrackerTests {
    @Test func aClickCountsForFiveSecondsAndOnlyForItsPlugin() {
        let clock = TestClock()
        let tracker = UserActionTracker(now: { [clock] in clock.now })
        #expect(!tracker.hasRecentAction("org.example.a"))
        tracker.record("org.example.a")
        #expect(tracker.hasRecentAction("org.example.a"))
        #expect(!tracker.hasRecentAction("org.example.b"))
        clock.advance(5)
        #expect(tracker.hasRecentAction("org.example.a"))
        clock.advance(0.1)
        #expect(!tracker.hasRecentAction("org.example.a"))
    }
}
