import AppKit
import BaronCore
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Runs the selection pipeline on demand. Unset until the user records it in Settings.
    public static let readSelection = Self("readSelection")
}

/// Reports a `.hotkey` trigger when the user presses the recorded shortcut.
@MainActor
public final class HotkeyMonitor {
    public var onTrigger: ((Trigger) -> Void)?

    public init() {
        KeyboardShortcuts.onKeyUp(for: .readSelection) { [weak self] in
            let location = ScreenGeometry.topLeft(fromAppKit: NSEvent.mouseLocation)
            self?.onTrigger?(Trigger(kind: .hotkey, location: location))
        }
    }

    public func setEnabled(_ enabled: Bool) {
        if enabled {
            KeyboardShortcuts.enable(.readSelection)
        } else {
            KeyboardShortcuts.disable(.readSelection)
        }
    }
}
