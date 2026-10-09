import CoreGraphics

/// What made Baron look for a selection.
public enum TriggerKind: String, Codable, Sendable {
    case drag
    case doubleClick
    case tripleClick
    case shiftClick
    case keyboard
    case hotkey
}

/// A window's identity and frame at one moment, in top-left-origin screen points.
public struct WindowSnapshot: Equatable, Sendable {
    public var id: Int
    public var frame: CGRect

    public init(id: Int, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

/// A gesture that may have selected text. Coordinates are top-left-origin screen points.
public struct Trigger: Equatable, Sendable {
    public var kind: TriggerKind
    public var location: CGPoint
    /// The window under the pointer moved or resized during the gesture: a window drag, not a selection.
    public var windowDragged: Bool

    public init(kind: TriggerKind, location: CGPoint, windowDragged: Bool = false) {
        self.kind = kind
        self.location = location
        self.windowDragged = windowDragged
    }
}

extension Trigger {
    /// The hotkey is an explicit request, so the gate's guesses about intent don't apply.
    public var skipsGate: Bool { kind == .hotkey }
}
