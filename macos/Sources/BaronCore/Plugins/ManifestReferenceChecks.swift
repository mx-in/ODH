/// IDs are unique, `dependsOn` names another preference, and every `needs` entry is granted.
enum ManifestReferenceChecks {
    static func check(_ manifest: PluginManifest) -> [ManifestIssue] {
        var issues: [ManifestIssue] = []
        let root = JSONPointer()

        var actionIDs = Set<String>()
        for (index, action) in manifest.actions.enumerated() where !actionIDs.insert(action.id).inserted {
            issues.append(.init((root / "actions" / index / "id").description, "repeats the action id \(action.id)"))
        }

        var preferenceIDs = Set<String>()
        for (index, preference) in manifest.preferences.enumerated() where !preferenceIDs.insert(preference.id).inserted {
            issues.append(.init((root / "preferences" / index / "id").description, "repeats the preference id \(preference.id)"))
        }

        for (index, preference) in manifest.preferences.enumerated() {
            for (position, target) in (preference.dependsOn ?? []).enumerated() {
                let pointer = (root / "preferences" / index / "dependsOn" / position).description
                if target == preference.id {
                    issues.append(.init(pointer, "can't name the preference itself"))
                } else if !preferenceIDs.contains(target) {
                    issues.append(.init(pointer, "names no preference: \(target)"))
                }
            }
        }

        let granted = Set(manifest.permissions)
        for (index, action) in manifest.actions.enumerated() {
            for (position, field) in (action.needs ?? []).enumerated() where !granted.contains(field.permission) {
                issues.append(.init((root / "actions" / index / "needs" / position).description, "needs the \(field.permission) permission in permissions"))
            }
        }
        return issues
    }
}
