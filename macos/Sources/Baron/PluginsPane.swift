import AppKit
import BaronCore
import BaronPlatform
import BaronRuntime
import BaronWeb
import SwiftUI

/// Settings › Plugins: installed plugins with Enabled switches, and the selected plugin's page.
struct PluginsPane: View {
    let controller: PluginController
    let install: InstallFlow
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
            .safeAreaInset(edge: .bottom) {
                Button("Add from Folder…") { install.chooseFolder() }
                    .padding(8).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("plugins.add")
            }
            .id(navigation.revision)
            .overlay {
                if controller.orderedPlugins.isEmpty {
                    Text("No plugins yet. Put plugin folders in the development folder (menu › Open Plugin Folder).")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                }
            }
            Divider()
            if let page {
                PluginPageView(page: page, store: store, navigation: navigation, install: install).id("\(page.plugin.id)-\(navigation.revision)")
            } else {
                Text("Select a plugin").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { select(navigation.selectedPlugin ?? controller.orderedPlugins.first?.id) }
        .onChange(of: navigation.selectedPlugin) { _, id in select(id) }
        .onChange(of: navigation.revision) { _, _ in select(navigation.selectedPlugin, force: true) }
    }

    private func select(_ id: String?, force: Bool = false) {
        if navigation.selectedPlugin != id { navigation.selectedPlugin = id }
        guard let id, let plugin = controller.plugins[id] else { page = nil; return }
        guard force || page?.plugin.id != id else { return }
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
    let install: InstallFlow
    @State private var confirmReset = false
    @State private var confirmUninstall = false

    private var manifest: PluginManifest { page.manifest }

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "puzzlepiece.extension").font(.title).foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(page.text(manifest.name)).font(.headline)
                        Text("Version \(manifest.version)\(manifest.author.map { " · \($0)" } ?? "") · From \(page.controller.source(of: manifest.id).label)")
                            .font(.caption).foregroundStyle(.secondary)
                        stateLine
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
            if manifest.settingsPage != nil {
                Section {
                    PluginSettingsPage(page: page)
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
                if page.controller.installedRecords[manifest.id] != nil {
                    Button("Uninstall…", role: .destructive) { confirmUninstall = true }.accessibilityIdentifier("page.uninstall")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Uninstall \(page.text(manifest.name))?", isPresented: $confirmUninstall) {
            Button("Uninstall", role: .destructive) {
                Task {
                    try? await page.controller.uninstall(manifest.id)
                    navigation.selectedPlugin = nil
                    navigation.revision += 1
                }
            }
            .accessibilityIdentifier("page.uninstall.confirm")
        } message: {
            Text("The plugin and everything it kept are deleted: preferences, storage, cache, Keychain items and the permissions you granted.")
        }
        .confirmationDialog("Reset \(page.text(manifest.name))?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { Task { await page.reset() } }
        } message: {
            Text("Its preferences, storage, cache and Keychain items are deleted. Permissions you granted stay.")
        }
    }

    @ViewBuilder
    private var stateLine: some View {
        switch page.state {
        case .enabled, .disabled:
            EmptyView()
        case .needsConsent:
            HStack {
                Text("An update is waiting for your consent.").font(.caption).foregroundStyle(.orange)
                Button("Review Update…") { Task { await reviewUpdate() } }.controlSize(.small).accessibilityIdentifier("page.reviewUpdate")
            }
        case .broken(let reason):
            Text("Broken: \(reason)").font(.caption).foregroundStyle(.red).accessibilityIdentifier("page.state")
        case .suspended(let reason):
            HStack {
                Text("Suspended: \(reason)").font(.caption).foregroundStyle(.red).accessibilityIdentifier("page.state")
                Button("Re-enable") { Task { await page.controller.reenable(manifest.id); await page.refreshState() } }.controlSize(.small)
                    .accessibilityIdentifier("page.reenable")
            }
        }
    }

    private func reviewUpdate() async {
        guard let pending = page.controller.installedRecords[manifest.id]?.pending else { return }
        let folder = await page.controller.installer.folder(manifest.id, version: pending.version)
        guard let next = ManifestValidator().validate(package: folder).manifest else { return }
        let accepted = await install.ask(InstallSheetView(name: page.text(manifest.name), manifest: next, source: pending.source.label,
                                                          title: "Update “\(page.text(manifest.name))” to \(pending.version)?", actionTitle: "Update",
                                                          newPermissions: pending.newPermissions))
        if accepted { await page.controller.acceptUpdate(manifest.id) } else { await page.controller.declineUpdate(manifest.id) }
        navigation.revision += 1
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

/// A plugin's own settings page (`settingsPage`), under its generated preferences. Design: 07-web-views.md
struct PluginSettingsPage: View {
    @ObservedObject var page: PluginPage
    @State private var view: PluginWebView?

    var body: some View {
        Group {
            if let view {
                WebPageHost(view: view)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .frame(height: 320)
        .accessibilityIdentifier("page.settingsPage")
        .task(id: page.manifest.id) {
            if let plugin = page.controller.plugins[page.manifest.id] { view = await page.controller.settingsPage(for: plugin) }
        }
    }
}

private struct WebPageHost: NSViewRepresentable {
    let view: PluginWebView
    func makeNSView(context: Context) -> PluginWebView { view }
    func updateNSView(_ nsView: PluginWebView, context: Context) {}
}
