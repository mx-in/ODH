import AppKit
import BaronCore
import BaronPlatform
import BaronRuntime
import SwiftUI

/// Settings › Plugins: installed plugins with Enabled switches, and the selected plugin's page.
struct PluginsPane: View {
    let controller: PluginController
    @ObservedObject var store: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    @State private var page: PluginPage?

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $navigation.selectedPlugin) {
                ForEach(controller.orderedPlugins, id: \.id) { plugin in
                    HStack {
                        Text(controller.displayName(plugin))
                        Spacer()
                        Toggle("", isOn: Binding {
                            store.settings.isPluginEnabled(plugin.id)
                        } set: { store.settings.setPlugin(plugin.id, enabled: $0) })
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        .accessibilityIdentifier("plugin.\(plugin.id).enabled")
                    }
                    .tag(plugin.id)
                    .accessibilityIdentifier("plugin.\(plugin.id)")
                }
            }
            .frame(width: 200)
            .overlay {
                if controller.orderedPlugins.isEmpty {
                    Text("No plugins yet. Put plugin folders in the development folder (menu › Open Plugin Folder).")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                }
            }
            Divider()
            if let page {
                PluginPageView(page: page, store: store, navigation: navigation).id(page.plugin.id)
            } else {
                Text("Select a plugin").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { select(navigation.selectedPlugin ?? controller.orderedPlugins.first?.id) }
        .onChange(of: navigation.selectedPlugin) { _, id in select(id) }
    }

    private func select(_ id: String?) {
        if navigation.selectedPlugin != id { navigation.selectedPlugin = id }
        guard let id, let plugin = controller.plugins[id] else { page = nil; return }
        guard page?.plugin.id != id else { return }
        let next = PluginPage(plugin: plugin, controller: controller)
        page = next
        Task { await next.load() }
    }
}

/// A plugin's page: header, preferences, permissions, data and about. Design: 06-settings.md#where-settings-live
struct PluginPageView: View {
    @ObservedObject var page: PluginPage
    @ObservedObject var store: SettingsStore
    @ObservedObject var navigation: SettingsNavigation
    @State private var confirmReset = false

    private var manifest: PluginManifest { page.manifest }

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "puzzlepiece.extension").font(.title).foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(page.text(manifest.name)).font(.headline)
                        Text("Version \(manifest.version)\(manifest.author.map { " · \($0)" } ?? "") · Development folder")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Enabled", isOn: Binding {
                        store.settings.isPluginEnabled(manifest.id)
                    } set: { store.settings.setPlugin(manifest.id, enabled: $0) })
                    .accessibilityIdentifier("page.enabled")
                }
            }
            if !manifest.preferences.isEmpty {
                Section("Preferences") {
                    ForEach(manifest.preferences, id: \.id) { preference in
                        PreferenceRow(preference: preference, page: page, highlighted: navigation.highlighted.contains(preference.id))
                    }
                }
            }
            Section("Permissions") {
                let summary = PermissionWording.summary(of: manifest)
                let lines = summary.reads + summary.connectsTo + summary.can + summary.stores + summary.disclosures
                if lines.isEmpty { Text("Only the text you run it on.").foregroundStyle(.secondary) }
                ForEach(lines, id: \.self) { Text($0) }
                ForEach(page.grants, id: \.permission) { grant in
                    HStack {
                        Text(grantLine(grant))
                        Spacer()
                        // The identifier sits on the button: one on the row would replace it.
                        Button("Remove") { Task { await page.revoke(grant) } }.accessibilityIdentifier("grant.\(grant.permission).remove")
                    }
                }
            }
            Section("Data") {
                if let usage = page.usage {
                    Text("Storage \(bytes(usage.storageBytes)) · Cache \(bytes(usage.cacheBytes)) · \(usage.secrets) secret\(usage.secrets == 1 ? "" : "s") in the Keychain")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Clear Cache") { Task { await page.clearCache() } }
                    Button("Reset Plugin Data…") { confirmReset = true }
                }
            }
            Section("About") {
                Text(page.text(manifest.description))
                if let homepage = manifest.homepage, let url = URL(string: homepage) { Link(homepage, destination: url) }
                if let license = manifest.license { Text("Licence: \(license)").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset \(page.text(manifest.name))?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { Task { await page.reset() } }
        } message: {
            Text("Its preferences, storage, cache and Keychain items are deleted. Permissions you granted stay.")
        }
    }

    private func grantLine(_ grant: RuntimeGrant) -> String {
        let words = PluginPermission(grant.permission).map(PermissionWording.phrase) ?? grant.permission
        switch grant.answer {
        case .alwaysAllow: return "Allowed to \(words)"
        case .deny: return "Denied: \(words) (asks again after a day)"
        case .allowOnce: return "Allowed once to \(words)"
        }
    }

    private func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
