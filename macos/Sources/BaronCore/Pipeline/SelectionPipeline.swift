import CoreGraphics

/// The app and focused element at the moment of a trigger, read once and shared by every stage.
@MainActor
public protocol SelectionSource {
    var bundleIdentifier: String? { get }
    func gateInput(for trigger: Trigger) -> GateInput
    func retrievalChain() -> RetrievalChain
    /// Where the selection sits on screen (top-left origin), when the app can say.
    func selectionBounds(after step: RetrievalStep) -> CGRect?
}

/// A selection that made it through: what to show and where.
public struct SelectionRun: Equatable, Sendable {
    public var trigger: Trigger
    public var text: String
    public var step: RetrievalStep
    public var bounds: CGRect?
    public var items: [BarItem]
}

public enum PipelineOutcome: Equatable, Sendable {
    case show(SelectionRun)
    case paused
    case rejected(GateReason)
    case noText
    /// A newer trigger arrived while this one was reading.
    case superseded
}

/// Trigger → gate → retrieval → the actions to offer.
@MainActor
public final class SelectionPipeline {
    public var gate: Gate
    public var retrievalRules: AppRetrievalRules
    public var actions: BuiltInActions
    public var isPaused = false

    private var generation = 0

    public init(gate: Gate, retrievalRules: AppRetrievalRules = AppRetrievalRules(), actions: BuiltInActions = BuiltInActions()) {
        self.gate = gate
        self.retrievalRules = retrievalRules
        self.actions = actions
    }

    public func run(_ trigger: Trigger, source: SelectionSource) async -> PipelineOutcome {
        generation += 1
        let mine = generation
        if isPaused, !trigger.skipsGate { return .paused }

        if !trigger.skipsGate, case .reject(let reason) = gate.evaluate(source.gateInput(for: trigger)) {
            return .rejected(reason)
        }

        let start = retrievalRules.startStep(for: source.bundleIdentifier)
        guard let result = await source.retrievalChain().retrieve(startingAt: start) else {
            return mine == generation ? .noText : .superseded
        }
        guard mine == generation else { return .superseded }

        let items = actions.items(for: result.text)
        return .show(SelectionRun(
            trigger: trigger,
            text: result.text,
            step: result.step,
            bounds: source.selectionBounds(after: result.step),
            items: items
        ))
    }

    /// Makes any run still reading report `.superseded`, for example when the bar is dismissed.
    public func cancel() {
        generation += 1
    }
}
