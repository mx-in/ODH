import ApplicationServices

/// Reads the selection of a web page through text markers (WebKit and Chromium).
public enum WebSelectionReader {
    /// The selected text-marker range, asked of the element first and then of its web area.
    public static func selectedRange(near element: AXElement) -> (range: AXTextMarkerRange, owner: AXElement)? {
        if let range = markerRange(element.value(kAXSelectedTextMarkerRangeAttribute)) {
            return (range, element)
        }
        if let area = WebAreaReader.webArea(containing: element),
           let range = markerRange(area.value(kAXSelectedTextMarkerRangeAttribute)) {
            return (range, area)
        }
        return nil
    }

    public static func string(for range: AXTextMarkerRange, in element: AXElement) -> String? {
        element.value(kAXStringForTextMarkerRangeParameterizedAttribute, parameter: range) as? String
    }

    static func markerRange(_ value: CFTypeRef?) -> AXTextMarkerRange? {
        guard let value, CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() else { return nil }
        return (value as! AXTextMarkerRange)
    }

    static func marker(_ value: CFTypeRef?) -> AXTextMarker? {
        guard let value, CFGetTypeID(value) == AXTextMarkerGetTypeID() else { return nil }
        return (value as! AXTextMarker)
    }
}
