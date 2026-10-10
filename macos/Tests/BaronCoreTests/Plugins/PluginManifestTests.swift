import Foundation
import Testing
@testable import BaronCore

struct PluginManifestTests {
    @Test func decodesEveryField() throws {
        let corpus = ManifestCorpusCase.all.first { $0.name == "valid-every-field" }!
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: corpus.manifestData())
        #expect(manifest.id == "org.example.upper")
        #expect(manifest.platforms == [.macos, .windows, .linux])
        #expect(manifest.permissions.contains("context.sentence"))
        #expect(manifest.optionalPermissions == ["network:*"])
        let action = try #require(manifest.actions.first)
        #expect(action.handlerName == "toUpper")
        #expect(action.needs == [.sentence, .page])
        #expect(action.autoRun == .never)
        #expect(action.when?.apps == [AppMatch(ids: [.macos: "com.apple.TextEdit"]), AppMatch(ids: [.macos: "com.apple.Notes", .windows: "notepad.exe"])])
        #expect(action.when?.regex == "\\p{L}")
    }

    @Test func fillsDefaultsForMissingLists() throws {
        let corpus = ManifestCorpusCase.all.first { $0.name == "valid-minimal" }!
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: corpus.manifestData())
        #expect(manifest.platforms == PluginPlatform.allCases)
        #expect(manifest.permissions.isEmpty && manifest.preferences.isEmpty)
        #expect(manifest.actions.first?.handlerName == "upper")
    }

    @Test func decodesEveryPreferenceType() throws {
        let corpus = ManifestCorpusCase.all.first { $0.name == "valid-every-preference" }!
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: corpus.manifestData())
        #expect(Set(manifest.preferences.map(\.type)) == Set(PreferenceType.allCases))
        let byID = Dictionary(uniqueKeysWithValues: manifest.preferences.map { ($0.id, $0) })
        #expect(byID["maxExamples"]?.default == .number(2))
        #expect(byID["ankiEnabled"]?.default == .bool(false))
        #expect(byID["dictionaries"]?.default == .strings(["collins"]))
        #expect(byID["deck"]?.dependsOn == ["ankiUrl"])
        #expect(byID["testAnki"]?.run == "testAnki")
    }
}
