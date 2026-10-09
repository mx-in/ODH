import ApplicationServices

/// Reads `AXSelectedText`, which native text views and many web views provide.
public enum SelectedTextReader {
    public static func selectedText(of element: AXElement) -> String? {
        element.string(kAXSelectedTextAttribute)
    }
}
