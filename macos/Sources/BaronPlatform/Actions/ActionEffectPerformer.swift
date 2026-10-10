import AppKit
import BaronCore

/// Carries out an action's effect on macOS.
@MainActor
public enum ActionEffectPerformer {
    public static func perform(_ effect: ActionEffect) {
        switch effect {
        case .copy(let text):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .replace(let text):
            SelectionReplacer.replace(with: text)
        }
    }
}
