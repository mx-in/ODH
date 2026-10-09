import AppKit
import BaronCore
import BaronPlatform
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

    @objc private func openSettings() {
        settingsWindow.show()
    }
}
