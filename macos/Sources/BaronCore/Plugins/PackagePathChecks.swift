import Foundation

/// Files the manifest names exist and stay inside the package, even through symlinks.
/// `main` may not be built yet, so it is only checked when present; installing checks it again.
enum PackagePathChecks {
    static func check(_ manifest: PluginManifest, package: URL) -> [ManifestIssue] {
        let root = JSONPointer()
        var paths: [(JSONPointer, String, mustExist: Bool)] = [(root / "main", manifest.main, false)]
        if let icon = manifest.icon { paths.append((root / "icon", icon, true)) }
        if let page = manifest.settingsPage { paths.append((root / "settingsPage", page, true)) }
        for (index, action) in manifest.actions.enumerated() {
            if let icon = action.icon { paths.append((root / "actions" / index / "icon", icon, true)) }
        }
        return paths.compactMap { pointer, path, mustExist in
            switch locate(path, in: package) {
            case .inside: nil
            case .missing: mustExist ? ManifestIssue(pointer.description, "names a file that doesn't exist: \(path)") : nil
            case .outside: ManifestIssue(pointer.description, "leads outside the package: \(path)")
            }
        }
    }

    enum Location { case inside, missing, outside }

    static func locate(_ path: String, in package: URL) -> Location {
        let base = package.standardizedFileURL.resolvingSymlinksInPath().path
        let file = package.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: file.path) else {
            // A dangling symlink still counts as leading somewhere.
            let isLink = (try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) != nil
            return isLink ? .outside : .missing
        }
        let resolved = file.standardizedFileURL.resolvingSymlinksInPath().path
        return resolved.hasPrefix(base + "/") ? .inside : .outside
    }
}
