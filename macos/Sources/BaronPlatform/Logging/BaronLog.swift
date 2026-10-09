import BaronCore
import os

/// Unified logging for Baron. View with:
/// `log stream --predicate 'subsystem == "org.odh.baron"'`
public enum BaronLog {
    public static let selection = Logger(subsystem: Baron.bundleIdentifier, category: "selection")

    public static func record(_ outcome: PipelineOutcome, trigger: Trigger, app: String?) {
        let line = SelectionLogMessage.describe(outcome, trigger: trigger, app: app)
        // The line is built to hold no selected text, so it is safe to log publicly.
        selection.info("\(line, privacy: .public)")
    }
}
