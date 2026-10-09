import CoreGraphics
import Testing
@testable import BaronCore

struct PointerTriggerDetectorTests {
    private func run(_ events: [PointerEvent]) -> Trigger? {
        var detector = PointerTriggerDetector()
        var last: Trigger?
        for event in events { last = detector.handle(event) }
        return last
    }

    @Test func dragOfFivePointsTriggers() {
        let trigger = run([
            PointerEvent(phase: .down, location: CGPoint(x: 0, y: 0)),
            PointerEvent(phase: .dragged, location: CGPoint(x: 3, y: 4)),
            PointerEvent(phase: .up, location: CGPoint(x: 3, y: 4)),
        ])
        #expect(trigger?.kind == .drag)
    }

    @Test func shortDragIsAPlainClick() {
        let trigger = run([
            PointerEvent(phase: .down, location: .zero),
            PointerEvent(phase: .up, location: CGPoint(x: 2, y: 2)),
        ])
        #expect(trigger == nil)
    }

    @Test func dragThatReturnsStillCounts() {
        let trigger = run([
            PointerEvent(phase: .down, location: .zero),
            PointerEvent(phase: .dragged, location: CGPoint(x: 40, y: 0)),
            PointerEvent(phase: .up, location: CGPoint(x: 1, y: 0)),
        ])
        #expect(trigger?.kind == .drag)
    }

    @Test(arguments: [(2, TriggerKind.doubleClick), (3, .tripleClick), (4, .tripleClick)])
    func multiClicks(count: Int, kind: TriggerKind) {
        let trigger = run([
            PointerEvent(phase: .down, location: .zero, clickCount: count),
            PointerEvent(phase: .up, location: .zero, clickCount: count),
        ])
        #expect(trigger?.kind == kind)
    }

    @Test func shiftClickTriggers() {
        let trigger = run([
            PointerEvent(phase: .down, location: .zero, shift: true),
            PointerEvent(phase: .up, location: .zero, shift: true),
        ])
        #expect(trigger?.kind == .shiftClick)
    }

    @Test func upWithoutDownIsIgnored() {
        #expect(run([PointerEvent(phase: .up, location: .zero, clickCount: 2)]) == nil)
    }

    @Test func movedWindowIsMarkedAsWindowDrag() {
        let before = WindowSnapshot(id: 7, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let after = WindowSnapshot(id: 7, frame: CGRect(x: 50, y: 0, width: 100, height: 100))
        let trigger = run([
            PointerEvent(phase: .down, location: .zero, window: before),
            PointerEvent(phase: .dragged, location: CGPoint(x: 50, y: 0)),
            PointerEvent(phase: .up, location: CGPoint(x: 50, y: 0), window: after),
        ])
        #expect(trigger?.windowDragged == true)
    }

    @Test func stillWindowIsNotAWindowDrag() {
        let window = WindowSnapshot(id: 7, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let trigger = run([
            PointerEvent(phase: .down, location: .zero, window: window),
            PointerEvent(phase: .up, location: CGPoint(x: 20, y: 0), window: window),
        ])
        #expect(trigger?.windowDragged == false)
    }
}

struct KeyboardTriggerDetectorTests {
    @Test func shiftArrowIsASelectionGesture() {
        #expect(KeyboardTriggerDetector.isSelectionGesture(keyCode: 124, modifiers: [.shift]))
        #expect(KeyboardTriggerDetector.isSelectionGesture(keyCode: 123, modifiers: [.shift, .option]))
        #expect(KeyboardTriggerDetector.isSelectionGesture(keyCode: 126, modifiers: [.shift, .command]))
    }

    @Test func plainArrowIsNot() {
        #expect(!KeyboardTriggerDetector.isSelectionGesture(keyCode: 124, modifiers: []))
        #expect(!KeyboardTriggerDetector.isSelectionGesture(keyCode: 124, modifiers: [.shift, .control]))
    }

    @Test func commandAIsOnlyExactlyCommandA() {
        #expect(KeyboardTriggerDetector.isSelectionGesture(keyCode: 0, modifiers: [.command]))
        #expect(!KeyboardTriggerDetector.isSelectionGesture(keyCode: 0, modifiers: [.command, .shift]))
        #expect(!KeyboardTriggerDetector.isSelectionGesture(keyCode: 0, modifiers: []))
    }

    @Test func onlyTheLastGestureOfARunFires() {
        var detector = KeyboardTriggerDetector()
        let first = detector.handleKey(keyCode: 124, modifiers: [.shift])!
        let second = detector.handleKey(keyCode: 124, modifiers: [.shift])!
        #expect(!detector.isLatest(first))
        #expect(detector.isLatest(second))
    }

    @Test func typingAfterAGestureCancelsIt() {
        var detector = KeyboardTriggerDetector()
        let token = detector.handleKey(keyCode: 124, modifiers: [.shift])!
        #expect(detector.handleKey(keyCode: 4, modifiers: []) == nil)
        #expect(!detector.isLatest(token))
    }
}
