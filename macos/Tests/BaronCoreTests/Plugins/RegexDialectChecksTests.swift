import Testing
@testable import BaronCore

struct RegexDialectChecksTests {
    let validator = ManifestValidatorTests()

    func issues(regex: String) -> [String] {
        let escaped = regex.replacingOccurrences(of: "\\", with: "\\\\")
        return validator.issues(#"{\#(ManifestValidatorTests.head), "actions": [{"id": "a", "title": "A", "when": {"regex": "\#(escaped)"}}]}"#)
    }

    @Test(arguments: ["^\\p{L}+$", "(?<word>fox)\\k<word>", "(?i:fox)", "[a-z]{2,}"])
    func acceptsPatternsBothUnderstand(_ pattern: String) {
        #expect(issues(regex: pattern) == [])
    }

    @Test(arguments: ["(?i)fox", "a{,3}", "x*+"])
    func rejectsPatternsJavaScriptRefuses(_ pattern: String) {
        #expect(issues(regex: pattern) == ["/actions/0/when/regex"])
    }

    @Test func rejectsPatternsICURefuses() {
        #expect(issues(regex: "[]fox") == ["/actions/0/when/regex"])
    }

    @Test func checksPreferencePatternsToo() {
        let json = #"{\#(ManifestValidatorTests.head), "actions": [{"id": "a", "title": "A"}], "preferences": [{"id": "u", "type": "text", "title": "U", "pattern": "(?i)x"}, {"id": "l", "type": "list", "title": "L", "itemPattern": "[]"}]}"#
        #expect(validator.issues(json) == ["/preferences/0/pattern", "/preferences/1/itemPattern"])
    }

    @Test func reportsTheEngineMessage() {
        #expect(JavaScriptRegexCompiler().error(compiling: "(?i)fox")?.contains("Invalid regular expression") == true)
        #expect(JavaScriptRegexCompiler().error(compiling: "fox") == nil)
    }
}
