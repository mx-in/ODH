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
        guard
            let first = WebSelectionReader.markerRange(element.value(unit.attribute, parameter: selectionStart)),
            let last = WebSelectionReader.markerRange(element.value(unit.attribute, parameter: selectionEnd))
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

    /// The text-marker answer, or the tree-rebuilt one when markers stop at an inline element
    /// and return no more than the selection itself (Chromium).
    public static func contextSpan(_ unit: Unit, around selection: AXTextMarkerRange, in element: AXElement) -> TextSpan? {
        let direct = span(unit, around: selection, in: element)
        if let direct, direct.text.utf16.count > direct.selectionEnd - direct.selectionStart { return direct }
        guard
            let selected = WebSelectionReader.string(for: selection, in: element),
            let paragraph = WebTreeContextReader.paragraph(around: selection, selectedText: selected, in: element)
        else { return direct }
        switch unit {
        case .paragraph: return paragraph
        case .sentence: return NativeTextContext.sentence(in: paragraph) ?? direct
        }
    }
}
