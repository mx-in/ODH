import AppKit
import BaronCore
import BaronPlatform

/// Connects the event monitors, the pipeline, the bar and the actions.
@MainActor
final class SelectionCoordinator {
    let pipeline: SelectionPipeline
    /// Called after every run, with the source it read from (used by the debug panel).
    var onRun: ((Trigger, PipelineOutcome, FocusedSelectionSource) -> Void)?
    /// Runs a plugin's action for the selection; set by the app delegate.
    var onPluginAction: ((PluginActionCatalog.Entry, SelectionRun) -> Void)?
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
        pipeline.arrangement = settings.bar
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
            onRun?(trigger, outcome, source)
            if case .show(let run) = outcome {
                current = run
                let allowed = Set(pipeline.plugins.entries.filter(\.mayAutoRun).map(\.itemID))
                if trigger.kind != .hotkey,
                   let automatic = pipeline.arrangement.automaticAction(among: run.items, allowed: allowed, app: run.app.bundleIdentifier),
                   let entry = pipeline.plugins.entry(forItemID: automatic) {
                    onPluginAction?(entry, run)
                } else {
                    bar.show(run.items, selection: run.bounds, pointer: run.trigger.location)
                }
            }
        }
    }

    /// An action's own hotkey: reads the selection and runs that action, whatever its when rules say.
    func runAction(_ itemID: String) {
        bar.hide()
        guard let source = FocusedSelectionSource.current() else { return }
        let trigger = Trigger(kind: .hotkey, location: ScreenGeometry.topLeft(fromAppKit: NSEvent.mouseLocation), windowDragged: false)
        Task {
            guard case .show(let run) = await pipeline.run(trigger, source: source) else { return }
            current = run
            if let entry = pipeline.plugins.entry(forItemID: itemID) {
                onPluginAction?(entry, run)
            } else if let effect = pipeline.actions.effect(of: itemID, for: run.text) {
                ActionEffectPerformer.perform(effect)
            }
        }
    }

    private func perform(_ item: BarItem) {
        guard let run = current else { return }
        if let entry = pipeline.plugins.entry(forItemID: item.id) {
            bar.hide()
            onPluginAction?(entry, run)
            return
        }
        guard let effect = pipeline.actions.effect(of: item.id, for: run.text) else { return }
        ActionEffectPerformer.perform(effect)
    }
}
