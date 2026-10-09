import AppKit
import BaronCore
import Carbon.HIToolbox

/// Collects what the gate needs from the focused element, without reading any text.
public enum GateInputReader {
    public static func read(app: NSRunningApplication, focused: AXElement?, trigger: Trigger) -> GateInput {
        GateInput(
            bundleIdentifier: app.bundleIdentifier,
            role: focused?.role,
            subrole: focused?.subrole,
            secureInputEnabled: IsSecureEventInputEnabled(),
            windowDragged: trigger.windowDragged
        )
    }
}
