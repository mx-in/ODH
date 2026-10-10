import CoreGraphics
import Testing
@testable import BaronCore

struct SelectionContextJSONTests {
    @Test func carriesTheFieldsEverySelectionHas() {
        let run = SelectionRun(trigger: Trigger(kind: .doubleClick, location: .zero, windowDragged: false), text: "fox", step: .axWeb,
                               bounds: CGRect(x: 1, y: 2, width: 3, height: 4), items: [],
                               app: SelectionApp(bundleIdentifier: "com.apple.Safari", name: "Safari", processID: 42), editable: true)
        #expect(SelectionContextJSON.make(from: run) == .object([
            "text": .string("fox"), "source": .string("ax-web"), "editable": .bool(true),
            "app": .object(["id": .string("com.apple.Safari"), "name": .string("Safari"), "pid": .number(42)]),
            "platform": .string("macos"),
            "bounds": .object(["x": .number(1), "y": .number(2), "width": .number(3), "height": .number(4)]),
        ]))
    }

    let captured = CapturedContext(
        window: .init(title: "Notes.txt", documentURL: "file:///Notes.txt"),
        page: .init(url: "https://example.com/", title: "Example"),
        sentence: TextSpan(text: "The 🦊 fox.", selectionStart: 7, selectionEnd: 10),
        paragraph: TextSpan(text: "The 🦊 fox. It runs.", selectionStart: 7, selectionEnd: 10, truncated: true))

    @Test func addsOnlyTheFieldsAskedFor() throws {
        let run = SelectionRun(trigger: Trigger(kind: .doubleClick, location: .zero, windowDragged: false), text: "fox", step: .axText, bounds: nil, items: [])
        guard case .object(let none) = SelectionContextJSON.make(from: run, context: captured, fields: []) else { return }
        #expect(none["sentence"] == nil && none["paragraph"] == nil && none["page"] == nil && none["window"] == nil)

        guard case .object(let some) = SelectionContextJSON.make(from: run, context: captured, fields: [.sentence, .window]) else { return }
        #expect(some["sentence"] == .object(["text": .string("The 🦊 fox."), "selectionStart": .number(7), "selectionEnd": .number(10), "truncated": .bool(false)]))
        #expect(some["window"] == .object(["title": .string("Notes.txt"), "documentUrl": .string("file:///Notes.txt")]))
        #expect(some["paragraph"] == nil && some["page"] == nil)

        guard case .object(let all) = SelectionContextJSON.make(from: run, context: captured, fields: Set(ContextField.allCases)) else { return }
        #expect(all["page"] == .object(["url": .string("https://example.com/"), "title": .string("Example")]))
        guard case .object(let paragraph) = try #require(all["paragraph"]) else { return }
        #expect(paragraph["truncated"] == .bool(true))
    }

    @Test func leavesOutFieldsThatWerentRead() {
        let run = SelectionRun(trigger: Trigger(kind: .doubleClick, location: .zero, windowDragged: false), text: "fox", step: .menuCopy, bounds: nil, items: [])
        guard case .object(let context) = SelectionContextJSON.make(from: run, context: CapturedContext(), fields: Set(ContextField.allCases)) else { return }
        #expect(Set(context.keys) == ["text", "source", "editable", "app", "platform"])
    }
}
