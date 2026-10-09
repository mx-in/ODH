import AppKit
import BaronCore

/// Watches mouse and keyboard events in other apps and reports selection triggers.
///
/// Global monitors only see events sent to other apps, which is what we want:
/// clicks on Baron's own bar never look like a selection.
@MainActor
public final class SelectionEventMonitor {
    public var onTrigger: ((Trigger) -> Void)?

    private var pointer = PointerTriggerDetector()
    private var keyboard = KeyboardTriggerDetector()
    private var monitors: [Any] = []

    public init() {}

    public func start() {
        guard monitors.isEmpty else { return }
        let mouse: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouse, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointer(event) }
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) }
        }) {
            monitors.append(monitor)
        }
    }

    public func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        pointer = PointerTriggerDetector()
    }

    private func handlePointer(_ event: NSEvent) {
        let location = ScreenGeometry.topLeft(fromAppKit: NSEvent.mouseLocation)
        let phase: PointerEvent.Phase
        switch event.type {
        case .leftMouseDown: phase = .down
        case .leftMouseDragged: phase = .dragged
        default: phase = .up
        }
        // Window frames only matter for spotting a window drag. The window-list query costs
        // milliseconds on the path to the bar, so skip it while dragging and on a click's mouse-up.
        let needsWindow = phase == .down || (phase == .up && pointer.endsDrag(at: location))
        let window = needsWindow ? WindowLocator.window(at: location) : nil
        let pointerEvent = PointerEvent(
            phase: phase,
            location: location,
            clickCount: event.clickCount,
            shift: event.modifierFlags.contains(.shift),
            window: window
        )
        if let trigger = pointer.handle(pointerEvent) {
            onTrigger?(trigger)
        }
    }

    private func handleKey(_ event: NSEvent) {
        guard let token = keyboard.handleKey(keyCode: event.keyCode, modifiers: Self.modifiers(of: event)) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyboardTriggerDetector.quietPeriod) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.keyboard.isLatest(token) else { return }
                let location = ScreenGeometry.topLeft(fromAppKit: NSEvent.mouseLocation)
                self.onTrigger?(Trigger(kind: .keyboard, location: location))
            }
        }
    }

    static func modifiers(of event: NSEvent) -> KeyboardTriggerDetector.Modifiers {
        var result: KeyboardTriggerDetector.Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }
}
