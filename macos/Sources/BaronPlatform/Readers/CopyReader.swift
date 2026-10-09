import BaronCore
import CoreGraphics
import SelectedTextKit

/// Reads the selection by making the app copy it, then puts the user's clipboard back.
///
/// SelectedTextKit saves every clipboard item (all types) before copying and
/// restores them afterwards, unless another app wrote in between.
/// The copy itself is written by the source app, so clipboard managers may still record it.
public enum CopyReader {
    public enum Method: String, CaseIterable {
        /// Presses the app's Edit › Copy menu item through Accessibility. No keystroke, no beep.
        case menu
        /// Posts ⌘C. The app may beep if nothing is selected.
        case keyboard
    }

    @MainActor
    public static func copySelection(using method: Method) async -> String? {
        let text: String?
        switch method {
        case .menu:
            text = try? await SelectedTextManager.shared.getSelectedText(strategy: .menuAction)
        case .keyboard:
            // Not SelectedTextKit's `.shortcut` strategy: it mutes the alert sound by scripting
            // System Events, which raises an Automation prompt and stalls for ~30 s until answered.
            text = await PasteboardManager.shared.getSelectedText(afterPerform: postCommandC)
        }
        return text?.isEmpty == false ? text : nil
    }

    private static func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyC: CGKeyCode = 8
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

extension ProbeField {
    public static func copy(_ method: CopyReader.Method) -> String {
        method == .menu ? menuCopy : keyCopy
    }
}
