import ApplicationServices

/// Finds the web page that holds an element, and reads its URL and title.
public enum WebAreaReader {
    public static let webAreaRole = "AXWebArea"

    public static func webArea(containing element: AXElement) -> AXElement? {
        element.firstAncestor { $0.role == webAreaRole }
    }

    public static func url(of webArea: AXElement) -> URL? {
        webArea.url(kAXURLAttribute)
    }

    /// Chromium puts the page title in `AXTitle` or `AXDescription`; Safari leaves both empty,
    /// so fall back to the window title, which Safari sets to the page title.
    public static func title(of webArea: AXElement) -> String? {
        for title in [webArea.title, webArea.string(kAXDescriptionAttribute), webArea.element(kAXWindowAttribute)?.title] {
            if let title, !title.isEmpty { return title }
        }
        return nil
    }
}
