import BaronCore
import Foundation

/// Where a plugin came from. Design: 10-install-and-lifecycle.md#where-plugins-come-from
public enum PluginSource: Codable, Equatable, Sendable {
    case bundled
    case folder(String)
    case file(String)
    case link(String)
    case development(String)

    /// For the install sheet and Settings: "a folder (odh)".
    public var label: String {
        switch self {
        case .bundled: "Baron (bundled)"
        case .folder(let path): "a folder (\(URL(fileURLWithPath: path).lastPathComponent))"
        case .file(let path): "a file (\(URL(fileURLWithPath: path).lastPathComponent))"
        case .link(let url): "a link (\(URL(string: url)?.host ?? url))"
        case .development(let path): "development (\(URL(fileURLWithPath: path).lastPathComponent))"
        }
    }
}

/// A package read and validated, ready to install.
public struct PluginPackage: Sendable {
    public var manifest: PluginManifest
    /// The folder holding manifest.json.
    public var folder: URL
    public var source: PluginSource

    /// The top-level files and folders the package ships, the ones `baron pack` zips: the standard ones and any the
    /// manifest names. A plugin's source folder also holds `src`, `node_modules` and the like, which Baron ignores.
    public var shippedEntries: [String] {
        let named = [manifest.main, manifest.icon, manifest.settingsPage].compactMap { $0 } + manifest.actions.compactMap(\.icon)
        let tops = named.compactMap { $0.split(separator: "/").first { $0 != "." }.map(String.init) }.filter { $0 != ".." }
        var seen = Set<String>()
        return (PackageReader.standardEntries + tops).filter {
            seen.insert($0).inserted && FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }
}

/// Why a package can't be installed, in words for the user.
public struct InstallError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String
    public var issues: [ManifestIssue]

    public init(_ message: String, issues: [ManifestIssue] = []) {
        self.message = message
        self.issues = issues
    }

    public var description: String {
        issues.isEmpty ? message : message + " " + issues.map(\.description).joined(separator: "; ")
    }
}

/// Reads plugin folders and `.baronplugin` archives (zip). Archives may hold only regular files and folders, no
/// absolute or `..` paths, no symlinks, and at most 50 MB unpacked. Design: 10-install-and-lifecycle.md#installing
public enum PackageReader {
    public static let sizeLimit = 50 * 1024 * 1024
    /// Shipped when present; packages/cli/src/pack.ts lists the same.
    public static let standardEntries = ["manifest.json", "dist", "views", "assets", "locales", "README.md", "LICENSE"]

    public static func read(folder: URL, source: PluginSource, validator: ManifestValidator = ManifestValidator()) throws -> PluginPackage {
        let result = validator.validate(package: folder)
        guard let manifest = result.manifest else {
            throw InstallError(refusal(result.issues), issues: result.issues)
        }
        let package = PluginPackage(manifest: manifest, folder: folder, source: source)
        for entry in package.shippedEntries {
            if let symlink = firstSymlink(in: folder.appendingPathComponent(entry), named: entry) {
                throw InstallError("The package contains a symbolic link (\(symlink)), which plugins can't ship.")
            }
        }
        return package
    }

    /// Unpacks an archive into `destination` (a fresh folder) and reads it.
    public static func read(archive: URL, into destination: URL, source: PluginSource, validator: ManifestValidator = ManifestValidator()) throws -> PluginPackage {
        let names = try run(["-Z1", archive.path], failure: "It isn't a valid .baronplugin archive.")
            .split(separator: "\n").map(String.init)
        if let bad = names.first(where: { $0.hasPrefix("/") || $0.split(separator: "/").contains("..") }) {
            throw InstallError("The archive has a path outside the package (\(bad)).")
        }
        let totals = try run(["-Zt", archive.path], failure: "It isn't a valid .baronplugin archive.")
        if let bytes = totals.split(separator: ",").first(where: { $0.contains("bytes uncompressed") })?
            .split(separator: " ").first.flatMap({ Int($0) }), bytes > sizeLimit {
            throw InstallError("The package is larger than 50 MB unpacked.")
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = try run(["-qq", "-o", archive.path, "-d", destination.path], failure: "The archive couldn't be unpacked.")
        if let symlink = firstSymlink(in: destination) {
            throw InstallError("The package contains a symbolic link (\(symlink)), which plugins can't ship.")
        }
        if size(of: destination) > sizeLimit { throw InstallError("The package is larger than 50 MB unpacked.") }
        return try read(folder: manifestFolder(in: destination), source: source, validator: validator)
    }

    /// The archive's root, or its single top folder (archives made by zipping a folder).
    static func manifestFolder(in folder: URL) throws -> URL {
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path) { return folder }
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" } ?? []
        if entries.count == 1, FileManager.default.fileExists(atPath: entries[0].appendingPathComponent("manifest.json").path) { return entries[0] }
        throw InstallError("The package has no manifest.json.")
    }

    static func refusal(_ issues: [ManifestIssue]) -> String {
        if issues.contains(where: { $0.pointer == "/apiVersion" || $0.pointer == "/minBaronVersion" }) { return "It needs a newer Baron." }
        if issues.contains(where: { $0.pointer == "/platforms" }) { return "It doesn't support macOS." }
        return "Its manifest has problems."
    }

    /// The first symbolic link at or under `folder`, as a path starting with `name`.
    static func firstSymlink(in folder: URL, named name: String? = nil) -> String? {
        if let name, (try? FileManager.default.attributesOfItem(atPath: folder.path))?[.type] as? FileAttributeType == .typeSymbolicLink { return name }
        guard let walker = FileManager.default.enumerator(atPath: folder.path) else { return nil }
        while let relative = walker.nextObject() as? String {
            if walker.fileAttributes?[.type] as? FileAttributeType == .typeSymbolicLink { return name.map { "\($0)/\(relative)" } ?? relative }
        }
        return nil
    }

    static func size(of folder: URL) -> Int {
        let keys: [URLResourceKey] = [.fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return 0 }
        return walker.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: Set(keys)).fileSize } }.reduce(0, +)
    }

    private static func run(_ arguments: [String], failure: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstallError(failure) }
        return String(decoding: data, as: UTF8.self)
    }
}
