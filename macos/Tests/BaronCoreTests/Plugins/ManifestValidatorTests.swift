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

struct ManifestValueCheckTests {
    let validator = ManifestValidatorTests()
    let action = #""actions": [{"id": "a", "title": "A"}]"#

    func issues(_ rest: String) -> [String] {
        validator.issues("{\(ManifestValidatorTests.head), \(rest)}")
    }

    @Test func minLengthIsAtMostMaxLength() {
        #expect(issues(#""actions": [{"id": "a", "title": "A", "when": {"minLength": 10, "maxLength": 5}}]"#) == ["/actions/0/when/minLength"])
        #expect(issues(#""actions": [{"id": "a", "title": "A", "when": {"minLength": 5, "maxLength": 5}}]"#) == [])
    }

    @Test func numberDefaultsStayInRange() {
        #expect(issues(action + #", "preferences": [{"id": "n", "type": "number", "title": "N", "min": 1, "max": 5, "default": 9}]"#) == ["/preferences/0/default"])
        #expect(issues(action + #", "preferences": [{"id": "n", "type": "number", "title": "N", "min": 1, "max": 5, "default": 0}]"#) == ["/preferences/0/default"])
        #expect(issues(action + #", "preferences": [{"id": "n", "type": "number", "title": "N", "min": 6, "max": 5}]"#) == ["/preferences/0/min"])
    }

    @Test func choiceDefaultsAreOptions() {
        let options = #""options": [{"value": "uk", "title": "UK"}]"#
        #expect(issues(action + #", "preferences": [{"id": "d", "type": "dropdown", "title": "D", "#+options+#", "default": "us"}]"#) == ["/preferences/0/default"])
        #expect(issues(action + #", "preferences": [{"id": "c", "type": "checklist", "title": "C", "#+options+#", "default": ["uk", "us"]}]"#) == ["/preferences/0/default/1"])
        // Options loaded from the plugin aren't known yet, so any default is allowed.
        #expect(issues(action + #", "preferences": [{"id": "d", "type": "dropdown", "title": "D", "optionsFrom": "decks", "default": "x"}]"#) == [])
    }
}
