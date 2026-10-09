import AppKit

/// Reports when the user moves on: a click elsewhere, a key press, scrolling, or an app switch.
///
/// Global monitors don't see events aimed at Baron's own panel, so clicks on the bar's
/// buttons never dismiss it here.
@MainActor
final class BarDismissMonitor {
    var onDismiss: (() -> Void)?
    private var monitors: [Any] = []
    private var activation: NSObjectProtocol?

    func start() {
        stop()
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.onDismiss?() }
        }) {
            monitors.append(monitor)
        }
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDismiss?() }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let activation {
            NSWorkspace.shared.notificationCenter.removeObserver(activation)
        }
        activation = nil
    }
}
