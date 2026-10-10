import BaronRuntime
import os

/// Shows plugin toasts. For now it only logs them; the toast panel comes with action results.
final class ToastPresenter: PluginPresenter {
    private let logger = Logger(subsystem: "org.odh.baron", category: "plugins")

    func toast(_ message: String, kind: String, from plugin: RuntimePlugin) async {
        logger.info("\(plugin.id, privacy: .public) toast (\(kind, privacy: .public)): \(message, privacy: .private)")
    }
}
