import CoreGraphics
import Testing
@testable import BaronCore

@MainActor
final class FakeSource: SelectionSource {
    var bundleIdentifier: String? = "com.apple.TextEdit"
    var role: String? = "AXTextArea"
    var retrievers: [any TextRetriever]
    var bounds: CGRect? = CGRect(x: 10, y: 10, width: 40, height: 12)
    var beforeRetrieval: (() -> Void)?

    init(text: String?) {
        retrievers = [FakeRetriever(.axText, text)]
    }

    func gateInput(for trigger: Trigger) -> GateInput {
        GateInput(bundleIdentifier: bundleIdentifier, role: role, windowDragged: trigger.windowDragged)
    }

    func retrievalChain() -> RetrievalChain {
        beforeRetrieval?()
        return RetrievalChain(retrievers: retrievers)
    }

    func selectionBounds(after step: RetrievalStep) -> CGRect? { bounds }
}

@MainActor
struct SelectionPipelineTests {
    private func pipeline() -> SelectionPipeline {
        SelectionPipeline(gate: Gate(excludedApps: ExcludedAppRule.defaults))
    }

    private let drag = Trigger(kind: .drag, location: CGPoint(x: 20, y: 20))
    private let hotkey = Trigger(kind: .hotkey, location: .zero)

    @Test func selectionIsShownWithItsActions() async {
        let outcome = await pipeline().run(drag, source: FakeSource(text: "hello"))
        guard case .show(let run) = outcome else { Issue.record("expected show, got \(outcome)"); return }
        #expect(run.text == "hello")
        #expect(run.step == .axText)
        #expect(run.items.map(\.id) == ["builtin.copy", "builtin.search"])
        #expect(run.bounds == CGRect(x: 10, y: 10, width: 40, height: 12))
    }

    @Test func gateRejectionStopsTheRun() async {
        let source = FakeSource(text: "secret")
        source.bundleIdentifier = "com.1password.1password"
        #expect(await pipeline().run(drag, source: source) == .rejected(.excludedApp))
    }

    @Test func hotkeySkipsTheGate() async {
        let source = FakeSource(text: "text in a button")
        source.role = "AXButton"
        guard case .show = await pipeline().run(hotkey, source: source) else { Issue.record("hotkey should skip the gate"); return }
    }

    @Test func noTextIsReported() async {
        #expect(await pipeline().run(drag, source: FakeSource(text: nil)) == .noText)
    }

    @Test func pausedIgnoresGesturesButNotTheHotkey() async {
        let pipeline = pipeline()
        pipeline.isPaused = true
        #expect(await pipeline.run(drag, source: FakeSource(text: "x")) == .paused)
        guard case .show = await pipeline.run(hotkey, source: FakeSource(text: "x")) else { Issue.record("hotkey should work while paused"); return }
    }

    @Test func aNewerTriggerSupersedesARunInFlight() async {
        let pipeline = pipeline()
        let source = FakeSource(text: "first")
        source.beforeRetrieval = { pipeline.cancel() }
        #expect(await pipeline.run(drag, source: source) == .superseded)
    }

    @Test func perAppRulesPickTheStartingStep() async {
        let pipeline = pipeline()
        pipeline.retrievalRules = AppRetrievalRules(startSteps: ["com.apple.TextEdit": .keyCopy])
        let source = FakeSource(text: nil)
        source.retrievers = [FakeRetriever(.axText, "ax"), FakeRetriever(.keyCopy, "copied")]
        guard case .show(let run) = await pipeline.run(drag, source: source) else { Issue.record("expected show"); return }
        #expect(run.step == .keyCopy)
    }
}
