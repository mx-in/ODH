import Testing
@testable import BaronCore

struct ContentClassifierTests {
    @Test(arguments: ["fox", "don't", "well-known", "Füchse", "naïve", "狐狸", "лиса"])
    func words(_ text: String) {
        #expect(ContentClassifier.types(of: text) == [.word, .text])
    }

    @Test(arguments: ["two words", "fox2", "-fox", "fox-", "o'", "fox."])
    func notWords(_ text: String) {
        #expect(!ContentClassifier.types(of: text).contains(.word))
        #expect(ContentClassifier.types(of: text).contains(.text))
    }

    @Test(arguments: ["https://example.com/a?b=1", "http://localhost:8080", "example.com", "www.example.com/path"])
    func urls(_ text: String) {
        #expect(ContentClassifier.types(of: text) == [.url, .text])
    }

    @Test(arguments: ["see https://example.com", "ftp://example.com", "mailto:a@b.co", "file:///tmp/x"])
    func notURLs(_ text: String) {
        #expect(!ContentClassifier.types(of: text).contains(.url))
    }

    @Test func emails() {
        #expect(ContentClassifier.types(of: "fox@example.com") == [.email, .text])
        #expect(!ContentClassifier.types(of: "fox@example").contains(.email))
    }

    @Test(arguments: ["42", "-3.5", "+7", "1,234,567", "1 234,5", "12%", "0.25"])
    func numbers(_ text: String) {
        #expect(ContentClassifier.types(of: text) == [.number, .text])
    }

    @Test(arguments: ["1,23,4", "4 2 2", "1.2.3", "12a"])
    func notNumbers(_ text: String) {
        #expect(!ContentClassifier.types(of: text).contains(.number))
    }

    @Test func emptyTextHasNoType() {
        #expect(ContentClassifier.types(of: "").isEmpty)
    }

    @Test func rulesMatchAnyListedType() {
        let input = WhenInput(text: " fox ", bundleIdentifier: nil, editable: false)
        #expect(WhenRules(contentTypes: [.url, .word]).matches(input))
        #expect(!WhenRules(contentTypes: [.url, .number]).matches(input))
        #expect(WhenRules(contentTypes: [.text]).matches(input))
    }
}
