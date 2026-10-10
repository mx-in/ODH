import Foundation
import Testing
@testable import BaronCore

struct LocaleReferenceChecksTests {
    let package: URL

    init() throws {
        package = FileManager.default.temporaryDirectory.appendingPathComponent("baron-locales-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("locales"), withIntermediateDirectories: true)
        try Data(#"{"name": "Upper", "action": "UPPER", "pref": "Audio", "uk": "UK"}"#.utf8).write(to: package.appendingPathComponent("locales/en.json"))
        try Data(#"{"name": ["not", "a", "string"]}"#.utf8).write(to: package.appendingPathComponent("locales/de.json"))
    }

    func issues(_ fields: String) -> [String] {
        let json = #"{"id": "org.example.a", "description": "D", "version": "1.0.0", "apiVersion": 1, "main": "dist/main.js", \#(fields)}"#
        return ManifestValidator().validate(data: Data(json.utf8), package: package).issues.map(\.pointer)
    }

    @Test func recognisesOnlyWholeStringKeys() {
        #expect(PluginLocales.key(in: "%action.lookup%") == "action.lookup")
        #expect(PluginLocales.key(in: "100%") == nil)
        #expect(PluginLocales.key(in: "%a b%") == nil)
        #expect(PluginLocales.key(in: "%%") == nil)
    }

    @Test func resolvesKeysInEveryLocalizableField() {
        #expect(issues(#""defaultLocale": "en", "name": "%name%", "actions": [{"id": "a", "title": "%action%"}], "preferences": [{"id": "p", "type": "dropdown", "title": "%pref%", "options": [{"value": "uk", "title": "%uk%"}]}]"#) == [])
    }

    @Test func pointsAtMissingKeys() {
        #expect(issues(#""defaultLocale": "en", "name": "%name%", "actions": [{"id": "a", "title": "%missing%"}], "preferences": [{"id": "p", "type": "dropdown", "title": "P", "options": [{"value": "uk", "title": "%gone%"}]}]"#)
            == ["/actions/0/title", "/preferences/0/options/0/title"])
    }

    @Test func needsADefaultLocaleWithAFile() {
        #expect(issues(#""name": "%name%", "actions": [{"id": "a", "title": "A"}]"#) == ["/defaultLocale"])
        #expect(issues(#""defaultLocale": "fr", "name": "N", "actions": [{"id": "a", "title": "A"}]"#) == ["/defaultLocale"])
        #expect(issues(#""defaultLocale": "de", "name": "N", "actions": [{"id": "a", "title": "A"}]"#) == ["/defaultLocale"])
    }
}
