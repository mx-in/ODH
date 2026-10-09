/// Turns a pipeline outcome into a log line that never contains the selected text.
///
/// Selections can hold passwords, messages or anything else, so the log records
/// only what is needed to debug the pipeline: the trigger, the app, the step and a length.
public enum SelectionLogMessage {
    public static func describe(_ outcome: PipelineOutcome, trigger: Trigger, app: String?) -> String {
        let prefix = "trigger=\(trigger.kind.rawValue) app=\(app ?? "unknown")"
        switch outcome {
        case .show(let run):
            return "\(prefix) result=shown step=\(run.step.rawValue) length=\(run.text.utf16.count) actions=\(run.items.count) bounds=\(run.bounds == nil ? "no" : "yes")"
        case .paused:
            return "\(prefix) result=paused"
        case .rejected(let reason):
            return "\(prefix) result=rejected reason=\(reason.rawValue)"
        case .noText:
            return "\(prefix) result=no-text"
        case .superseded:
            return "\(prefix) result=superseded"
        }
    }
}
