import Foundation

/// Context read around a selection right after its text, before any action asks for it.
/// Each action then gets only the fields it `needs` and its plugin was granted (`SelectionContextJSON`).
/// Design: docs/tec-design.md#context-capture
public struct CapturedContext: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        public var title: String?
        public var documentURL: String?

        public init(title: String? = nil, documentURL: String? = nil) {
            self.title = title
            self.documentURL = documentURL
        }
    }

    public struct Page: Equatable, Sendable {
        public var url: String
        public var title: String?

        public init(url: String, title: String? = nil) {
            self.url = url
            self.title = title
        }
    }

    public var window: Window?
    public var page: Page?
    public var sentence: TextSpan?
    public var paragraph: TextSpan?

    public init(window: Window? = nil, page: Page? = nil, sentence: TextSpan? = nil, paragraph: TextSpan? = nil) {
        self.window = window
        self.page = page
        self.sentence = sentence
        self.paragraph = paragraph
    }

    /// The fields that were read.
    public var fields: Set<ContextField> {
        var fields = Set<ContextField>()
        if window != nil { fields.insert(.window) }
        if page != nil { fields.insert(.page) }
        if sentence != nil { fields.insert(.sentence) }
        if paragraph != nil { fields.insert(.paragraph) }
        return fields
    }
}
