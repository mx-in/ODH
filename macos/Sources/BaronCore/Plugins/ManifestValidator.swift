import Foundation

/// What a host supports, for the checks that depend on it.
public struct ManifestEnvironment: Sendable {
    public var baronVersion: String
    public var platform: PluginPlatform
    /// The current API generation and the one before it.
    public var apiVersions: ClosedRange<Int>

    public init(baronVersion: String = Baron.version, platform: PluginPlatform = .macos, apiVersions: ClosedRange<Int> = Baron.apiVersions) {
        self.baronVersion = baronVersion
        self.platform = platform
        self.apiVersions = apiVersions
    }
}

public struct ManifestValidation: Sendable {
    /// Present only when there are no issues.
    public var manifest: PluginManifest?
    public var issues: [ManifestIssue]
}

/// Validates a plugin package's manifest: its structure, as the JSON Schema does, then the checks a schema can't express.
public struct ManifestValidator: Sendable {
    public var environment: ManifestEnvironment

    public init(environment: ManifestEnvironment = ManifestEnvironment()) {
        self.environment = environment
    }

    /// `package` is the plugin folder that holds `manifest.json`.
    public func validate(package: URL) -> ManifestValidation {
        guard let data = try? Data(contentsOf: package.appendingPathComponent("manifest.json")) else {
            return ManifestValidation(manifest: nil, issues: [ManifestIssue("", "manifest.json is missing or unreadable")])
        }
        return validate(data: data, package: package)
    }

    public func validate(data: Data, package: URL) -> ManifestValidation {
        guard let json = try? JSONValue(data: data) else {
            return ManifestValidation(manifest: nil, issues: [ManifestIssue("", "manifest.json is not valid JSON")])
        }
        let structural = ManifestStructure.check(json)
        guard structural.isEmpty else { return ManifestValidation(manifest: nil, issues: structural) }
        guard let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
            return ManifestValidation(manifest: nil, issues: [ManifestIssue("", "manifest.json could not be read")])
        }
        let issues = ManifestReferenceChecks.check(manifest)
            + ManifestValueChecks.check(manifest)
            + PackagePathChecks.check(manifest, package: package)
        return ManifestValidation(manifest: issues.isEmpty ? manifest : nil, issues: issues)
    }
}
