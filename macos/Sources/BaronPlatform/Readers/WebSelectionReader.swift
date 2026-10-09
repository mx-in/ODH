import ApplicationServices

/// Reads the selection of a web page through text markers (WebKit and Chromium).
public enum WebSelectionReader {
    /// The selected text-marker range, asked of the element first and then of its web area.
    ///
    /// The returned owner is the web area whenever there is one: Chromium scopes sentence,
    /// paragraph and bounds queries to the element they are asked of, so asking the
    /// focused span would only ever return the span's own text.
    public static func selectedRange(near element: AXElement) -> (range: AXTextMarkerRange, owner: AXElement)? {
        let area = WebAreaReader.webArea(containing: element)
        if let range = markerRange(element.value(kAXSelectedTextMarkerRangeAttribute)) {
            return (range, area ?? element)
        }
        if let area, let range = markerRange(area.value(kAXSelectedTextMarkerRangeAttribute)) {
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
