import Testing
@testable import BaronCore

/// The gate for task-004: Baron's validator and the JSON Schema agree on the shared corpus.
struct ManifestCorpusTests {
    let validator = ManifestValidator(environment: ManifestEnvironment(baronVersion: "0.1.0", platform: .macos, apiVersions: 1...1))

    @Test func hasAtLeastThirtyCases() {
        #expect(ManifestCorpusCase.all.count >= 30)
    }

    @Test(arguments: ManifestCorpusCase.all)
    func validatorMatchesTheExpectation(_ corpusCase: ManifestCorpusCase) throws {
        let result = validator.validate(data: try corpusCase.manifestData(), package: corpusCase.folder)
        let pointers = result.issues.map(\.pointer)
        switch corpusCase.expectation {
        case .valid:
            #expect(pointers == [], "\(result.issues)")
            #expect(result.manifest != nil)
        case .rejectedBySchema(let pointer), .rejectedBySemantics(let pointer):
            #expect(pointers == [pointer], "\(result.issues)")
            #expect(result.manifest == nil)
        }
    }
}
