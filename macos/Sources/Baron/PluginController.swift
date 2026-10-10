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

    init(presenter: PluginPresenter) {
        let router = HostRouter(services: [LogService(), UIService(presenter: presenter), HTTPService()])
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

    func openFolder() {
        _ = DevelopmentPlugins.scan()
        NSWorkspace.shared.open(DevelopmentPlugins.defaultFolder)
    }
}
