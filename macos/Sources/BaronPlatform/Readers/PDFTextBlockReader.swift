import ApplicationServices

/// Finds the PDF text block that holds the selection in Preview.
///
/// Preview shows a PDF as one `AXStaticText` per text block (wrapped lines joined with spaces), under a focused
/// group that reports the selected text but not its range. Every block reports the selected text as well; only
/// the block holding the selection reports where it is in `AXSelectedTextRange`, the others say NSNotFound.
public enum PDFTextBlockReader {
    static let staticTextRole = "AXStaticText"

    public static func selectedBlock(under focused: AXElement, limit: Int = 500) -> AXElement? {
        var queue = [focused]
        var visited = 0
        while visited < limit, !queue.isEmpty {
            let element = queue.removeFirst()
            visited += 1
            if element.role == staticTextRole {
                if let range = NativeTextWindowReader.realSelectedRange(of: element), range.length > 0 { return element }
                continue
            }
            queue += element.children
        }
        return nil
    }
}
