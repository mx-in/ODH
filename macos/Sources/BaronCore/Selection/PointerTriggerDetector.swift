import CoreGraphics

/// One left-button pointer event, already converted to top-left-origin screen points.
public struct PointerEvent: Sendable {
    public enum Phase: Sendable { case down, dragged, up }

    public var phase: Phase
    public var location: CGPoint
    public var clickCount: Int
    public var shift: Bool
    /// The window under the pointer; read only on down and up.
    public var window: WindowSnapshot?

    public init(phase: Phase, location: CGPoint, clickCount: Int = 1, shift: Bool = false, window: WindowSnapshot? = nil) {
        self.phase = phase
        self.location = location
        self.clickCount = clickCount
        self.shift = shift
        self.window = window
    }
}

/// Turns a down → dragged… → up sequence into a selection trigger, or nothing.
public struct PointerTriggerDetector: Sendable {
    public static let minimumDragDistance: CGFloat = 5

    private var pressed: PointerEvent?
    private var farthest: CGFloat = 0

    public init() {}

    /// Whether a mouse-up at `location` ends a drag, the only case where the window's frame matters
    /// (to spot a window drag). Lets the caller skip the costly window lookup for clicks.
    public func endsDrag(at location: CGPoint) -> Bool {
        guard let pressed else { return false }
        return max(farthest, distance(pressed.location, location)) >= Self.minimumDragDistance
    }

    public mutating func handle(_ event: PointerEvent) -> Trigger? {
        switch event.phase {
        case .down:
            pressed = event
            farthest = 0
            return nil
        case .dragged:
            if let pressed { farthest = max(farthest, distance(pressed.location, event.location)) }
            return nil
        case .up:
            guard let pressed else { return nil }
            self.pressed = nil
            let moved = max(farthest, distance(pressed.location, event.location))
            guard let kind = kind(clickCount: event.clickCount, moved: moved, shift: event.shift) else { return nil }
            return Trigger(kind: kind, location: event.location, windowDragged: windowChanged(from: pressed.window, to: event.window))
        }
    }

    private func kind(clickCount: Int, moved: CGFloat, shift: Bool) -> TriggerKind? {
        if clickCount >= 3 { return .tripleClick }
        if clickCount == 2 { return .doubleClick }
        if moved >= Self.minimumDragDistance { return .drag }
        if shift { return .shiftClick }
        return nil
    }

    private func windowChanged(from before: WindowSnapshot?, to after: WindowSnapshot?) -> Bool {
        guard let before, let after, before.id == after.id else { return false }
        return before.frame != after.frame
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
