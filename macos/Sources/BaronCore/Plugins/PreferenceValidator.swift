import Foundation

/// Checks a value the user typed against its preference, as the settings pane does before saving.
/// Design: 06-settings.md#validation-and-saving
public enum PreferenceValidator {
    /// Nil when the value can be saved; otherwise the message shown under the field.
    public static func problem(with value: JSONValue?, for preference: Preference) -> String? {
        let empty: Bool = switch value {
        case nil, .null?: true
        case .string(let text)?: text.trimmingCharacters(in: .whitespaces).isEmpty
        case .array(let items)?: items.isEmpty
        default: false
        }
        if empty { return preference.required == true ? "Required." : nil }
        switch (preference.type, value!) {
        case (.text, .string(let text)), (.file, .string(let text)), (.directory, .string(let text)), (.app, .string(let text)), (.secret, .string(let text)):
            if let maxLength = preference.maxLength, text.count > maxLength { return "At most \(maxLength) characters." }
            if let pattern = preference.pattern, !matches(pattern, text) { return "Doesn't have the expected format." }
            return nil
        case (.number, .number(let number)):
            if let min = preference.min, number < min { return "At least \(min.formatted())." }
            if let max = preference.max, number > max { return "At most \(max.formatted())." }
            return nil
        case (.checkbox, .bool):
            return nil
        case (.dropdown, .string(let choice)):
            if let options = preference.options, !options.contains(where: { $0.value == choice }) { return "Choose one of the options." }
            return nil
        case (.checklist, .array(let items)):
            guard items.allSatisfy({ if case .string = $0 { true } else { false } }) else { return "Choose from the options." }
            return nil
        case (.list, .array(let items)):
            let texts = items.compactMap { if case .string(let s) = $0 { s } else { nil } }
            guard texts.count == items.count else { return "Each item is text." }
            if let maxItems = preference.maxItems, texts.count > maxItems { return "At most \(maxItems) items." }
            if let pattern = preference.itemPattern, let bad = texts.first(where: { !matches(pattern, $0) }) { return "“\(bad)” doesn't have the expected format." }
            return nil
        default:
            return "Not a valid value."
        }
    }

    /// Patterns are searched for, like `when.regex` and JavaScript's `RegExp.test`; anchor with `^` and `$` to match
    /// the whole value.
    static func matches(_ pattern: String, _ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

/// What an options provider returned, read for a dropdown or checklist. Design: 06-settings.md#options-from-the-plugin
public enum PreferenceOptionsResult {
    public static func parse(_ value: JSONValue) -> Result<[Preference.Option], PluginActionResultError> {
        guard case .array(let items) = value else { return .failure(.init("The options provider didn't return a list")) }
        var options: [Preference.Option] = []
        for item in items {
            guard case .string(let id)? = item["value"], case .string(let title)? = item["title"] else {
                return .failure(.init("Each option needs a value and a title"))
            }
            options.append(Preference.Option(value: id, title: title, subtitle: item["subtitle"]?.stringValue))
        }
        return .success(options)
    }
}
