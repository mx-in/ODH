/// The `SelectionContext` an action receives: the fields every selection has, plus those of the captured context
/// that are in `fields` (the action's `needs` that its plugin is granted). Design: docs/tec-design.md#context-capture
public enum SelectionContextJSON {
    public static func make(from run: SelectionRun, context captured: CapturedContext? = nil, fields: Set<ContextField> = [],
                            platform: String = "macos") -> JSONValue {
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
        if let captured {
            if fields.contains(.window), let window = captured.window {
                var object: [String: JSONValue] = [:]
                if let title = window.title { object["title"] = .string(title) }
                if let url = window.documentURL { object["documentUrl"] = .string(url) }
                context["window"] = .object(object)
            }
            if fields.contains(.page), let page = captured.page {
                var object: [String: JSONValue] = ["url": .string(page.url)]
                if let title = page.title { object["title"] = .string(title) }
                context["page"] = .object(object)
            }
            if fields.contains(.sentence), let sentence = captured.sentence { context["sentence"] = span(sentence) }
            if fields.contains(.paragraph), let paragraph = captured.paragraph { context["paragraph"] = span(paragraph) }
        }
        return .object(context)
    }

    static func span(_ span: TextSpan) -> JSONValue {
        .object([
            "text": .string(span.text),
            "selectionStart": .number(Double(span.selectionStart)),
            "selectionEnd": .number(Double(span.selectionEnd)),
            "truncated": .bool(span.truncated),
        ])
    }
}
