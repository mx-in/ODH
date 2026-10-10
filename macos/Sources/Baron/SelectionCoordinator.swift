import AppKit
import BaronCore
import BaronPlatform

/// Connects the event monitors, the pipeline, the bar and the actions.
@MainActor
final class SelectionCoordinator {
    let pipeline: SelectionPipeline
    /// Called after every run, with the source it read from (used by the debug panel).
    var onRun: ((Trigger, PipelineOutcome, FocusedSelectionSource) -> Void)?
    /// Runs a plugin's action for the selection with the context read for it; set by the app delegate.
    var onPluginAction: ((PluginActionCatalog.Entry, SelectionRun, CapturedContext?) -> Void)?
    private let events = SelectionEventMonitor()
    private let hotkey = HotkeyMonitor()
    private let bar = ActionBarController()
    private var current: SelectionRun?
    private var capture: ContextCapture?
    private var askBrowsersForPage = false

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
        askBrowsersForPage = settings.askBrowsersForPage
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
        guard let source = FocusedSelectionSource.current(wakeElectron: pipeline.plugins.usesContext) else { return }
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
                    startCapture(entry.context, source: source, run: run)
                    runPlugin(entry, run)
                } else {
                    // Read the context now, before the user clicks: scrolling or typing would change it.
                    startCapture(pipeline.plugins.contextFields(for: run.items), source: source, run: run)
                    bar.show(run.items, selection: run.bounds, pointer: run.trigger.location)
                }
            }
        }
    }

    /// An action's own hotkey: reads the selection and runs that action, whatever its when rules say.
    func runAction(_ itemID: String) {
        bar.hide()
        guard let source = FocusedSelectionSource.current(wakeElectron: pipeline.plugins.usesContext) else { return }
        let trigger = Trigger(kind: .hotkey, location: ScreenGeometry.topLeft(fromAppKit: NSEvent.mouseLocation), windowDragged: false)
        Task {
            guard case .show(let run) = await pipeline.run(trigger, source: source) else { return }
            current = run
            if let entry = pipeline.plugins.entry(forItemID: itemID) {
                startCapture(entry.context, source: source, run: run)
                runPlugin(entry, run)
            } else if let effect = pipeline.actions.effect(of: itemID, for: run.text) {
                ActionEffectPerformer.perform(effect)
            }
        }
    }

    private func startCapture(_ fields: Set<ContextField>, source: FocusedSelectionSource, run: SelectionRun) {
        let target = SelectionContextReader.Target(app: AXElement.application(pid: source.app.processIdentifier), focused: source.focused, step: run.step,
                                                   bundleIdentifier: source.bundleIdentifier, askBrowsers: askBrowsersForPage)
        capture = ContextCapture(fields) { fields in
            let started = ContinuousClock.now
            let context = SelectionContextReader.read(fields, from: target)
            let read = context.fields.map(\.rawValue).sorted(), asked = fields.map(\.rawValue).sorted()
            BaronLog.plugins.info("context: read \(read, privacy: .public) of \(asked, privacy: .public) in \((ContinuousClock.now - started).milliseconds, privacy: .public) ms")
            return context
        }
    }

    /// Runs the action once its context has arrived, or after waiting at most `ContextCapture.actionWait`.
    private func runPlugin(_ entry: PluginActionCatalog.Entry, _ run: SelectionRun) {
        let capture = entry.context.isEmpty ? nil : capture
        Task {
            let context = await capture?.value()
            onPluginAction?(entry, run, context)
        }
    }

    private func perform(_ item: BarItem) {
        guard let run = current else { return }
        if let entry = pipeline.plugins.entry(forItemID: item.id) {
            bar.hide()
            runPlugin(entry, run)
            return
        }
        guard let effect = pipeline.actions.effect(of: item.id, for: run.text) else { return }
        ActionEffectPerformer.perform(effect)
    }
}
