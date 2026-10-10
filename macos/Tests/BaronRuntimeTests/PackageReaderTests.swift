import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

/// Makes plugin packages and archives for install tests.
enum Packages {
    static func folder(id: String = "org.example.pkg", version: String = "1.0.0", permissions: [String] = [], apiVersion: Int = 1,
                       main: String = "globalThis.__baronPlugin = { actions: { run() { return { type: 'copy', text: 'v' }; } } };") throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("baron-pkg-\(UUID().uuidString)").appendingPathComponent("plugin")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("dist"), withIntermediateDirectories: true)
        let manifest: [String: Any] = ["id": id, "name": "Package", "description": "D", "version": version, "apiVersion": apiVersion,
                                       "main": "dist/main.js", "permissions": permissions, "actions": [["id": "run", "title": "Run"]]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        try Data(main.utf8).write(to: folder.appendingPathComponent("dist/main.js"))
        return folder
    }

    /// Zips a folder's contents (or the folder itself) with the system zip.
    static func zip(_ folder: URL, wrapFolder: Bool = false, extraArguments: [String] = []) throws -> URL {
        let archive = folder.deletingLastPathComponent().appendingPathComponent("plugin-\(UUID().uuidString).baronplugin")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = wrapFolder ? folder.deletingLastPathComponent() : folder
        process.arguments = ["-qr"] + extraArguments + [archive.path, wrapFolder ? folder.lastPathComponent : "."]
        try process.run()
        process.waitUntilExit()
        return archive
    }

    static func scratch() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("baron-unpack-\(UUID().uuidString)")
    }
}

struct PackageReaderTests {
    @Test func readsAFolder() throws {
        let package = try PackageReader.read(folder: Packages.folder(), source: .folder("/x/plugin"))
        #expect(package.manifest.id == "org.example.pkg")
        #expect(package.source.label == "a folder (plugin)")
    }

    @Test func readsAnArchiveFlatOrWrapped() throws {
        let folder = try Packages.folder()
        for wrapped in [false, true] {
            let package = try PackageReader.read(archive: Packages.zip(folder, wrapFolder: wrapped), into: Packages.scratch(), source: .file("x.baronplugin"))
            #expect(package.manifest.version == "1.0.0")
        }
    }

    @Test func refusesNonArchives() throws {
        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("junk-\(UUID().uuidString).baronplugin")
        try Data("not a zip".utf8).write(to: junk)
        #expect(throws: InstallError("It isn't a valid .baronplugin archive.")) { try PackageReader.read(archive: junk, into: Packages.scratch(), source: .file(junk.path)) }
    }

    @Test func refusesSymlinks() throws {
        let folder = try Packages.folder()
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("dist/link.js").path, withDestinationPath: "/etc/hosts")
        let archive = try Packages.zip(folder, extraArguments: ["--symlinks"])
        do {
            _ = try PackageReader.read(archive: archive, into: Packages.scratch(), source: .file(archive.path))
            Issue.record("accepted a symlink")
        } catch let error as InstallError {
            #expect(error.message.contains("symbolic link"))
        }
    }

    @Test func ignoresASourceFoldersOtherFiles() throws {
        let folder = try Packages.folder()
        let bin = folder.appendingPathComponent("node_modules/.bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: bin.appendingPathComponent("tsc").path, withDestinationPath: "../typescript/bin/tsc")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("src"), withIntermediateDirectories: true)
        let package = try PackageReader.read(folder: folder, source: .development(folder.path))
        #expect(package.shippedEntries == ["manifest.json", "dist"])
    }

    @Test func refusesSymlinksInShippedFolders() throws {
        let folder = try Packages.folder()
        try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("dist/link.js").path, withDestinationPath: "/etc/hosts")
        #expect(throws: InstallError("The package contains a symbolic link (dist/link.js), which plugins can't ship.")) {
            try PackageReader.read(folder: folder, source: .folder(folder.path))
        }
    }

    @Test func refusesInvalidManifestsAndNewerAPIs() throws {
        let newer = try Packages.folder(apiVersion: 2)
        #expect((try? PackageReader.read(folder: newer, source: .folder(newer.path))) == nil)
        do { _ = try PackageReader.read(folder: newer, source: .folder(newer.path)) } catch let error as InstallError {
            #expect(error.message == "It needs a newer Baron.")
        }
        let broken = try Packages.folder(id: "Not Valid")
        do { _ = try PackageReader.read(folder: broken, source: .folder(broken.path)); Issue.record("accepted") } catch let error as InstallError {
            #expect(error.message == "Its manifest has problems." && error.issues.map(\.pointer) == ["/id"])
        }
    }

    @Test func refusesPathsOutsideThePackage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("baron-evil-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("escape.txt"))
        let archive = root.appendingPathComponent("evil.baronplugin")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root.appendingPathComponent("a")
        process.arguments = ["-q", archive.path, "../escape.txt"]
        try process.run()
        process.waitUntilExit()
        do { _ = try PackageReader.read(archive: archive, into: Packages.scratch(), source: .file(archive.path)); Issue.record("accepted") } catch let error as InstallError {
            #expect(error.message.contains("outside the package"))
        }
    }
}
