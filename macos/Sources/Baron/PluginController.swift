import AppKit
import BaronCore
import BaronRuntime
import os

/// Loads plugins, keeps the bar's plugin actions current, and serves the settings pages: preferences, options,
/// buttons, data and grants.
@MainActor
final class PluginController {
    let runtime: PluginRuntime
    private(set) var catalog = PluginActionCatalog()
    private(set) var plugins: [String: RuntimePlugin] = [:]
    /// Plugins found in the development folder, in folder order, valid or not.
    private(set) var found: [DevelopmentPlugins.Found] = []
    private(set) var disabled: Set<String> = []
    private let logger = Logger(subsystem: "org.odh.baron", category: "plugins")
    var onCatalogChange: ((PluginActionCatalog) -> Void)?
    /// Opens a plugin's settings page with fields highlighted (required ones that are empty).
    var openSettings: (_ pluginID: String, _ highlight: Set<String>) -> Void = { _, _ in }

    let actions = UserActionTracker()
    let location = PluginDataLocation.standard
    let grants: GrantStore
    let stores: PluginStores
    let preferences: PreferencesStore
    let secrets = SecretStore()
    let data: PluginDataManager
    let system = AppSystemActions()

    init(presenter: PluginPresenter) {
        grants = GrantStore(folder: location.dataRoot)
        stores = PluginStores(location: location)
        preferences = PreferencesStore(location: location)
        data = PluginDataManager(stores: stores, preferences: preferences, secrets: secrets, grants: grants)
        let gate = PermissionGate(grants: grants, actions: actions)
        let services: [HostService] = [
            LogService(),
            UIService(presenter: presenter, system: system),
            HTTPService(policy: NetworkPolicy(grants: grants)),
            ClipboardService(system: system),
            SelectionService(system: system),
            TextService(),
            StorageService(stores: stores),
            CacheService(stores: stores),
            SecretService(store: secrets),
            PermissionService(grants: grants, prompter: AlertPrompter()) { plugin in
                PluginLocalizer(package: plugin.package, defaultLocale: plugin.manifest.defaultLocale).resolve(plugin.manifest.name)
            },
        ]
        runtime = PluginRuntime(handler: HostRouter(services: services, gate: gate))
        system.openSettingsWindow = { [weak self] id in self?.openSettings(id, []) }
    }

    func localizer(for plugin: RuntimePlugin) -> PluginLocalizer {
        PluginLocalizer(package: plugin.package, defaultLocale: plugin.manifest.defaultLocale)
    }

    func displayName(_ plugin: RuntimePlugin) -> String {
        localizer(for: plugin).resolve(plugin.manifest.name)
    }

    /// Plugins in the order Settings lists them.
    var orderedPlugins: [RuntimePlugin] {
        found.compactMap(\.plugin).filter { plugins[$0.id] != nil }
    }

    /// Scans the development folder again; changed plugins load fresh on their next use.
    func reload() async {
        found = DevelopmentPlugins.scan()
        for entry in found where entry.plugin == nil {
            logger.error("Skipped \(entry.folder.lastPathComponent, privacy: .public): \(entry.issues.map(\.description).joined(separator: "; "), privacy: .public)")
        }
        let loaded = found.compactMap(\.plugin)
        for plugin in plugins.values { await runtime.reload(plugin.id) }
        plugins = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for plugin in loaded { await runtime.register(plugin) }
        logger.info("Loaded \(loaded.count) plugin(s) from the development folder")
        rebuildCatalog()
    }

    /// Applies the user's on/off switches.
    func setDisabled(_ ids: Set<String>) {
        guard ids != disabled else { return }
        disabled = ids
        for id in ids { Task { await runtime.reload(id) } }
        rebuildCatalog()
    }

    private func rebuildCatalog() {
        let enabled = orderedPlugins.filter { !disabled.contains($0.id) }
        catalog = PluginActionCatalog(enabled.map { ($0.manifest, localizer(for: $0)) })
        onCatalogChange?(catalog)
    }

