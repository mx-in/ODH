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

    /// Browsers put the page title in `AXTitle` or, failing that, `AXDescription`.
    public static func title(of webArea: AXElement) -> String? {
        let title = webArea.title ?? webArea.string(kAXDescriptionAttribute)
        return title?.isEmpty == false ? title : nil
    }
}
