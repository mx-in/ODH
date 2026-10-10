import Foundation
import Testing
@testable import BaronCore

struct PluginLocalizerTests {
    let tables = [
        "en": ["action.lookup": "Look up", "pref.deck": "Deck", "only.en": "English only"],
        "zh-Hans": ["action.lookup": "查词", "pref.deck": "牌组"],
        "zh-Hant": ["action.lookup": "查詞"],
    ]

    func localizer(_ languages: [String]) -> PluginLocalizer {
        PluginLocalizer(tables: tables, defaultLocale: "en", preferredLanguages: languages)
    }

    @Test func resolvesEnglish() {
        #expect(localizer(["en-US"]).resolve("%action.lookup%") == "Look up")
    }

    @Test func resolvesSimplifiedChineseFromTheSystemTag() {
        #expect(localizer(["zh-Hans-CN", "en-US"]).resolve("%action.lookup%") == "查词")
        #expect(localizer(["zh-Hant-TW"]).resolve("%action.lookup%") == "查詞")
    }

    @Test func fallsBackThroughLanguagesThenTheDefault() {
        #expect(localizer(["zh-Hant-TW", "zh-Hans-CN"]).resolve("%pref.deck%") == "牌组")
        #expect(localizer(["zh-Hans-CN"]).resolve("%only.en%") == "English only")
        #expect(localizer(["fr-FR"]).resolve("%pref.deck%") == "Deck")
    }

    @Test func showsTheKeyWhenNothingHasIt() {
        #expect(localizer(["en"]).resolve("%nowhere%") == "nowhere")
    }

    @Test func leavesPlainTextAlone() {
        #expect(localizer(["zh-Hans"]).resolve("100%") == "100%")
        #expect(localizer(["zh-Hans"]).resolve("Look up") == "Look up")
    }

    @Test func loadsLocalesFromAPackage() {
        let corpus = ManifestCorpusCase.all.first { $0.name == "valid-localized" }!
        let localizer = PluginLocalizer(package: corpus.folder, defaultLocale: "en", preferredLanguages: ["zh-Hans-CN"])
        #expect(localizer.resolve("%action.upper%") == "转为大写")
        #expect(localizer.resolve("%pref.audio%") == "Audio")
    }
}
