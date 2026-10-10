import AppKit
import BaronCore
import BaronRuntime
import SwiftUI

/// Where the Settings window is: its tab, the selected plugin and the fields to highlight.
@MainActor
final class SettingsNavigation: ObservableObject {
    enum Tab: Hashable { case general, plugins }
    @Published var tab: Tab = .general
    @Published var selectedPlugin: String?
    @Published var highlighted: Set<String> = []
}

/// One plugin's settings page. Values are validated as they change and saved 0.5 s after the last edit;
/// saving reloads the plugin and the options of fields that depend on the changed one. Design: 06-settings.md
@MainActor
final class PluginPage: ObservableObject {
    enum OptionsState: Equatable {
        case loading
        case loaded([Preference.Option])
        case failed(String)
    }

    let plugin: RuntimePlugin
    let controller: PluginController
    let localizer: PluginLocalizer
    @Published var values: [String: JSONValue] = [:]
    @Published var errors: [String: String] = [:]
    @Published var options: [String: OptionsState] = [:]
    @Published var buttonResults: [String: (message: String, isError: Bool)] = [:]
    @Published var secretSaved: [String: Bool] = [:]
    @Published var usage: PluginDataUsage?
    @Published var grants: [RuntimeGrant] = []
    @Published var savedFlash: String?
    private var pendingSaves: [String: Task<Void, Never>] = [:]

    static let saveDelay: Duration = .milliseconds(500)

    init(plugin: RuntimePlugin, controller: PluginController) {
        self.plugin = plugin
        self.controller = controller
        localizer = controller.localizer(for: plugin)
    }

    var manifest: PluginManifest { plugin.manifest }
    func text(_ string: String?) -> String { string.map(localizer.resolve) ?? "" }

    func load() async {
        values = await controller.preferences.values(for: manifest)
        for preference in manifest.preferences where preference.type == .secret {
            secretSaved[preference.id] = ((try? controller.secrets.get(preference.id, pluginID: plugin.id)) ?? nil) != nil
        }
        for preference in manifest.preferences where preference.optionsFrom != nil {
            await loadOptions(preference)
        }
        await refreshData()
    }

    func refreshData() async {
        usage = try? await controller.data.usage(plugin.id)
        grants = await controller.grants.runtimeGrants(for: plugin.id)
    }

    // MARK: Values

    func set(_ preference: Preference, to value: JSONValue?) {
        values[preference.id] = value
        errors[preference.id] = PreferenceValidator.problem(with: value, for: preference)
        pendingSaves[preference.id]?.cancel()
        guard errors[preference.id] == nil else { return }
        pendingSaves[preference.id] = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled, let self else { return }
            await self.save(preference, value)
        }
    }

    private func save(_ preference: Preference, _ value: JSONValue?) async {
        do {
            try await controller.save(preference.id, value: value, for: plugin)
            savedFlash = preference.id
            for dependent in manifest.preferences where dependent.dependsOn?.contains(preference.id) == true {
                await loadOptions(dependent)
            }
        } catch {
            errors[preference.id] = "Couldn't save: \(error)"
        }
    }

    /// Saves everything waiting, for tests and before closing.
    func flush() async {
        for task in pendingSaves.values { await task.value }
    }

    // MARK: Options, buttons, secrets

    func loadOptions(_ preference: Preference) async {
        guard let provider = preference.optionsFrom else { return }
        options[preference.id] = .loading
        switch await controller.options(provider, for: plugin, values: values) {
        case .success(let loaded): options[preference.id] = .loaded(loaded)
        case .failure(let error): options[preference.id] = .failed(error.message)
        }
    }

    /// The choices a dropdown or checklist offers now: fixed, or loaded; nil while loading or after a failure.
    func choices(_ preference: Preference) -> [Preference.Option]? {
        if let fixed = preference.options { return fixed.map { Preference.Option(value: $0.value, title: text($0.title), subtitle: $0.subtitle.map(text)) } }
        if case .loaded(let loaded)? = options[preference.id] { return loaded }
        return nil
    }

    func press(_ preference: Preference) async {
        guard let handler = preference.run else { return }
        buttonResults[preference.id] = ("…", false)
        buttonResults[preference.id] = await controller.runButton(handler, for: plugin, values: values)
    }

    func saveSecret(_ preference: Preference, _ secret: String) {
        do {
            if secret.isEmpty { try controller.secrets.remove(preference.id, pluginID: plugin.id) }
            else { try controller.secrets.set(preference.id, secret, pluginID: plugin.id) }
            secretSaved[preference.id] = !secret.isEmpty
            errors[preference.id] = nil
            Task { await controller.runtime.reload(plugin.id) }
        } catch {
            errors[preference.id] = "\(error)"
        }
    }

    // MARK: Data and grants

    func revoke(_ grant: RuntimeGrant) async {
        await controller.grants.revoke(grant.permission, pluginID: plugin.id)
        await refreshData()
    }

    func clearCache() async {
        try? await controller.data.clearCache(plugin.id)
        await refreshData()
    }

    func reset() async {
        try? await controller.data.reset(plugin.id)
        await controller.runtime.reload(plugin.id)
        await load()
    }
}
