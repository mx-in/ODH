import Foundation
import Testing
@testable import BaronCore

struct BuiltInActionsTests {
    @Test func copyCopiesTheText() {
        #expect(CopyAction().effect(for: "hello") == .copy("hello"))
    }

    @Test func searchFillsTheTemplate() {
        let action = SearchAction(template: "https://example.com/s?q={query}")
        #expect(action.url(for: "  fish & chips  ")?.absoluteString == "https://example.com/s?q=fish%20%26%20chips")
    }

    @Test func searchEncodesNonASCII() {
        let url = SearchAction().url(for: "单词")
        #expect(url?.absoluteString == "https://www.google.com/search?q=%E5%8D%95%E8%AF%8D")
    }

    @Test func searchNeedsAPlaceholder() {
        #expect(SearchAction(template: "https://example.com").url(for: "x") == nil)
    }

    @Test func searchSkipsBlankOrHugeSelections() {
        #expect(!SearchAction().applies(to: "   "))
        #expect(!SearchAction().applies(to: String(repeating: "a", count: 501)))
        #expect(SearchAction().applies(to: "word"))
    }

    @Test func openLinkFindsTheFirstLink() {
        let action = OpenLinkAction()
        #expect(action.link(in: "see https://odh.example/docs and more")?.absoluteString == "https://odh.example/docs")
        #expect(action.applies(to: "visit example.com today"))
        #expect(!action.applies(to: "no links here"))
    }

    @Test func linkActionAppearsOnlyWithALink() {
        let actions = BuiltInActions()
        #expect(actions.items(for: "plain words").map(\.id) == ["builtin.copy", "builtin.search"])
        #expect(actions.items(for: "https://a.example").map(\.id) == ["builtin.copy", "builtin.search", "builtin.openLink"])
    }

    @Test func effectIsLookedUpByItemID() {
        let actions = BuiltInActions()
        #expect(actions.effect(of: "builtin.copy", for: "x") == .copy("x"))
        #expect(actions.effect(of: "missing", for: "x") == nil)
    }
}
