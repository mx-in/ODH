import CoreGraphics
import Foundation

/// Posts real mouse and keyboard events, as a person would. Needs the Accessibility grant.
/// Points are top-left-origin screen points, the same space CGEvent uses.
public enum SyntheticInput {
    private static let source = CGEventSource(stateID: .hidSystemState)
    /// When the last left mouse-up was posted: where a selection gesture ends.
    public private(set) static var lastMouseUp = Date.distantPast

    public static func move(to point: CGPoint) {
        post(.mouseMoved, at: point)
        pause(0.05)
    }

    public static func click(at point: CGPoint) {
        move(to: point)
        post(.leftMouseDown, at: point, clickState: 1)
        post(.leftMouseUp, at: point, clickState: 1)
    }

    /// Two clicks inside the double-click interval, with click states 1 then 2, so apps select a word.
    public static func doubleClick(at point: CGPoint) {
        move(to: point)
        post(.leftMouseDown, at: point, clickState: 1)
        post(.leftMouseUp, at: point, clickState: 1)
        pause(0.06)
        post(.leftMouseDown, at: point, clickState: 2)
        post(.leftMouseUp, at: point, clickState: 2)
    }

    /// Three clicks inside the double-click interval, so apps select a paragraph or line.
    public static func tripleClick(at point: CGPoint) {
        move(to: point)
        for state: Int64 in 1...3 {
            post(.leftMouseDown, at: point, clickState: state)
            post(.leftMouseUp, at: point, clickState: state)
            pause(0.05)
        }
    }

    /// Presses at `start`, moves in steps to `end`, and releases: a text selection drag.
    public static func drag(from start: CGPoint, to end: CGPoint, steps: Int = 12) {
        move(to: start)
        post(.leftMouseDown, at: start, clickState: 1)
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, at: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            pause(0.02)
        }
        post(.leftMouseUp, at: end, clickState: 1)
    }

    /// Presses one key. `keyCode` is a macOS virtual key code (53 = Escape, 13 = W).
    public static func press(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
        pause(0.05)
    }

    private static func post(_ type: CGEventType, at point: CGPoint, clickState: Int64 = 0) {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        if clickState > 0 { event?.setIntegerValueField(.mouseEventClickState, value: clickState) }
        event?.post(tap: .cghidEventTap)
        if type == .leftMouseUp { lastMouseUp = Date() }
        pause(0.02)
    }

    public static func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
