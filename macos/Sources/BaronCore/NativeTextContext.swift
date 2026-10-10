import Foundation
import NaturalLanguage

/// Cuts the paragraph and sentence around a selection out of a window of text.
///
/// Native text views only give us a slice of their content (we never read a
/// whole document), so a paragraph that runs past the slice's edge is marked
/// `truncated`.
public enum NativeTextContext {
    public static let paragraphCap = 4_000
    public static let sentenceCap = 1_000

    /// - Parameters:
    ///   - window: the text read around the selection.
    ///   - selection: the selection's UTF-16 range inside `window`.
    ///   - windowStartsAtDocumentStart: true when nothing precedes `window`.
    ///   - windowEndsAtDocumentEnd: true when nothing follows `window`.
    public static func paragraph(
        in window: String,
        selection: Range<Int>,
        windowStartsAtDocumentStart: Bool,
        windowEndsAtDocumentEnd: Bool
    ) -> TextSpan? {
        let units = Array(window.utf16)
        guard selection.lowerBound >= 0, selection.upperBound <= units.count else { return nil }

        // A triple-click selects the paragraph with its line break; expand from the last
        // selected character that isn't a break, or the next paragraph gets pulled in.
        var last = selection.upperBound
        while last > selection.lowerBound, isLineBreak(units[last - 1]) { last -= 1 }
        let selection = selection.lowerBound..<last

        var start = selection.lowerBound
        while start > 0, !isLineBreak(units[start - 1]) { start -= 1 }
        var end = selection.upperBound
        while end < units.count, !isLineBreak(units[end]) { end += 1 }

        let hitStart = start == 0 && !windowStartsAtDocumentStart
        let hitEnd = end == units.count && !windowEndsAtDocumentEnd
        return capped(units: units, start: start, end: end, selection: selection, cap: paragraphCap, cutAlready: hitStart || hitEnd)
    }

    /// The sentence (or sentences, when the selection crosses a boundary) that holds the selection.
    public static func sentence(in paragraph: TextSpan) -> TextSpan? {
        let text = paragraph.text
        let units = Array(text.utf16)
        let selection = paragraph.selectionStart..<paragraph.selectionEnd
        guard selection.upperBound <= units.count else { return nil }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var start: Int?
        var end: Int?
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let lower = range.lowerBound.utf16Offset(in: text)
            let upper = range.upperBound.utf16Offset(in: text)
            // A sentence counts when it overlaps the selection, or holds an empty selection.
            let overlaps = lower < selection.upperBound && upper > selection.lowerBound
            let holdsCaret = selection.isEmpty && lower <= selection.lowerBound && selection.lowerBound <= upper
            if overlaps || holdsCaret {
                start = min(start ?? lower, lower)
                end = max(end ?? upper, upper)
            }
            return true
        }
        guard var start, var end else { return nil }

        // NLTokenizer keeps trailing whitespace on a sentence; drop it.
        while end > start, isWhitespace(units[end - 1]), end > selection.upperBound { end -= 1 }
        while start < end, isWhitespace(units[start]), start < selection.lowerBound { start += 1 }
        let edgeIsCut = paragraph.truncated && (start == 0 || end == units.count)
        return capped(units: units, start: start, end: end, selection: selection, cap: sentenceCap, cutAlready: edgeIsCut)
    }

    /// Shortens a span to `cap` UTF-16 units, keeping the selection and centring it in what is left.
    public static func capped(_ span: TextSpan, to cap: Int) -> TextSpan {
        let units = Array(span.text.utf16)
        return capped(units: units, start: 0, end: units.count, selection: span.selectionStart..<span.selectionEnd, cap: cap, cutAlready: span.truncated)
    }

    private static func capped(units: [UInt16], start: Int, end: Int, selection: Range<Int>, cap: Int, cutAlready: Bool) -> TextSpan {
        var start = start
        var end = end
        var truncated = cutAlready
        if end - start > cap {
            truncated = true
            let room = max(cap - selection.count, 0)
            start = max(start, selection.lowerBound - room / 2)
            end = min(end, max(selection.upperBound, start + cap))
            start = max(start, end - cap)
            // Cut between characters, not inside a surrogate pair (an emoji would decode as U+FFFD).
            if start > 0, UTF16.isTrailSurrogate(units[start]) { start += 1 }
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
        }
        let text = String(decoding: units[start..<end], as: UTF16.self)
        return TextSpan(text: text, selectionStart: selection.lowerBound - start, selectionEnd: selection.upperBound - start, truncated: truncated)
    }

    private static func isLineBreak(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || isLineBreak(unit) || unit == 0x3000
    }
}
