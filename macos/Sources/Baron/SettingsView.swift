import AppKit
import BaronCore
import BaronPlatform
import KeyboardShortcuts
import SwiftUI

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
        .frame(minWidth: 460, idealWidth: 460, minHeight: SettingsWindowController.minimumSize.height, idealHeight: SettingsWindowController.size.height)
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
    static let size = NSSize(width: 460, height: 560)
    static let minimumSize = NSSize(width: 460, height: 360)
    private var window: NSWindow?
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
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
