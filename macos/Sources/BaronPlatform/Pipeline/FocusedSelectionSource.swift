import AppKit
import BaronCore

/// The frontmost app and its focused element, read once per trigger.
@MainActor
public final class FocusedSelectionSource: SelectionSource {
    public let app: NSRunningApplication
    public let focused: AXElement?

    public var bundleIdentifier: String? { app.bundleIdentifier }

    public var selectionApp: SelectionApp {
        SelectionApp(bundleIdentifier: app.bundleIdentifier, name: app.localizedName ?? app.bundleIdentifier ?? "", processID: app.processIdentifier)
    }

    /// The focused element takes new selected text, and isn't a password field.
    public var isEditable: Bool {
        guard let focused, focused.subrole != SecureInputRule.secureSubrole else { return false }
        return focused.isSettable(kAXSelectedTextAttribute)
    }

    /// Nil when there is no frontmost app.
    public static func current() -> FocusedSelectionSource? {
        guard let app = FocusedElementReader.frontmostApplication else { return nil }
        return FocusedSelectionSource(app: app)
    }

    init(app: NSRunningApplication) {
        self.app = app
        let element = AXElement.application(pid: app.processIdentifier)
        // Chromium apps only answer once their accessibility tree is switched on.
        AccessibilityWaker.wake(element)
        focused = FocusedElementReader.focusedElement(in: element)
    }

    public func gateInput(for trigger: Trigger) -> GateInput {
        GateInputReader.read(app: app, focused: focused, trigger: trigger)
    }

    public func retrievalChain() -> RetrievalChain {
        .standard(for: focused)
    }

    public func selectionBounds(after step: RetrievalStep) -> CGRect? {
        guard let focused else { return nil }
        switch step {
        case .axText:
            return SelectionBoundsReader.bounds(ofNativeSelectionIn: focused)
        case .axWeb:
            return WebSelectionReader.selectedRange(near: focused).flatMap { SelectionBoundsReader.bounds(ofWebSelection: $0.range, in: $0.owner) }
        case .menuCopy, .keyCopy:
            // The app may still report bounds even when its text needed copying.
            return SelectionBoundsReader.bounds(ofNativeSelectionIn: focused)
        }
    }
}
