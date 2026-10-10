import Foundation
import Testing
@testable import BaronCore

struct PackagePathChecksTests {
    let package: URL

    init() throws {
        package = FileManager.default.temporaryDirectory.appendingPathComponent("baron-paths-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try Data("<svg/>".utf8).write(to: package.appendingPathComponent("assets/icon.svg"))
        try Data("<svg/>".utf8).write(to: package.deletingLastPathComponent().appendingPathComponent("baron-outside-\(package.lastPathComponent).svg"))
        try FileManager.default.createSymbolicLink(atPath: package.appendingPathComponent("assets/link.svg").path, withDestinationPath: "icon.svg")
        try FileManager.default.createSymbolicLink(atPath: package.appendingPathComponent("assets/escape.svg").path,
                                                   withDestinationPath: "../../baron-outside-\(package.lastPathComponent).svg")
        try FileManager.default.createSymbolicLink(atPath: package.appendingPathComponent("assets/dangling.svg").path, withDestinationPath: "/nowhere/x.svg")
    }

    func issues(icon: String, main: String = "dist/main.js") -> [String] {
        let json = #"{"id": "org.example.a", "name": "A", "description": "D", "version": "1.0.0", "apiVersion": 1, "main": "\#(main)", "icon": "\#(icon)", "actions": [{"id": "a", "title": "A"}]}"#
        return ManifestValidator().validate(data: Data(json.utf8), package: package).issues.map(\.pointer)
    }

    @Test func acceptsFilesAndSymlinksInside() {
        #expect(issues(icon: "assets/icon.svg") == [])
        #expect(issues(icon: "assets/link.svg") == [])
    }

    @Test func rejectsMissingFiles() {
        #expect(issues(icon: "assets/none.svg") == ["/icon"])
    }

    @Test func rejectsSymlinksOut() {
        #expect(issues(icon: "assets/escape.svg") == ["/icon"])
        #expect(issues(icon: "assets/dangling.svg") == ["/icon"])
    }

    @Test func checksMainOnlyWhenBuilt() {
        #expect(issues(icon: "assets/icon.svg", main: "dist/none.js") == [])
    }
}
