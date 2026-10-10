import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

struct PreferencesStoreTests {
    let location = PluginDataLocation.temporary()

    func manifest() throws -> PluginManifest {
        try JSONDecoder().decode(PluginManifest.self, from: Data("""
        {"id": "org.example.prefs", "name": "P", "description": "D", "version": "1.0.0", "apiVersion": 1, "main": "dist/main.js",
         "actions": [{"id": "a", "title": "A"}],
         "preferences": [{"id": "deck", "type": "text", "title": "Deck", "default": "Default"}, {"id": "max", "type": "number", "title": "Max", "default": 2},
                         {"id": "key", "type": "secret", "title": "Key"}, {"id": "go", "type": "button", "title": "", "label": "Go", "run": "go"}]}
        """.utf8))
    }

    @Test func savedValuesOverrideDefaultsAndSurviveANewStore() async throws {
        let manifest = try manifest()
        let store = PreferencesStore(location: location)
        #expect(await store.values(for: manifest) == ["deck": .string("Default"), "max": .number(2)])
        try await store.set("deck", to: .string("Words"), pluginID: manifest.id)
        #expect(await PreferencesStore(location: location).values(for: manifest) == ["deck": .string("Words"), "max": .number(2)])
        try await store.set("deck", to: nil, pluginID: manifest.id)
        #expect(await store.values(for: manifest)["deck"] == .string("Default"))
    }

    @Test func neverExposesSecretsButtonsOrUnknownIDs() async throws {
        let manifest = try manifest()
        let store = PreferencesStore(location: location)
        try await store.set("key", to: .string("sk-123"), pluginID: manifest.id)
        try await store.set("gone", to: .string("x"), pluginID: manifest.id)
        let values = await store.values(for: manifest)
        #expect(values["key"] == nil && values["gone"] == nil && values["go"] == nil)
    }

    @Test func foldersArePerPluginAndRefuseBadIDs() throws {
        #expect(try location.dataFolder(for: "org.example.a").lastPathComponent == "org.example.a")
        #expect(FileManager.default.fileExists(atPath: try location.cacheFolder(for: "org.example.a").path))
        #expect(throws: HostError.self) { try location.dataFolder(for: "../evil") }
    }
}
