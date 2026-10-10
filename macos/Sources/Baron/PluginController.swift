import AppKit
import BaronCore
import BaronRuntime
import os

/// Loads plugins from the development folder and keeps the bar's plugin actions current.
@MainActor
final class PluginController {
    let runtime: PluginRuntime
    private(set) var catalog = PluginActionCatalog()
    private(set) var plugins: [String: RuntimePlugin] = [:]
    private let logger = Logger(subsystem: "org.odh.baron", category: "plugins")
    var onCatalogChange: ((PluginActionCatalog) -> Void)?

    let actions = UserActionTracker()
    let grants = GrantStore(folder: GrantStore.defaultFolder)

    init(presenter: PluginPresenter) {
        let gate = PermissionGate(grants: grants, actions: actions)
        let router = HostRouter(services: [LogService(), UIService(presenter: presenter), HTTPService(policy: NetworkPolicy(grants: grants))], gate: gate)
        runtime = PluginRuntime(handler: router)
    }

    /// Scans the development folder again; changed plugins load fresh on their next use.
    func reload() async {
        let found = DevelopmentPlugins.scan()
        for entry in found where entry.plugin == nil {
            logger.error("Skipped \(entry.folder.lastPathComponent, privacy: .public): \(entry.issues.map(\.description).joined(separator: "; "), privacy: .public)")
        }
        let loaded = found.compactMap(\.plugin)
        for plugin in plugins.values { await runtime.reload(plugin.id) }
        plugins = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for plugin in loaded { await runtime.register(plugin) }
        catalog = PluginActionCatalog(loaded.map { ($0.manifest, PluginLocalizer(package: $0.package, defaultLocale: $0.manifest.defaultLocale)) })
        logger.info("Loaded \(loaded.count) plugin(s) from the development folder")
        onCatalogChange?(catalog)
    }

    /// Runs the action for a selection with the plugin's preferences and the user's environment.
    func run(_ entry: PluginActionCatalog.Entry, for selection: SelectionRun) async -> Result<JSONValue, HostError> {
        guard let plugin = plugins[entry.pluginID] else { return .failure(.notFound("\(entry.pluginName) is no longer loaded")) }
        let action = plugin.manifest.actions.first { $0.id == entry.actionID }
        let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
        let payload = DispatchPayload(environment: PluginEnvironment(appearance: appearance),
                                      preferences: PreferenceDefaults.values(for: plugin.manifest),
                                      context: SelectionContextJSON.make(from: selection))
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
