import CoreGraphics
import Testing
@testable import BaronCore

struct DebugSnapshotTests {
    private let trigger = Trigger(kind: .doubleClick, location: .zero)

    private func value(_ snapshot: DebugSnapshot, _ label: String) -> String? {
        snapshot.rows.first { $0.label == label }?.value
    }

    @Test func shownRunListsTextAppAndContext() {
        let run = SelectionRun(trigger: trigger, text: "quokka", step: .axWeb, bounds: nil, items: [BarItem(id: "c", title: "Copy")])
        var report = ProbeReport(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome")
        report.record(ProbeField.webParagraph, value: "The [quokka] runs.", milliseconds: 1.5)
        report.record(ProbeField.nativeParagraph, value: nil, milliseconds: 0.1)
        report.record(ProbeField.pageURL, value: "file:///f.html", milliseconds: 0.2)

        let snapshot = DebugSnapshot.make(outcome: .show(run), trigger: trigger, appName: "Google Chrome",
                                          bundleIdentifier: "com.google.Chrome", report: report)
        #expect(value(snapshot, "App") == "Google Chrome (com.google.Chrome)")
        #expect(value(snapshot, "Selected text") == "quokka")
        #expect(value(snapshot, "Read by") == "ax-web")
        #expect(value(snapshot, "Paragraph") == "The [quokka] runs.")
        #expect(snapshot.rows.first { $0.label == "Paragraph" }?.milliseconds == 1.5)
        #expect(value(snapshot, "Page URL") == "file:///f.html")
        #expect(value(snapshot, "Sentence") == "—")
    }

    @Test func rejectedRunShowsTheReason() {
        let snapshot = DebugSnapshot.make(outcome: .rejected(.secureInput), trigger: trigger, appName: "Safari",
                                          bundleIdentifier: "com.apple.Safari", report: nil)
        #expect(value(snapshot, "Result") == "rejected by the gate: secureInput")
        #expect(value(snapshot, "Selected text") == nil)
    }
}
