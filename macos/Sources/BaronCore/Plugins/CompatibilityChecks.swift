/// The plugin targets an API generation, Baron version and platform this host supports.
enum CompatibilityChecks {
    static func check(_ manifest: PluginManifest, environment: ManifestEnvironment) -> [ManifestIssue] {
        var issues: [ManifestIssue] = []
        let versions = environment.apiVersions
        if manifest.apiVersion > versions.upperBound {
            issues.append(.init("/apiVersion", "needs a newer Baron: this one supports plugin API \(versions.upperBound)"))
        } else if manifest.apiVersion < versions.lowerBound {
            issues.append(.init("/apiVersion", "is too old: this Baron supports plugin API \(versions.lowerBound) to \(versions.upperBound)"))
        }
        if let minimum = manifest.minBaronVersion.flatMap(SemanticVersion.init),
           let current = SemanticVersion(environment.baronVersion), current < minimum {
            issues.append(.init("/minBaronVersion", "needs Baron \(minimum) or later; this is \(current)"))
        }
        if !manifest.platforms.contains(environment.platform) {
            issues.append(.init("/platforms", "doesn't include \(environment.platform.rawValue)"))
        }
        return issues
    }
}
