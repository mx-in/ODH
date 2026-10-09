import ApplicationServices
import BaronCore

/// Rebuilds the paragraph around a web selection from the Accessibility tree.
///
/// Chromium stops its sentence and paragraph text markers at inline elements, so a
/// word inside a `<span>` or `<a>` comes back alone. Here we find the text element
/// under the selection, walk up to the first ancestor holding more text, and join its
/// static texts in order. The sentence is then cut with the same tokenizer as native text.
public enum WebTreeContextReader {
    static let staticTextRole = "AXStaticText"
    /// Roles browsers give inline content, which never form a paragraph of their own.
    static let inlineRoles: Set<String> = [staticTextRole, "AXLink", "AXInlineTextBox"]

    /// The text element that holds a text marker.
    public static func leaf(at marker: AXTextMarker, in area: AXElement) -> AXElement? {
        guard let value = area.value(kAXUIElementForTextMarkerParameterizedAttribute, parameter: marker),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AXElement(value as! AXUIElement)
    }

    public static func paragraph(around selection: AXTextMarkerRange, selectedText: String, in area: AXElement) -> TextSpan? {
        // Use the first selected character: a selection's start marker can sit at the end of the
        // previous block (a triple-click), which would pick the wrong paragraph.
        let start = AXTextMarkerRangeCopyStartMarker(selection)
        let firstCharacter = selectedText.isEmpty ? start
            : WebSelectionReader.marker(area.value(kAXNextTextMarkerForTextMarkerParameterizedAttribute, parameter: start)) ?? start
        guard let leaf = leaf(at: firstCharacter, in: area) ?? leaf(at: start, in: area) else { return nil }
        let leafText = leaf.string(kAXValueAttribute) ?? ""
        let selectedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)

        // The paragraph is the nearest ancestor that isn't inline text or a link. If the selection
        // runs past it (it spans blocks), widen to the next ancestor that holds all of it.
        var block = leaf.parent
        while let inline = block, inlineRoles.contains(inline.role ?? "") { block = inline.parent }
        var depth = 0
        while let candidate = block, depth < 8 {
            let (text, leafOffset) = joinedText(of: candidate, locating: leaf)
            if let leafOffset, text.utf16.count >= selectedText.utf16.count {
                let within = leafText.range(of: selectedText).map { leafText.utf16.distance(from: leafText.utf16.startIndex, to: $0.lowerBound.samePosition(in: leafText.utf16)!) } ?? 0
                let start = leafOffset + within
                let end = min(start + selectedText.utf16.count, text.utf16.count)
                return NativeTextContext.capped(TextSpan(text: text, selectionStart: start, selectionEnd: end), to: NativeTextContext.paragraphCap)
            }
            if candidate.role == WebAreaReader.webAreaRole { break }
            block = candidate.parent
            depth += 1
        }
        return nil
    }

    /// The bounds of the text element under the selection: coarse, but enough to place the bar.
    public static func leafBounds(around selection: AXTextMarkerRange, in area: AXElement) -> CGRect? {
        leaf(at: AXTextMarkerRangeCopyStartMarker(selection), in: area)?.frame
    }

    /// Joins every static text under `root` in tree order, and where `leaf` starts (UTF-16).
    static func joinedText(of root: AXElement, locating leaf: AXElement, limit: Int = 2_000) -> (String, Int?) {
        var text = ""
        var offset: Int?
        var stack = [root]
        var visited = 0
        while let element = stack.popLast(), visited < limit {
            visited += 1
            if element.role == staticTextRole {
                if offset == nil, CFEqual(element.raw, leaf.raw) { offset = text.utf16.count }
                text += element.string(kAXValueAttribute) ?? ""
                continue
            }
            stack += element.children.reversed()
        }
        return (text, offset)
    }
}
