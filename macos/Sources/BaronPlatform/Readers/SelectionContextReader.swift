import BaronCore
import Foundation

/// Reads the context fields around a selection from the readers the probe uses, within a time budget.
/// Design: docs/tec-design.md#context-capture
public enum SelectionContextReader {
    /// Fields still unread when it runs out are left out.
    public static let budget: Duration = .milliseconds(200)

    /// Where to read from, taken on the main actor when the text was read.
    public struct Target: Sendable {
        public let app: AXElement
        public let focused: AXElement?
        public let step: RetrievalStep
        public let bundleIdentifier: String?
        /// The user allowed asking browsers for the page through AppleScript when Accessibility has no address.
        public let askBrowsers: Bool

        public init(app: AXElement, focused: AXElement?, step: RetrievalStep, bundleIdentifier: String? = nil, askBrowsers: Bool = false) {
            self.app = app
            self.focused = focused
            self.step = step
            self.bundleIdentifier = bundleIdentifier
            self.askBrowsers = askBrowsers
        }
    }

    public static func read(_ fields: Set<ContextField>, from target: Target, budget: Duration = budget) -> CapturedContext {
        var context = CapturedContext()
        // Text that needed copying comes without context: its focused element may not be the selection's.
        guard !fields.isEmpty, target.step == .axText || target.step == .axWeb else { return context }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: budget)
        var inTime: Bool { clock.now < deadline }

        if fields.contains(.window), let window = WindowReader.focusedWindow(of: target.app) {
            context.window = .init(title: WindowReader.title(of: window), documentURL: WindowReader.documentURL(of: window)?.absoluteString)
        }
        guard let focused = target.focused else { return context }
        if fields.contains(.page), inTime {
            if let area = WebAreaReader.webArea(containing: focused), let url = WebAreaReader.url(of: area) {
                context.page = .init(url: url.absoluteString, title: WebAreaReader.title(of: area))
            } else if target.askBrowsers, target.step == .axWeb, let id = target.bundleIdentifier {
                context.page = BrowserPageReader.page(of: id)
            }
        }
        let wantsSentence = fields.contains(.sentence), wantsParagraph = fields.contains(.paragraph)
        guard wantsSentence || wantsParagraph, inTime else { return context }

        switch target.step {
        case .axWeb:
            guard let web = WebSelectionReader.selectedRange(near: focused) else { break }
            if wantsParagraph { context.paragraph = WebContextReader.contextSpan(.paragraph, around: web.range, in: web.owner) }
            if wantsSentence, inTime { context.sentence = WebContextReader.contextSpan(.sentence, around: web.range, in: web.owner) }
        default:
            // A PDF in Preview: the focused group has no range, but the block holding the selection does.
            guard let window = NativeTextWindowReader.window(around: focused)
                    ?? PDFTextBlockReader.selectedBlock(under: focused).flatMap(NativeTextWindowReader.window(around:)),
                  let paragraph = NativeTextContext.paragraph(in: window.text, selection: window.selection,
                                                              windowStartsAtDocumentStart: window.startsAtDocumentStart,
                                                              windowEndsAtDocumentEnd: window.endsAtDocumentEnd) else { break }
            if wantsParagraph { context.paragraph = paragraph }
            if wantsSentence { context.sentence = NativeTextContext.sentence(in: paragraph) }
        }
        return context
    }
}
