import AppKit
import BaronCore
import BaronPlatform
import BaronRuntime
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let permissionItem = NSMenuItem()
    private let pauseItem = NSMenuItem()
    private let store = SettingsStore()
    private let coordinator = SelectionCoordinator(pipeline: SelectionPipeline(gate: Gate(excludedApps: ExcludedAppRule.defaults)))
    private lazy var settingsWindow = SettingsWindowController(store: store)
    private let debugPanel = DebugPanelController()
    private let debugItem = NSMenuItem()
    private var subscriptions: Set<AnyCancellable> = []
    private let toasts = ToastPresenter()
    private lazy var plugins = PluginController(presenter: toasts)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = buildMenu()
        statusItem = item

        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.request()
        }
        AXElement.applyGlobalTimeout()

        store.$settings
            .sink { [weak self] in self?.apply($0) }
            .store(in: &subscriptions)
        coordinator.onRun = { [weak self] trigger, outcome, source in
            guard let self, self.debugPanel.isVisible else { return }
            Task { await self.debugPanel.store.record(trigger: trigger, outcome: outcome, source: source) }
        }
        plugins.onCatalogChange = { [weak self] in self?.coordinator.pipeline.plugins = $0 }
        coordinator.onPluginAction = { [weak self] entry, run in
            guard let self else { return }
            Task { await self.runPluginAction(entry, run) }
        }
        Task { await plugins.reload() }
        coordinator.start()
        // `open build/Baron.app --args --debug-panel` starts with the panel showing.
        if CommandLine.arguments.contains("--debug-panel") { debugPanel.toggle() }
    }

    private func apply(_ settings: BaronSettings) {
        coordinator.apply(settings)
        pauseItem.title = settings.isPaused ? "Resume \(Baron.name)" : "Pause \(Baron.name)"
        statusItem?.button?.image = NSImage(
            systemSymbolName: settings.isPaused ? "pause.circle" : "text.cursor",
            accessibilityDescription: Baron.name
        )
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        permissionItem.target = self
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        pauseItem.target = self
        pauseItem.action = #selector(togglePause)
        menu.addItem(pauseItem)
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        let reloadPlugins = menu.addItem(withTitle: "Reload Plugins", action: #selector(reloadPlugins), keyEquivalent: "")
        reloadPlugins.target = self
        let pluginFolder = menu.addItem(withTitle: "Open Plugin Folder", action: #selector(openPluginFolder), keyEquivalent: "")
        pluginFolder.target = self
        debugItem.title = "Show Debug Panel"
        debugItem.target = self
        debugItem.action = #selector(toggleDebugPanel)
        menu.addItem(debugItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(Baron.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        updatePermissionItem()
        return menu
    }

    // The grant can change in System Settings at any time, so re-check each time the menu opens.
    func menuWillOpen(_ menu: NSMenu) {
        updatePermissionItem()
        debugItem.state = debugPanel.isVisible ? .on : .off
    }

    private func updatePermissionItem() {
        if AccessibilityPermission.isGranted {
            permissionItem.title = "Accessibility access granted"
            permissionItem.action = nil
        } else {
            permissionItem.title = "Grant Accessibility Access…"
            permissionItem.action = #selector(openAccessibilitySettings)
        }
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSystemSettings()
    }

    @objc private func togglePause() {
        store.settings.isPaused.toggle()
    }

    @objc private func toggleDebugPanel() {
        debugPanel.toggle()
    }

    /// Runs a plugin action and carries out what it returns; failures show as a toast naming the plugin.
    private func runPluginAction(_ entry: PluginActionCatalog.Entry, _ run: SelectionRun) async {
        toasts.anchor = run.bounds.map { CGPoint(x: $0.midX, y: $0.minY) } ?? run.trigger.location
        let mayReplace = plugins.plugins[entry.pluginID]?.manifest.permissions.contains("selection.replace") ?? false
        switch await plugins.run(entry, for: run) {
        case .success(let value):
            let parsed = PluginActionResult.parse(value, editable: run.editable, mayReplace: mayReplace)
            BaronLog.plugins.info("\(entry.pluginID, privacy: .public) result: \(String(describing: parsed).prefix(40), privacy: .private) editable=\(run.editable, privacy: .public)")
            switch parsed {
            case .success(.nothing): break
            case .success(.copy(let text)): ActionEffectPerformer.perform(.copy(text))
            case .success(.replace(let text)): ActionEffectPerformer.perform(.replace(text))
            case .success(.openURL(let url)): ActionEffectPerformer.perform(.openURL(url))
            case .success(.toast(let message, let kind)): toasts.show(message, kind: ToastPanel.Kind(rawValue: kind) ?? .info)
            case .failure(let error): toasts.show("\(entry.pluginName): \(error.message)", kind: .error)
            }
        case .failure(let error):
            toasts.show(PluginErrorMessage.text(for: error, pluginName: entry.pluginName), kind: .error)
        }
    }

    @objc private func reloadPlugins() {
        Task { await plugins.reload() }
    }

    @objc private func openPluginFolder() {
        plugins.openFolder()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }
}
