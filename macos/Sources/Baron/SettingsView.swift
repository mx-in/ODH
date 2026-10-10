import AppKit
import BaronCore
import BaronPlatform
import KeyboardShortcuts
import SwiftUI

/// The Settings window: General and Plugins tabs.
struct SettingsRoot: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    let plugins: PluginController
    let install: InstallFlow

    var body: some View {
        TabView(selection: $navigation.tab) {
            SettingsView(store: store).tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsNavigation.Tab.general)
            BarSettingsView(store: store, navigation: navigation, catalog: { plugins.catalog })
                .tabItem { Label("Bar", systemImage: "rectangle.3.group") }.tag(SettingsNavigation.Tab.bar)
            PluginsPane(controller: plugins, install: install, store: store, navigation: navigation)
                .tabItem { Label("Plugins", systemImage: "puzzlepiece.extension") }.tag(SettingsNavigation.Tab.plugins)
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: SettingsWindowController.minimumSize.height, idealHeight: SettingsWindowController.size.height)
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var selectedApp: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Pause the bar", isOn: $store.settings.isPaused)
                    .accessibilityIdentifier("settings.pause")
                KeyboardShortcuts.Recorder("Read selection:", name: .readSelection)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .accessibilityIdentifier("settings.launchAtLogin")
                    .onChange(of: launchAtLogin) { _, enabled in
                        if !LaunchAtLogin.set(enabled) { launchAtLogin = LaunchAtLogin.isEnabled }
                    }
            }
            Section("Search") {
                TextField("Search URL", text: $store.settings.searchTemplate)
                    .accessibilityIdentifier("settings.searchTemplate")
                if !BaronSettings.isValidSearchTemplate(store.settings.searchTemplate) {
                    Text("The URL must contain {query}.").foregroundStyle(.red).font(.caption)
                }
            }
            Section("Advanced") {
                Toggle("Developer mode", isOn: $store.settings.developerMode)
                    .accessibilityIdentifier("settings.developerMode")
                Text("Lets `baron dev` load plugins from their folders, reload them on each build and stream their logs. Only your user account can connect.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Ask browsers for the page address", isOn: $store.settings.askBrowsersForPage)
                    .accessibilityIdentifier("settings.askBrowsersForPage")
                Text("For plugins allowed to read the page: when a browser doesn't share its address through Accessibility, ask Safari, Chrome, Arc, Edge, Brave, Vivaldi or Opera with AppleScript. macOS asks you once for each browser.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Excluded apps") {
                List(store.settings.excludedApps, id: \.self, selection: $selectedApp) { id in
                    Text(appName(for: id)).help(id)
                }
                .frame(minHeight: 140)
                .accessibilityIdentifier("settings.excludedApps")
                HStack {
                    Button("Add App…", action: addApp)
                    Button("Remove") {
                        if let id = selectedApp { store.settings.include(id) }
                        selectedApp = nil
                    }
                    .disabled(selectedApp == nil)
                }
            }
        }
        .formStyle(.grouped)
        // A grouped form scrolls, so it has no height of its own: without one the window opens as just its title bar.
        .frame(minWidth: 460, idealWidth: 460, minHeight: SettingsWindowController.minimumSize.height - 60, idealHeight: SettingsWindowController.size.height - 60)
        .padding(.vertical, 8)
    }

    private func appName(for bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return bundleIdentifier }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { store.settings.exclude(id) }
        }
    }
}

/// Hosts `SettingsView` in a normal window. Baron is an accessory app, so it
/// activates itself while the window is open to take keyboard input.
@MainActor
final class SettingsWindowController {
    static let size = NSSize(width: 720, height: 620)
    static let minimumSize = NSSize(width: 640, height: 420)
    private var window: NSWindow?
    private let store: SettingsStore
    private let plugins: PluginController
    private let install: InstallFlow
    let navigation = SettingsNavigation()

    init(store: SettingsStore, plugins: PluginController, install: InstallFlow) {
        self.store = store
        self.plugins = plugins
        self.install = install
    }

    /// Opens the Plugins tab on a plugin, highlighting fields (required ones that are empty).
    func showPlugin(_ id: String, highlight: Set<String> = []) {
        navigation.tab = .plugins
        navigation.selectedPlugin = id
        navigation.highlighted = highlight
        show()
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsRoot(store: store, navigation: navigation, plugins: plugins, install: install)))
            window.title = "\(Baron.name) Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(Self.size)
            window.contentMinSize = Self.minimumSize
            window.isReleasedWhenClosed = false
            window.setAccessibilityIdentifier("baron.settings")
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
