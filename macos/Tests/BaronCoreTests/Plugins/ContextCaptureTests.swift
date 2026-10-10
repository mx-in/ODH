import Foundation
import Testing
@testable import BaronCore

private let read = CapturedContext(window: .init(title: "Notes"))

@MainActor
struct ContextCaptureTests {
    @Test func anActionGetsTheContextOnceItArrives() async {
        let capture = ContextCapture([.window]) { _ in
            Thread.sleep(forTimeInterval: 0.05)
            return read
        }
        #expect(await capture.value() == read)
        // Later actions get it straight away.
        #expect(await capture.value(waitingAtMost: .zero) == read)
    }

    @Test func anActionWaitsAtMostTheLimitThenRunsWithout() async {
        let capture = ContextCapture([.window]) { _ in
            Thread.sleep(forTimeInterval: 0.5)
            return read
        }
        let clock = ContinuousClock()
        let started = clock.now
        #expect(await capture.value(waitingAtMost: .milliseconds(100)) == nil)
        #expect(clock.now - started < .milliseconds(400))
    }

    @Test func nothingIsReadWhenNoActionNeedsContext() async {
        let capture = ContextCapture([]) { _ in
            Issue.record("read without fields")
            return read
        }
        #expect(await capture.value(waitingAtMost: .zero) == CapturedContext())
    }
}