    func payload(for plugin: RuntimePlugin, context: JSONValue? = nil, preferences overrides: [String: JSONValue]? = nil) async -> DispatchPayload {
        let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
        let values = await preferences.values(for: plugin.manifest).merging(overrides ?? [:]) { _, new in new }
        return DispatchPayload(environment: PluginEnvironment(appearance: appearance), preferences: values, context: context)
    }

    /// Required preferences without a value; the action doesn't run until they're filled.
    func missingRequired(_ plugin: RuntimePlugin) async -> Set<String> {
        let values = await preferences.values(for: plugin.manifest)
        var missing = Set<String>()
        for preference in plugin.manifest.preferences where preference.required == true {
            if preference.type == .secret {
                if ((try? secrets.get(preference.id, pluginID: plugin.id)) ?? nil)?.isEmpty != false { missing.insert(preference.id) }
            } else if PreferenceValidator.problem(with: values[preference.id], for: preference) != nil {
                missing.insert(preference.id)
            }
        }
        return missing
    }

    /// Runs the action for a selection with the plugin's preferences and the user's environment.
    func run(_ entry: PluginActionCatalog.Entry, for selection: SelectionRun) async -> Result<JSONValue, HostError> {
        guard let plugin = plugins[entry.pluginID] else { return .failure(.notFound("\(entry.pluginName) is no longer loaded")) }
        let missing = await missingRequired(plugin)
        if !missing.isEmpty {
            openSettings(plugin.id, missing)
            return .failure(HostError("needs_settings", "\(entry.pluginName) needs some settings before it can run"))
        }
        let action = plugin.manifest.actions.first { $0.id == entry.actionID }
        let payload = await payload(for: plugin, context: SelectionContextJSON.make(from: selection))
        actions.record(plugin.id)
        let result = await runtime.dispatch(plugin.id, .action, name: action?.handlerName ?? entry.actionID, payload: payload)
        switch result {
        case .success:
            logger.info("\(plugin.id, privacy: .public) \(entry.actionID, privacy: .public): done")
        case .failure(let error):
            logger.error("\(plugin.id, privacy: .public) \(entry.actionID, privacy: .public): failed with \(error.code, privacy: .public): \(error.message, privacy: .private)")
        }
        return result
    }

    /// Fills a dropdown or checklist from the plugin's options provider, with the values on the page so far.
    func options(_ provider: String, for plugin: RuntimePlugin, values: [String: JSONValue]) async -> Result<[Preference.Option], PluginActionResultError> {
        let payload = await payload(for: plugin, preferences: values)
        switch await runtime.dispatch(plugin.id, .options, name: provider, payload: payload) {
        case .success(let value):
            switch PreferenceOptionsResult.parse(value) {
            case .success(let options): return .success(options.map { option in
                Preference.Option(value: option.value, title: localizer(for: plugin).resolve(option.title), subtitle: option.subtitle.map(localizer(for: plugin).resolve))
            })
            case .failure(let error): return .failure(error)
            }
        case .failure(let error):
            return .failure(PluginActionResultError(PluginErrorMessage.text(for: error, pluginName: displayName(plugin))))
        }
    }

    /// Runs a settings button; returns the line shown next to it and whether it reports an error.
    func runButton(_ handler: String, for plugin: RuntimePlugin, values: [String: JSONValue]) async -> (message: String, isError: Bool) {
        actions.record(plugin.id)
        let payload = await payload(for: plugin, preferences: values)
        switch await runtime.dispatch(plugin.id, .button, name: handler, payload: payload) {
        case .success(let value):
            let message = value["message"]?.stringValue ?? "Done."
            return (localizer(for: plugin).resolve(message), value["kind"]?.stringValue == "error")
        case .failure(let error):
            return (PluginErrorMessage.text(for: error, pluginName: displayName(plugin)), true)
        }
    }

    /// Saves one preference and reloads the plugin so its next dispatch sees the new values.
    func save(_ id: String, value: JSONValue?, for plugin: RuntimePlugin) async throws {
        try await preferences.set(id, to: value, pluginID: plugin.id)
        await runtime.reload(plugin.id)
    }

    func openFolder() {
        _ = DevelopmentPlugins.scan()
        NSWorkspace.shared.open(DevelopmentPlugins.defaultFolder)
    }
}

extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
