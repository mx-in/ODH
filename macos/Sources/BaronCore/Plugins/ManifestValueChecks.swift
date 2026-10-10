/// Bounds are in order, and defaults fall within their options or range.
enum ManifestValueChecks {
    static func check(_ manifest: PluginManifest) -> [ManifestIssue] {
        var issues: [ManifestIssue] = []
        let root = JSONPointer()

        for (index, action) in manifest.actions.enumerated() {
            if let min = action.when?.minLength, let max = action.when?.maxLength, min > max {
                issues.append(.init((root / "actions" / index / "when" / "minLength").description, "is more than maxLength (\(max))"))
            }
        }

        for (index, preference) in manifest.preferences.enumerated() {
            let here = root / "preferences" / index
            if let min = preference.min, let max = preference.max, min > max {
                issues.append(.init((here / "min").description, "is more than max (\(max.formatted()))"))
            }
            switch preference.default {
            case .number(let value)?:
                if let min = preference.min, value < min { issues.append(.init((here / "default").description, "is less than min (\(min.formatted()))")) }
                else if let max = preference.max, value > max { issues.append(.init((here / "default").description, "is more than max (\(max.formatted()))")) }
            case .string(let value)? where preference.type == .dropdown:
                if let options = preference.options, !options.contains(where: { $0.value == value }) {
                    issues.append(.init((here / "default").description, "is not one of the options: \(value)"))
                }
            case .strings(let values)? where preference.type == .checklist:
                if let options = preference.options {
                    for (position, value) in values.enumerated() where !options.contains(where: { $0.value == value }) {
                        issues.append(.init((here / "default" / position).description, "is not one of the options: \(value)"))
                    }
                }
            default:
                break
            }
        }
        return issues
    }
}
