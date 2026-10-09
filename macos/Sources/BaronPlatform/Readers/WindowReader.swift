import ApplicationServices

/// Reads the focused window's title and, for document-based apps, its file.
public enum WindowReader {
    public static func focusedWindow(of app: AXElement) -> AXElement? {
        app.element(kAXFocusedWindowAttribute)
    }

    public static func title(of window: AXElement) -> String? {
        window.title
    }

    public static func documentURL(of window: AXElement) -> URL? {
        window.url(kAXDocumentAttribute)
    }
}
