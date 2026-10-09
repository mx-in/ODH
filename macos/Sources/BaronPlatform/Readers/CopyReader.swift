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
        /// Posts ⌘C with the system volume muted.
        case keyboard

        var strategy: TextStrategy {
            switch self {
            case .menu: .menuAction
            case .keyboard: .shortcut
            }
        }
    }

    @MainActor
    public static func copySelection(using method: Method) async -> String? {
        let text = try? await SelectedTextManager.shared.getSelectedText(strategy: method.strategy)
        return text?.isEmpty == false ? text : nil
    }
}
