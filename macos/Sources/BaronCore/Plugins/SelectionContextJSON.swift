/// The `SelectionContext` an action receives, built from a selection run. Sentence, paragraph, page and window
/// come with the context builder (task-009); until then actions get the fields every selection has.
public enum SelectionContextJSON {
    public static func make(from run: SelectionRun, platform: String = "macos") -> JSONValue {
        var context: [String: JSONValue] = [
            "text": .string(run.text),
            "source": .string(run.step.rawValue),
            "editable": .bool(run.editable),
            "app": .object([
                "id": .string(run.app.bundleIdentifier ?? ""),
                "name": .string(run.app.name),
                "pid": .number(Double(run.app.processID)),
            ]),
            "platform": .string(platform),
        ]
        if let bounds = run.bounds {
            context["bounds"] = .object(["x": .number(bounds.minX), "y": .number(bounds.minY), "width": .number(bounds.width), "height": .number(bounds.height)])
        }
        return .object(context)
    }
}
