import CoreGraphics
import Testing
@testable import BaronCore

struct SelectionLogMessageTests {
    private let trigger = Trigger(kind: .drag, location: .zero)

    @Test func shownSelectionLogsLengthAndStepButNotText() {
        let secret = "my password is hunter2"
        let run = SelectionRun(trigger: trigger, text: secret, step: .axWeb, bounds: nil, items: [BarItem(id: "a", title: "A")])
        let line = SelectionLogMessage.describe(.show(run), trigger: trigger, app: "com.apple.Safari")
        #expect(!line.contains("hunter2"))
        #expect(!line.contains("password"))
        #expect(line.contains("length=\(secret.utf16.count)"))
        #expect(line.contains("step=ax-web"))
        #expect(line.contains("app=com.apple.Safari"))
    }

    @Test func rejectionLogsTheReason() {
        let line = SelectionLogMessage.describe(.rejected(.secureInput), trigger: trigger, app: nil)
        #expect(line == "trigger=drag app=unknown result=rejected reason=secureInput")
    }
}
