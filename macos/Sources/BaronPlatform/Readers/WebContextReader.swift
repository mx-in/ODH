import ApplicationServices
import BaronCore

/// Reads the sentence or paragraph around a web selection through text markers.
public enum WebContextReader {
    public enum Unit {
        case sentence, paragraph

        var attribute: String {
            switch self {
            case .sentence: kAXSentenceTextMarkerRangeForTextMarkerParameterizedAttribute
            case .paragraph: kAXParagraphTextMarkerRangeForTextMarkerParameterizedAttribute
            }
        }

        var cap: Int {
            switch self {
            case .sentence: NativeTextContext.sentenceCap
            case .paragraph: NativeTextContext.paragraphCap
            }
        }
    }

    /// The unit around the selection's start joined with the unit around its end,
    /// so a selection that crosses a boundary keeps all of its text.
    public static func span(_ unit: Unit, around selection: AXTextMarkerRange, in element: AXElement) -> TextSpan? {
        let selectionStart = AXTextMarkerRangeCopyStartMarker(selection)
        let selectionEnd = AXTextMarkerRangeCopyEndMarker(selection)
        // A triple-click selects the paragraph with its trailing line breaks, so the end marker sits
        // in the next paragraph. Step back over those breaks to look up the last real character.
        let trailingBreaks = (WebSelectionReader.string(for: selection, in: element) ?? "")
            .reversed().prefix { $0.isNewline }.count
        var lookupEnd = selectionEnd
        for _ in 0..<trailingBreaks {
            guard let previous = WebSelectionReader.marker(element.value(kAXPreviousTextMarkerForTextMarkerParameterizedAttribute, parameter: lookupEnd)) else { break }
            lookupEnd = previous
        }
        guard
            let first = WebSelectionReader.markerRange(element.value(unit.attribute, parameter: selectionStart)),
            let last = WebSelectionReader.markerRange(element.value(unit.attribute, parameter: lookupEnd))
        else { return nil }

        let spanStart = AXTextMarkerRangeCopyStartMarker(first)
        let spanEnd = AXTextMarkerRangeCopyEndMarker(last)
        let whole = AXTextMarkerRangeCreate(kCFAllocatorDefault, spanStart, spanEnd)
        let before = AXTextMarkerRangeCreate(kCFAllocatorDefault, spanStart, selectionStart)
        guard
            let text = WebSelectionReader.string(for: whole, in: element),
            let selected = WebSelectionReader.string(for: selection, in: element)
        else { return nil }

        let prefixLength = WebSelectionReader.string(for: before, in: element)?.utf16.count ?? 0
        let start = min(prefixLength, text.utf16.count)
        let end = min(start + selected.utf16.count, text.utf16.count)
        return NativeTextContext.capped(TextSpan(text: text, selectionStart: start, selectionEnd: end), to: unit.cap)
    }

    /// The sentence or paragraph around a web selection, by the method that works for the engine.
    ///
    /// WebKit (Safari, Mail) answers correctly through text markers, and its tree hides `<br>`
    /// line breaks, so markers come first. Chromium stops markers at inline elements and pulls in
    /// neighbouring blocks at block edges, so its paragraph is rebuilt from the tree instead.
    public static func contextSpan(_ unit: Unit, around selection: AXTextMarkerRange, in element: AXElement) -> TextSpan? {
        if WebAreaReader.isChromium(element) {
            return treeSpan(unit, around: selection, in: element) ?? span(unit, around: selection, in: element)
        }
        return span(unit, around: selection, in: element) ?? treeSpan(unit, around: selection, in: element)
    }

    static func treeSpan(_ unit: Unit, around selection: AXTextMarkerRange, in element: AXElement) -> TextSpan? {
        guard
            let selected = WebSelectionReader.string(for: selection, in: element),
            let paragraph = WebTreeContextReader.paragraph(around: selection, selectedText: selected, in: element)
        else { return nil }
        switch unit {
        case .paragraph: return paragraph
        case .sentence: return NativeTextContext.sentence(in: paragraph)
        }
    }
}
