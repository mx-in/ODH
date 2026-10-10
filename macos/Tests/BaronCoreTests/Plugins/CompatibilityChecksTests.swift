import Foundation
import Testing
@testable import BaronCore

struct SemanticVersionTests {
    @Test func ordersBySemverPrecedence() {
        let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "1.2.0", "2.0.0"]
        let versions = ordered.compactMap(SemanticVersion.init)
        #expect(versions.count == ordered.count)
        #expect(versions == versions.sorted())
        for (a, b) in zip(versions, versions.dropFirst()) { #expect(a < b) }
    }

    @Test func ignoresBuildMetadata() {
        #expect(SemanticVersion("1.0.0+build.5") == SemanticVersion("1.0.0"))
    }

    @Test func rejectsOtherFormats() {
        #expect(SemanticVersion("1.0") == nil)
        #expect(SemanticVersion("v1.0.0") == nil)
    }
}

struct CompatibilityChecksTests {
    func issues(_ fields: String, baron: String = "0.2.0", apiVersions: ClosedRange<Int> = 2...3) -> [String] {
        let json = #"{"id": "org.example.a", "name": "A", "description": "D", "version": "1.0.0", "main": "dist/main.js", "actions": [{"id": "a", "title": "A"}], \#(fields)}"#
        let validator = ManifestValidator(environment: ManifestEnvironment(baronVersion: baron, platform: .macos, apiVersions: apiVersions))
        return validator.validate(data: Data(json.utf8), package: URL(fileURLWithPath: "/nonexistent")).issues.map(\.pointer)
    }

    @Test func runsTheCurrentAndPreviousAPI() {
        #expect(issues(#""apiVersion": 3"#) == [])
        #expect(issues(#""apiVersion": 2"#) == [])
        #expect(issues(#""apiVersion": 4"#) == ["/apiVersion"])
        #expect(issues(#""apiVersion": 1"#) == ["/apiVersion"])
    }

    @Test func comparesMinBaronVersion() {
        #expect(issues(#""apiVersion": 3, "minBaronVersion": "0.2.0""#) == [])
        #expect(issues(#""apiVersion": 3, "minBaronVersion": "0.2.0""#, baron: "0.2.0-beta.1") == ["/minBaronVersion"])
        #expect(issues(#""apiVersion": 3, "minBaronVersion": "0.10.0""#) == ["/minBaronVersion"])
    }

    @Test func needsThisPlatform() {
        #expect(issues(#""apiVersion": 3, "platforms": ["macos"]"#) == [])
        #expect(issues(#""apiVersion": 3, "platforms": ["windows"]"#) == ["/platforms"])
    }
}
