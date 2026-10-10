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
}
