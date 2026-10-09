/// A stretch of text around the selection, such as its sentence or paragraph.
///
/// Offsets are UTF-16 code units, the unit `CFRange` and JavaScript string
/// indices both use, so plugins can slice `text` without converting.
public struct TextSpan: Equatable, Codable, Sendable {
    public var text: String
    public var selectionStart: Int
    public var selectionEnd: Int
    public var truncated: Bool

    public init(text: String, selectionStart: Int, selectionEnd: Int, truncated: Bool = false) {
        self.text = text
        self.selectionStart = selectionStart
        self.selectionEnd = selectionEnd
        self.truncated = truncated
    }
}
