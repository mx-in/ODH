import Testing
@testable import BaronCore

@MainActor
final class FakeRetriever: TextRetriever {
    let step: RetrievalStep
    let result: String?
    private(set) var calls = 0

    init(_ step: RetrievalStep, _ result: String?) {
        self.step = step
        self.result = result
    }

    func retrieve() async -> String? {
        calls += 1
        return result
    }
}

@MainActor
struct RetrievalChainTests {
    @Test func firstNonEmptyResultWins() async {
        let text = FakeRetriever(.axText, nil)
        let web = FakeRetriever(.axWeb, "from the web")
        let menu = FakeRetriever(.menuCopy, "from the menu")
        let result = await RetrievalChain(retrievers: [menu, web, text]).retrieve()
        #expect(result == RetrievalResult(text: "from the web", step: .axWeb))
        #expect(text.calls == 1)
        #expect(menu.calls == 0)
    }

    @Test func blankTextFallsThrough() async {
        let text = FakeRetriever(.axText, "  \n")
        let key = FakeRetriever(.keyCopy, "copied")
        let result = await RetrievalChain(retrievers: [text, key]).retrieve()
        #expect(result?.step == .keyCopy)
    }

    @Test func startingStepSkipsEarlierSteps() async {
        let text = FakeRetriever(.axText, "ax")
        let menu = FakeRetriever(.menuCopy, "menu")
        let result = await RetrievalChain(retrievers: [text, menu]).retrieve(startingAt: .menuCopy)
        #expect(result?.step == .menuCopy)
        #expect(text.calls == 0)
    }

    @Test func nothingFoundIsNil() async {
        let result = await RetrievalChain(retrievers: [FakeRetriever(.axText, nil)]).retrieve()
        #expect(result == nil)
    }

    @Test func appRulesPickTheStartingStep() {
        let rules = AppRetrievalRules(startSteps: ["com.example.java": .keyCopy])
        #expect(rules.startStep(for: "com.example.java") == .keyCopy)
        #expect(rules.startStep(for: "com.apple.TextEdit") == .axText)
        #expect(rules.startStep(for: nil) == .axText)
    }
}

struct RetryTests {
    @Test func stopsAtTheFirstValue() async {
        var calls = 0
        var pauses: [Duration] = []
        let value: Int? = await retry(attempts: 6, within: .milliseconds(300), sleep: { pauses.append($0) }) {
            calls += 1
            return calls == 3 ? 42 : nil
        }
        #expect(value == 42)
        #expect(calls == 3)
        #expect(pauses == [.milliseconds(60), .milliseconds(60)])
    }

    @Test func givesUpAfterAllAttempts() async {
        var calls = 0
        var total = Duration.zero
        let value: Int? = await retry(attempts: 6, within: .milliseconds(300), sleep: { total += $0 }) {
            calls += 1
            return nil
        }
        #expect(value == nil)
        #expect(calls == 6)
        #expect(total == .milliseconds(300))
    }
}
