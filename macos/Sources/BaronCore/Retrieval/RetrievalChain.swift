/// The ways Baron can read a selection, in the order it tries them.
public enum RetrievalStep: String, CaseIterable, Codable, Sendable {
    case axText = "ax-text"
    case axWeb = "ax-web"
    case menuCopy = "menu-copy"
    case keyCopy = "key-copy"
}

/// One way of reading the selected text.
@MainActor
public protocol TextRetriever {
    var step: RetrievalStep { get }
    func retrieve() async -> String?
}

public struct RetrievalResult: Equatable, Sendable {
    public var text: String
    public var step: RetrievalStep

    public init(text: String, step: RetrievalStep) {
        self.text = text
        self.step = step
    }
}

/// Tries retrievers in `RetrievalStep` order, from a starting step; the first non-blank text wins.
@MainActor
public struct RetrievalChain {
    public var retrievers: [any TextRetriever]

    public init(retrievers: [any TextRetriever]) {
        let order = RetrievalStep.allCases
        self.retrievers = retrievers.sorted { order.firstIndex(of: $0.step)! < order.firstIndex(of: $1.step)! }
    }

    public func retrieve(startingAt start: RetrievalStep = .axText) async -> RetrievalResult? {
        let order = RetrievalStep.allCases
        let first = order.firstIndex(of: start)!
        for retriever in retrievers where order.firstIndex(of: retriever.step)! >= first {
            guard let text = await retriever.retrieve() else { continue }
            if !text.allSatisfy(\.isWhitespace) {
                return RetrievalResult(text: text, step: retriever.step)
            }
        }
        return nil
    }
}

/// Per-app starting points for apps whose Accessibility support is broken.
public struct AppRetrievalRules: Codable, Equatable, Sendable {
    public var startSteps: [String: RetrievalStep]

    public init(startSteps: [String: RetrievalStep] = [:]) {
        self.startSteps = startSteps
    }

    public func startStep(for bundleIdentifier: String?) -> RetrievalStep {
        bundleIdentifier.flatMap { startSteps[$0] } ?? .axText
    }
}

/// Calls `body` up to `attempts` times, spreading the attempts over `window`, until it returns a value.
public func retry<T>(
    attempts: Int,
    within window: Duration,
    sleep: (Duration) async -> Void = { try? await Task.sleep(for: $0) },
    _ body: () async -> T?
) async -> T? {
    guard attempts > 0 else { return nil }
    let pause = attempts > 1 ? window / (attempts - 1) : .zero
    for attempt in 0..<attempts {
        if let value = await body() { return value }
        if attempt < attempts - 1 { await sleep(pause) }
    }
    return nil
}
