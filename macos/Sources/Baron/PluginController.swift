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
    /// Installed plugins and their records (version, source, pending update).
    private(set) var installedRecords: [String: InstalledRecord] = [:]
    /// Plugins loaded by `baron dev`, from their folders (not copied).
    private var developmentPlugins: [String: RuntimePlugin] = [:]
    /// Developer mode's socket while it is on.
    private(set) var devServer: DevServer?
    /// Updated plugins whose onUpdate hasn't run yet, with the version they came from.
    private var pendingUpdateHooks: [String: String] = [:]
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
    let installer: PluginInstaller

    init(presenter: PluginPresenter) {
        grants = GrantStore(folder: location.dataRoot)
        stores = PluginStores(location: location)
        preferences = PreferencesStore(location: location)
        data = PluginDataManager(stores: stores, preferences: preferences, secrets: secrets, grants: grants)
        installer = PluginInstaller(data: data)
        let gate = PermissionGate(grants: grants, actions: actions)
        let services: [HostService] = [
            LogService(sink: { id, level, text in DevSink.shared.emit(id, "log", ["level": .string(level), "text": .string(text)]) }),
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

    /// Plugins in the order Settings lists them: installed ones, then development ones.
    private(set) var orderedPlugins: [RuntimePlugin] = []

    /// Where a listed plugin came from.
    func source(of id: String) -> PluginSource {
        if let dev = developmentPlugins[id] { return .development(dev.package.path) }
        return installedRecords[id]?.source ?? found.first { $0.plugin?.id == id }.map { .development($0.folder.path) } ?? .development("")
    }

    /// Reads the installed plugins and the development folder again; changed plugins load fresh on their next use.
    func reload() async {
        let installed = await installer.installed()
        installedRecords = Dictionary(installed.map { ($0.record.id, $0.record) }, uniquingKeysWith: { first, _ in first })
        for item in installed where item.record.previousVersion != nil { pendingUpdateHooks[item.record.id] = item.record.previousVersion }
        found = DevelopmentPlugins.scan()
        for entry in found where entry.plugin == nil {
            logger.error("Skipped \(entry.folder.lastPathComponent, privacy: .public): \(entry.issues.map(\.description).joined(separator: "; "), privacy: .public)")
        }
        let developing = Set(developmentPlugins.keys)
        let installedIDs = Set(installed.map(\.plugin.id)).union(developing)
        let loaded = installed.map(\.plugin).filter { !developing.contains($0.id) } + developmentPlugins.values.sorted { $0.id < $1.id }
            + found.compactMap(\.plugin).filter { !installedIDs.contains($0.id) }
        orderedPlugins = loaded
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
        await runUpdateHookIfNeeded(plugin)
        let payload = await payload(for: plugin, context: SelectionContextJSON.make(from: selection))
        actions.record(plugin.id)
        let result = await runtime.dispatch(plugin.id, .action, name: action?.handlerName ?? entry.actionID, payload: payload)
        if result.isSuccess, installedRecords[plugin.id]?.previousVersion != nil {
            try? await installer.confirmLoaded(plugin.id)
            installedRecords[plugin.id]?.previousVersion = nil
        }
        switch result {
        case .success:
            logger.info("\(plugin.id, privacy: .public) \(entry.actionID, privacy: .public): done")
        case .failure(let error):
            logger.error("\(plugin.id, privacy: .public) \(entry.actionID, privacy: .public): failed with \(error.code, privacy: .public): \(error.message, privacy: .private)")
            DevSink.shared.emit(plugin.id, "error", ["code": .string(error.code), "message": .string(error.message), "stack": .string(error.stack ?? "")])
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

    // MARK: Lifecycle

    /// onInstall, once after a fresh install (10 s limit); a failure is shown but doesn't undo the install.
    func runInstallHook(_ id: String) async {
        guard let plugin = plugins[id] else { return }
        let result = await runtime.dispatch(id, .lifecycle, name: "onInstall", payload: await payload(for: plugin))
        if case .failure(let error) = result { presentError(PluginErrorMessage.text(for: error, pluginName: displayName(plugin))) }
    }

    /// onUpdate({ previousVersion }), once, before an updated plugin's first dispatch.
    func runUpdateHookIfNeeded(_ plugin: RuntimePlugin) async {
        guard let previous = pendingUpdateHooks.removeValue(forKey: plugin.id) else { return }
        var payload = await payload(for: plugin)
        payload.arguments = [.object(["previousVersion": .string(previous)])]
        if case .failure(let error) = await runtime.dispatch(plugin.id, .lifecycle, name: "onUpdate", payload: payload) {
            presentError(PluginErrorMessage.text(for: error, pluginName: displayName(plugin)))
        }
    }

    var presentError: (String) -> Void = { _ in }

    // MARK: States

    enum State: Equatable {
        case enabled, disabled, needsConsent, broken(String), suspended(String)

        var label: String {
            switch self {
            case .enabled: "Enabled"
            case .disabled: "Disabled"
            case .needsConsent: "Needs consent"
            case .broken: "Broken"
            case .suspended: "Suspended"
            }
        }
    }

    func state(of id: String) async -> State {
        switch await runtime.state(of: id) {
        case .broken(let reason): return .broken(reason)
        case .suspended(let reason): return .suspended(reason)
        default: break
        }
        if installedRecords[id]?.pending != nil { return .needsConsent }
        return disabled.contains(id) ? .disabled : .enabled
    }

    func reenable(_ id: String) async {
        await runtime.reenable(id)
    }

    func acceptUpdate(_ id: String) async {
        try? await installer.acceptPending(id)
        await reload()
    }

    func declineUpdate(_ id: String) async {
        try? await installer.declinePending(id)
        await reload()
    }

    /// Removes an installed plugin with all of its data; development plugins are only forgotten until the next scan.
    func uninstall(_ id: String) async throws {
        await runtime.reload(id)
        try await installer.uninstall(id)
        await reload()
    }

    // MARK: Developer mode

    func setDeveloperMode(_ on: Bool) {
        if on, devServer == nil {
            let server = DevServer(handler: self)
            do {
                try server.start()
                devServer = server
                DevSink.shared.server = server
            } catch {
                logger.error("Developer mode couldn't start: \(String(describing: error), privacy: .public)")
            }
        } else if !on, let server = devServer {
            server.stop()
            devServer = nil
            DevSink.shared.server = nil
            developmentPlugins.removeAll()
            Task { await reload() }
        }
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

extension PluginController: DevSessionHandler {
    nonisolated func register(folder: URL) async throws -> String {
        let package = try PackageReader.read(folder: folder, source: .development(folder.path))
        let plugin = RuntimePlugin(manifest: package.manifest, package: folder, development: true)
        await MainActor.run { developmentPlugins[plugin.id] = plugin }
        await reload()
        return plugin.id
    }

    nonisolated func reload(pluginID: String) async {
        await runtime.reload(pluginID)
    }

    nonisolated func unregister(pluginID: String) async {
        await MainActor.run { _ = developmentPlugins.removeValue(forKey: pluginID) }
        await runtime.reload(pluginID)
        await reload()
    }
}

/// Forwards plugin log lines and errors to `baron dev` sessions while developer mode is on.
final class DevSink: @unchecked Sendable {
    static let shared = DevSink()
    private let lock = NSLock()
    private var current: DevServer?
    var server: DevServer? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    func emit(_ pluginID: String, _ event: String, _ fields: [String: JSONValue]) {
        server?.emit(pluginID: pluginID, event: event, fields: fields)
    }
}
