import AppKit
import BaronCore
import BaronPlatform

/// Connects the event monitors, the pipeline, the bar and the actions.
@MainActor
final class SelectionCoordinator {
    let pipeline: SelectionPipeline
    private let events = SelectionEventMonitor()
    private let hotkey = HotkeyMonitor()
    private let bar = ActionBarController()
    private var current: SelectionRun?

    init(pipeline: SelectionPipeline) {
        self.pipeline = pipeline
        events.onTrigger = { [weak self] in self?.handle($0) }
        hotkey.onTrigger = { [weak self] in self?.handle($0) }
        bar.onSelect = { [weak self] in self?.perform($0) }
    }

    /// Pausing also hides the bar; the hotkey keeps working while paused.
    func apply(_ settings: BaronSettings) {
        pipeline.isPaused = settings.isPaused
        pipeline.gate = Gate(excludedApps: settings.effectiveExcludedApps)
        pipeline.retrievalRules = settings.retrievalRules
        pipeline.actions = BuiltInActions(searchTemplate: settings.searchTemplate)
        if settings.isPaused { bar.hide() }
    }

    func start() {
        events.start()
    }

    func stop() {
        events.stop()
        bar.hide()
        pipeline.cancel()
    }

    private func handle(_ trigger: Trigger) {
        bar.hide()
        guard let source = FocusedSelectionSource.current() else { return }
        Task {
            let outcome = await pipeline.run(trigger, source: source)
            BaronLog.record(outcome, trigger: trigger, app: source.bundleIdentifier)
            if case .show(let run) = outcome {
                current = run
                bar.show(run.items, selection: run.bounds, pointer: run.trigger.location)
            }
        }
    }

    private func perform(_ item: BarItem) {
        guard let run = current, let effect = pipeline.actions.effect(of: item.id, for: run.text) else { return }
        ActionEffectPerformer.perform(effect)
    }
}
