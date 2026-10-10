import BaronCore
import Foundation

/// What the app shows for plugins. The app implements it; tests record calls.
public protocol PluginPresenter: Sendable {
    func toast(_ message: String, kind: String, from plugin: RuntimePlugin) async
}

/// What `openWebView` asks for: the page's `baron.view.data`, and a size in points.
public struct WebViewRequest: Equatable, Sendable {
    public var data: JSONValue
    public var width: Double?
    public var height: Double?

    public init(data: JSONValue = .null, width: Double? = nil, height: Double? = nil) {
        self.data = data
        self.width = width
        self.height = height
    }
}

/// Shows plugin pages in the result panel. The app implements it; tests record calls.
/// Design: docs/design/plugin-platform/07-web-views.md
public protocol PluginViewPresenter: Sendable {
    /// Shows `page` (a file inside the plugin's package) and returns the new view's id.
    func openWebView(_ page: URL, path: String, request: WebViewRequest, for plugin: RuntimePlugin) async throws -> String
    /// Throws `not_found` for a view the plugin doesn't have open.
    func postMessage(_ message: JSONValue, toView view: String, from plugin: RuntimePlugin) async throws
    func closeView(_ view: String, from plugin: RuntimePlugin) async throws
}

/// `host.ui`: toasts, opening URLs (https, http and mailto), the plugin's settings, and its pages in the result
/// panel with their `ViewHandle` (postMessage, closeView).
public struct UIService: HostService {
    public let namespace = "ui"
    private let presenter: PluginPresenter
    private let system: SystemActions?
    private let views: PluginViewPresenter?

    public init(presenter: PluginPresenter, system: SystemActions? = nil, views: PluginViewPresenter? = nil) {
        self.presenter = presenter
        self.system = system
        self.views = views
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
        case "openWebView":
            let path = try arguments.string(0)
            let options = try arguments.object(1)
            guard let page = PluginPagePath.resolve(path, in: plugin.package) else {
                throw HostError("not_found", "\(path) isn't a file in the plugin's package", data: .object(["path": .string("/0")]))
            }
            func size(_ key: String) throws -> Double? {
                guard let value = options[key], value != .null else { return nil }
                guard case .number(let points) = value, points > 0 else { throw arguments.invalid(1, "options whose \(key) is a positive number") }
                return points
            }
            let request = WebViewRequest(data: options["data"] ?? .null, width: try size("width"), height: try size("height"))
            return .string(try await requireViews().openWebView(page, path: path, request: request, for: plugin))
        case "postMessage":
            let view = try arguments.string(0)
            try await requireViews().postMessage(arguments.values.count > 1 ? arguments.values[1] : .null, toView: view, from: plugin)
            return .null
        case "closeView":
            try await requireViews().closeView(try arguments.string(0), from: plugin)
            return .null
        case "show":
            throw HostError.unavailable("Native views come after ODH; use openWebView")
        default:
            throw arguments.unknownMethod()
        }
    }

    private func requireViews() throws -> PluginViewPresenter {
        guard let views else { throw HostError.unavailable("Pages can't be shown here") }
        return views
    }
}
