import Foundation
import Testing
@testable import BaronCore

struct ManifestValidatorTests {
    let validator = ManifestValidator(environment: ManifestEnvironment(baronVersion: "0.1.0", platform: .macos, apiVersions: 1...1))

    func issues(_ manifest: String) -> [String] {
        validator.validate(data: Data(manifest.utf8), package: URL(fileURLWithPath: "/nonexistent")).issues.map(\.pointer)
    }

    static let head = #""id": "org.example.upper", "name": "Upper", "description": "D", "version": "1.0.0", "apiVersion": 1, "main": "dist/main.js""#

    @Test func returnsTheManifestWhenValid() {
        let result = validator.validate(data: Data("{\(Self.head), \"actions\": [{\"id\": \"upper\", \"title\": \"UPPER\"}]}".utf8), package: URL(fileURLWithPath: "/nonexistent"))
        #expect(result.issues == [])
        #expect(result.manifest?.id == "org.example.upper")
    }

    @Test func reportsBrokenJSONAtTheRoot() {
        #expect(issues("{") == [""])
    }

    @Test func stopsAtStructuralIssues() {
        #expect(issues("{\(Self.head), \"actions\": [{\"id\": \"upper\", \"title\": \"UPPER\"}, {\"id\": \"upper\"}]}") == ["/actions/1/title"])
    }

    @Test func rejectsRepeatedIDs() {
        #expect(issues("{\(Self.head), \"actions\": [{\"id\": \"a\", \"title\": \"A\"}, {\"id\": \"a\", \"title\": \"B\"}, {\"id\": \"a\", \"title\": \"C\"}]}") == ["/actions/1/id", "/actions/2/id"])
    }

    @Test func rejectsDependsOnItselfOrNothing() {
        let manifest = "{\(Self.head), \"actions\": [{\"id\": \"a\", \"title\": \"A\"}], \"preferences\": [{\"id\": \"deck\", \"type\": \"dropdown\", \"title\": \"Deck\", \"optionsFrom\": \"decks\", \"dependsOn\": [\"deck\", \"url\", \"other\"]}, {\"id\": \"url\", \"type\": \"text\", \"title\": \"URL\"}]}"
        #expect(issues(manifest) == ["/preferences/0/dependsOn/0", "/preferences/0/dependsOn/2"])
    }

    @Test func needsTheMatchingContextPermission() {
        let manifest = "{\(Self.head), \"permissions\": [\"context.page\"], \"actions\": [{\"id\": \"a\", \"title\": \"A\", \"needs\": [\"page\", \"window\"]}]}"
        #expect(issues(manifest) == ["/actions/0/needs/1"])
    }
}
