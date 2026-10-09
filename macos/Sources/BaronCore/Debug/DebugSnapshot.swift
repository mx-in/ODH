import Foundation

/// Everything the debug panel shows about the latest trigger.
///
/// Unlike the log, this holds the selected text: it stays in memory, on this Mac,
/// and only while the panel is open.
public struct DebugSnapshot: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public var label: String
        public var value: String
        public var milliseconds: Double?
    }

    public var date: Date
    public var summary: String
    public var rows: [Row]

    /// - Parameters:
    ///   - report: the probe's readings, when the selection was read; nil when the run stopped early.
    public static func make(
        outcome: PipelineOutcome, trigger: Trigger, appName: String?, bundleIdentifier: String?,
        report: ProbeReport?, date: Date = Date()
    ) -> DebugSnapshot {
        var rows = [
            Row(label: "App", value: [appName, bundleIdentifier.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")),
            Row(label: "Trigger", value: trigger.kind.rawValue + (trigger.windowDragged ? " (window drag)" : "")),
            Row(label: "Result", value: describe(outcome)),
        ]
        if case .show(let run) = outcome {
            rows.append(Row(label: "Read by", value: run.step.rawValue))
            rows.append(Row(label: "Selected text", value: run.text))
            rows.append(Row(label: "Actions", value: run.items.map(\.title).joined(separator: ", ")))
        }
        if let report {
            let value: (String) -> ProbeReading? = { field in report.readings.first { $0.field == field && $0.status == .ok } }
            let context: [(String, [String])] = [
                ("Sentence", [ProbeField.webSentence, ProbeField.nativeSentence]),
                ("Paragraph", [ProbeField.webParagraph, ProbeField.nativeParagraph]),
                ("Page URL", [ProbeField.pageURL]),
                ("Page title", [ProbeField.pageTitle]),
                ("Window title", [ProbeField.windowTitle]),
                ("Document", [ProbeField.windowDocument]),
                ("Bounds", [ProbeField.webBounds, ProbeField.nativeBounds]),
                ("Focused role", [ProbeField.focusedRole]),
            ]
            for (label, fields) in context {
                let reading = fields.lazy.compactMap(value).first
                rows.append(Row(label: label, value: reading?.value ?? "—", milliseconds: reading?.milliseconds))
            }
        }
        return DebugSnapshot(date: date, summary: SelectionLogMessage.describe(outcome, trigger: trigger, app: bundleIdentifier), rows: rows)
    }

    static func describe(_ outcome: PipelineOutcome) -> String {
        switch outcome {
        case .show: "shown"
        case .paused: "paused"
        case .rejected(let reason): "rejected by the gate: \(reason.rawValue)"
        case .noText: "no text found"
        case .superseded: "superseded by a newer trigger"
        }
    }
}
