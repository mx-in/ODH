import Foundation
import Testing
@testable import BaronCore

struct PreferenceValidatorTests {
    func preference(_ json: String) throws -> Preference {
        try JSONDecoder().decode(Preference.self, from: Data(json.utf8))
    }

    @Test func requiredFieldsMustBeFilled() throws {
        let deck = try preference(#"{"id": "deck", "type": "text", "title": "Deck", "required": true}"#)
        #expect(PreferenceValidator.problem(with: nil, for: deck) == "Required.")
        #expect(PreferenceValidator.problem(with: .string("  "), for: deck) == "Required.")
        #expect(PreferenceValidator.problem(with: .string("Words"), for: deck) == nil)
        let optional = try preference(#"{"id": "tags", "type": "text", "title": "Tags"}"#)
        #expect(PreferenceValidator.problem(with: .string(""), for: optional) == nil)
    }

    @Test func checksPatternsLengthsAndRanges() throws {
        let url = try preference(#"{"id": "u", "type": "text", "title": "U", "pattern": "^https?://", "maxLength": 30}"#)
        #expect(PreferenceValidator.problem(with: .string("http://127.0.0.1:8765"), for: url) == nil)
        #expect(PreferenceValidator.problem(with: .string("ftp://x"), for: url) == "Doesn't have the expected format.")
        #expect(PreferenceValidator.problem(with: .string("https://" + String(repeating: "x", count: 30)), for: url) == "At most 30 characters.")
        let max = try preference(#"{"id": "m", "type": "number", "title": "M", "min": 0, "max": 10}"#)
        #expect(PreferenceValidator.problem(with: .number(11), for: max) == "At most 10.")
        #expect(PreferenceValidator.problem(with: .number(-1), for: max) == "At least 0.")
        #expect(PreferenceValidator.problem(with: .string("3"), for: max) == "Not a valid value.")
    }

    @Test func checksListsAndChoices() throws {
        let scripts = try preference(#"{"id": "s", "type": "list", "title": "S", "itemPattern": "^https://", "maxItems": 2}"#)
        #expect(PreferenceValidator.problem(with: .array([.string("https://a.example/x.js")]), for: scripts) == nil)
        #expect(PreferenceValidator.problem(with: .array([.string("http://a.example/x.js")]), for: scripts) == "“http://a.example/x.js” doesn't have the expected format.")
        #expect(PreferenceValidator.problem(with: .array([.string("https://a"), .string("https://b"), .string("https://c")]), for: scripts) == "At most 2 items.")
        let audio = try preference(#"{"id": "a", "type": "dropdown", "title": "A", "options": [{"value": "uk", "title": "UK"}]}"#)
        #expect(PreferenceValidator.problem(with: .string("us"), for: audio) == "Choose one of the options.")
        let decks = try preference(#"{"id": "d", "type": "dropdown", "title": "D", "optionsFrom": "decks"}"#)
        #expect(PreferenceValidator.problem(with: .string("anything"), for: decks) == nil)
    }

    @Test func readsOptionsFromProviders() throws {
        #expect(try PreferenceOptionsResult.parse(.array([.object(["value": .string("d"), "title": .string("Default"), "subtitle": .string("12 cards")])])).get()
            == [Preference.Option(value: "d", title: "Default", subtitle: "12 cards")])
        guard case .failure = PreferenceOptionsResult.parse(.array([.object(["value": .string("d")])])) else { Issue.record("accepted"); return }
        guard case .failure = PreferenceOptionsResult.parse(.string("x")) else { Issue.record("accepted"); return }
    }
}
