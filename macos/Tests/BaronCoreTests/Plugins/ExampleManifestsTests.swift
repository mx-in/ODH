import Foundation
import Testing
@testable import BaronCore

/// Every example plugin in examples/ is accepted by Baron's validator.
struct ExampleManifestsTests {
    static let examples: [URL] = {
        let root = ManifestCorpusCase.root.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("examples")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.sorted().map { root.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }
    }()

    @Test func thereAreExamples() {
        #expect(!Self.examples.isEmpty)
    }

    @Test(arguments: examples)
    func validates(_ folder: URL) {
        #expect(ManifestValidator().validate(package: folder).issues == [])
    }
}
