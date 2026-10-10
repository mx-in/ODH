import BaronCore

/// `host.preferences` until the settings store arrives (task-007): each declared preference's default.
/// Secrets, buttons and headings never appear.
public enum PreferenceDefaults {
    public static func values(for manifest: PluginManifest) -> [String: JSONValue] {
        var values: [String: JSONValue] = [:]
        for preference in manifest.preferences where ![.secret, .button, .heading].contains(preference.type) {
            switch preference.default {
            case .string(let text)?: values[preference.id] = .string(text)
            case .number(let number)?: values[preference.id] = .number(number)
            case .bool(let flag)?: values[preference.id] = .bool(flag)
            case .strings(let list)?: values[preference.id] = .array(list.map(JSONValue.string))
            case nil: break
            }
        }
        return values
    }
}
