import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

struct DevelopmentPluginsTests {
    @Test func findsValidAndInvalidPluginFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("baron-dev-\(UUID().uuidString)")
        let good = try makePlugin("globalThis.__baronPlugin = { actions: { run() {} } };")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: good.package, to: root.appendingPathComponent("b-good"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a-bad"), withIntermediateDirectories: true)
        try Data(#"{"id": "Bad"}"#.utf8).write(to: root.appendingPathComponent("a-bad/manifest.json"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("c-not-a-plugin"), withIntermediateDirectories: true)

        let found = DevelopmentPlugins.scan(root)
        #expect(found.map(\.folder.lastPathComponent) == ["a-bad", "b-good"])
        #expect(found[0].plugin == nil && found[0].issues.map(\.pointer).contains("/id"))
        #expect(found[1].plugin?.id == "org.example.test" && found[1].issues.isEmpty)
    }

    @Test func createsAMissingFolder() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("baron-dev-\(UUID().uuidString)")
        #expect(DevelopmentPlugins.scan(root).isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.path))
    }
}
