import ApplicationServices

/// Reads a slice of a native text view around its selection, never the whole document.
public enum NativeTextWindowReader {
    /// Characters read on each side of the selection.
    public static let margin = 1_000

    public struct Window {
        public let text: String
        /// The selection's UTF-16 range inside `text`.
        public let selection: Range<Int>
        public let startsAtDocumentStart: Bool
        public let endsAtDocumentEnd: Bool
    }

    public static func selectedRange(of element: AXElement) -> CFRange? {
        AXElement.range(from: element.value(kAXSelectedTextRangeAttribute))
    }

    /// The selected range when it is a real one: Preview's PDF blocks without the selection report NSNotFound.
    public static func realSelectedRange(of element: AXElement) -> CFRange? {
        guard let range = selectedRange(of: element), range.location >= 0, range.location != NSNotFound, range.length >= 0 else { return nil }
        return range
    }

    public static func window(around element: AXElement) -> Window? {
        guard let selected = realSelectedRange(of: element) else { return nil }
        let count = (element.value(kAXNumberOfCharactersAttribute) as? Int) ?? Int.max
        let start = max(0, selected.location - margin)
        let end = min(count, selected.location + selected.length + margin)
        guard end >= start else { return nil }

        let request = AXElement.value(of: CFRange(location: start, length: end - start))
        guard let text = element.value(kAXStringForRangeParameterizedAttribute, parameter: request) as? String else { return nil }

        let lower = selected.location - start
        let upper = min(lower + selected.length, text.utf16.count)
        guard lower >= 0, lower <= upper else { return nil }
        return Window(
            text: text,
            selection: lower..<upper,
            startsAtDocumentStart: start == 0,
            endsAtDocumentEnd: count != Int.max && end >= count
        )
    }
}
