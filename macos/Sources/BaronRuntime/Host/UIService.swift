import BaronCore
import Foundation

/// What the app shows for plugins. The app implements it; tests record calls.
public protocol PluginPresenter: Sendable {
    func toast(_ message: String, kind: String, from plugin: RuntimePlugin) async
}

/// `host.ui`: toasts, opening URLs (https, http and mailto) and the plugin's settings. Panels come with task-010.
public struct UIService: HostService {
    public let namespace = "ui"
    private let presenter: PluginPresenter
    private let system: SystemActions?

    public init(presenter: PluginPresenter, system: SystemActions? = nil) {
        self.presenter = presenter
        self.system = system
    }

    public func call(_ method: String, _ arguments: HostArguments, plugin: RuntimePlugin) async throws -> JSONValue {
        switch method {
        case "toast":
            let kind = try arguments.optionalString(1) ?? "info"
            guard ["info", "success", "error"].contains(kind) else { throw arguments.invalid(1, "info, success or error") }
            await presenter.toast(try arguments.string(0), kind: kind, from: plugin)
            return .null
        case "openUrl":
            let text = try arguments.string(0)
            guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["https", "http", "mailto"].contains(scheme) else {
                throw HostError("invalid_argument", "openUrl takes https, http and mailto URLs, not \(text)", data: .object(["path": .string("/0")]))
            }
            await system?.open(url)
            return .null
        case "openSettings":
            await system?.openSettings(pluginID: plugin.id)
            return .null
        default:
            throw arguments.unknownMethod()
        }
    }
}
