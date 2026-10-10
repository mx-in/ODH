import Testing
@testable import BaronCore

struct WhenRulesTests {
    func input(_ text: String, app: String? = "com.apple.Safari", editable: Bool = false) -> WhenInput {
        WhenInput(text: text, bundleIdentifier: app, editable: editable)
    }

    @Test func noRulesMatchEverything() {
        #expect(WhenRules().matches(input("anything at all")))
    }

    @Test func lengthCountsUTF16UnitsOfTheTrimmedText() {
        let rules = WhenRules(minLength: 2, maxLength: 3)
        #expect(rules.matches(input("  fox \n")))
        #expect(!rules.matches(input("a")))
        #expect(!rules.matches(input("foxes")))
        // One emoji is two UTF-16 units, as in JavaScript.
        #expect(rules.matches(input("🦊")))
        #expect(!WhenRules(maxLength: 1).matches(input("🦊")))
    }

    @Test func regexSearchesAnywhereLikeJavaScript() {
        #expect(WhenRules(regex: "o").matches(input("fox")))
        #expect(WhenRules(regex: "^\\p{L}+$").matches(input("Füchse")))
        #expect(!WhenRules(regex: "^\\p{L}+$").matches(input("fox 2")))
        #expect(!WhenRules(regex: "^fox$").matches(input("Fox")))
    }

    @Test func aBrokenPatternNeverMatches() {
        #expect(!WhenRules(regex: "[]").matches(input("fox")))
    }
}
