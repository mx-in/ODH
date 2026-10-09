import AppKit
import ApplicationServices

/// Finds the frontmost app and the element that holds keyboard focus inside it.
public enum FocusedElementReader {
    public static var frontmostApplication: NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    /// The focused element, asked of the app itself rather than the system-wide element,
    /// which can answer with a stale element from a previously focused app.
    public static func focusedElement(in app: AXElement) -> AXElement? {
        app.element(kAXFocusedUIElementAttribute)
    }
}
