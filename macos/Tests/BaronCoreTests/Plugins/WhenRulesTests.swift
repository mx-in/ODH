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

    @Test func appsListsTheAppsAnActionAppearsIn() {
        let rules = WhenRules(apps: [AppMatch(ids: [.macos: "com.apple.Safari"]), AppMatch(ids: [.windows: "chrome.exe"])])
        #expect(rules.matches(input("fox", app: "com.apple.Safari")))
        #expect(!rules.matches(input("fox", app: "com.google.Chrome")))
        #expect(!rules.matches(input("fox", app: nil)))
        #expect(!WhenRules(apps: [AppMatch(ids: [.windows: "com.apple.Safari"])]).matches(input("fox")))
    }

    @Test func excludeAppsHidesTheAction() {
        let rules = WhenRules(excludeApps: [AppMatch(ids: [.macos: "com.apple.Terminal"])])
        #expect(!rules.matches(input("fox", app: "com.apple.Terminal")))
        #expect(rules.matches(input("fox", app: "com.apple.Safari")))
        #expect(rules.matches(input("fox", app: nil)))
    }

    @Test func editableMustMatchWhenGiven() {
        #expect(WhenRules(editable: true).matches(input("fox", editable: true)))
        #expect(!WhenRules(editable: true).matches(input("fox", editable: false)))
        #expect(WhenRules(editable: false).matches(input("fox", editable: false)))
    }

    @Test func everyRuleMustHold() {
        let rules = WhenRules(maxLength: 10, contentTypes: [.word], editable: false)
        #expect(rules.matches(input("fox")))
        #expect(!rules.matches(input("fox", editable: true)))
        #expect(!rules.matches(input("two words")))
    }
}
