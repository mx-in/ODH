import Foundation
import Testing
@testable import BaronCore

struct BaronSettingsTests {
    @Test func roundTripsThroughJSON() throws {
        var settings = BaronSettings()
        settings.isPaused = true
        settings.exclude("com.example.game")
        settings.retrievalRules = AppRetrievalRules(startSteps: ["com.example.java": .keyCopy])
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(BaronSettings.self, from: data) == settings)
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let decoded = try JSONDecoder().decode(BaronSettings.self, from: Data(#"{"isPaused": true}"#.utf8))
        #expect(decoded.isPaused)
        #expect(decoded.searchTemplate == SearchAction.defaultTemplate)
        #expect(decoded.excludedApps == ExcludedAppRule.defaults.sorted())
    }

    @Test func baronStaysExcludedEvenIfRemoved() {
        var settings = BaronSettings()
        settings.include(Baron.bundleIdentifier)
        #expect(!settings.excludedApps.contains(Baron.bundleIdentifier))
        #expect(settings.effectiveExcludedApps.contains(Baron.bundleIdentifier))
    }

    @Test func excludeKeepsTheListSortedAndUnique() {
        var settings = BaronSettings(excludedApps: ["b", "d"])
        settings.exclude("c")
        settings.exclude("c")
        #expect(settings.excludedApps == ["b", "c", "d"])
    }

    @Test func searchTemplateNeedsAPlaceholderAndAURL() {
        #expect(BaronSettings.isValidSearchTemplate("https://duckduckgo.com/?q={query}"))
        #expect(!BaronSettings.isValidSearchTemplate("https://duckduckgo.com/"))
    }
}
