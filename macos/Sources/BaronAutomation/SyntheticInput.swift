import CoreGraphics
import Foundation

/// Posts real mouse and keyboard events, as a person would. Needs the Accessibility grant.
/// Points are top-left-origin screen points, the same space CGEvent uses.
public enum SyntheticInput {
    private static let source = CGEventSource(stateID: .hidSystemState)

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
        pause(0.02)
    }

    public static func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
