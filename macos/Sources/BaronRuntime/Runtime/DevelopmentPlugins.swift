import BaronCore
import Foundation

/// Plugins loaded straight from folders, until installing arrives (task-008): every folder with a
/// `manifest.json` inside the development folder.
public enum DevelopmentPlugins {
    /// `~/Library/Application Support/Baron/Development`.
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Baron.name).appendingPathComponent("Development")
    }

    public struct Found: Sendable {
        public var folder: URL
        /// Nil when the manifest has issues.
        public var plugin: RuntimePlugin?
        public var issues: [ManifestIssue]
    }

    /// Validates each plugin folder; sorted by folder name. Creates the development folder if it's missing.
    public static func scan(_ folder: URL = defaultFolder, validator: ManifestValidator = ManifestValidator()) -> [Found] {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().compactMap { name in
            let package = folder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: package.appendingPathComponent("manifest.json").path) else { return nil }
            let result = validator.validate(package: package)
            return Found(folder: package, plugin: result.manifest.map { RuntimePlugin(manifest: $0, package: package) }, issues: result.issues)
        }
    }
}
