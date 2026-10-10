import Foundation
import Testing
@testable import BaronCore

struct ManifestStructureTests {
    let minimal: [String: Any] = [
        "id": "org.example.upper", "name": "Upper", "description": "Uppercases", "version": "1.0.0",
        "apiVersion": 1, "main": "dist/main.js", "actions": [["id": "upper", "title": "UPPER"]],
    ]

    func pointers(_ manifest: [String: Any]) throws -> [String] {
        let value = try JSONValue(data: JSONSerialization.data(withJSONObject: manifest))
        return ManifestStructure.check(value).map(\.pointer).sorted()
    }

    @Test func acceptsAMinimalManifest() throws {
        #expect(try pointers(minimal) == [])
    }

    @Test func tellsBooleansFromNumbers() throws {
        #expect(try JSONValue(data: Data("[true, 1, 1.5]".utf8)) == .array([.bool(true), .number(1), .number(1.5)]))
        var manifest = minimal
        manifest["apiVersion"] = true
        #expect(try pointers(manifest) == ["/apiVersion"])
    }

    @Test func pointsAtMissingAndUnknownFields() throws {
        var manifest = minimal
        manifest["id"] = nil
        manifest["permisions"] = ["secrets"]
        #expect(try pointers(manifest) == ["/id", "/permisions"])
    }

    @Test func dollarMatchesOnlyAtTheEnd() throws {
        var manifest = minimal
        manifest["id"] = "org.example.upper\n"
        #expect(try pointers(manifest) == ["/id"])
    }

    @Test func escapesPointerSegments() {
        #expect((JSONPointer() / "a/b" / "c~d" / 0).description == "/a~1b/c~0d/0")
    }

    @Test func reportsTheFieldOfTheMatchingAlternative() throws {
        var manifest = minimal
        manifest["actions"] = [["id": "upper", "title": "UPPER", "when": ["apps": [["ios": "x"]]]]]
        #expect(try pointers(manifest) == ["/actions/0/when/apps/0/ios"])
    }

    @Test(arguments: ManifestCorpusCase.all)
    func agreesWithTheSchemaOnTheCorpus(_ corpusCase: ManifestCorpusCase) throws {
        let found = ManifestStructure.check(try JSONValue(data: corpusCase.manifestData())).map(\.pointer)
        switch corpusCase.expectation {
        case .valid, .rejectedBySemantics: #expect(found == [])
        case .rejectedBySchema(let pointer): #expect(found == [pointer])
        }
    }

    @Test func corpusIsThere() {
        #expect(ManifestCorpusCase.all.count >= 30)
    }
}
