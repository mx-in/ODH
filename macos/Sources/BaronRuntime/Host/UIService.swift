import BaronCore
import Foundation

/// What the app shows for plugins. The app implements it; tests record calls.
public protocol PluginPresenter: Sendable {
    func toast(_ message: String, kind: String, from plugin: RuntimePlugin) async
}

/// `host.ui`. Only toasts so far; opening URLs, panels and settings come with tasks 006 and 010.
public struct UIService: HostService {
    public let namespace = "ui"
    private let presenter: PluginPresenter

    public init(presenter: PluginPresenter) {
        self.presenter = presenter
    }

    public func call(_ method: String, _ arguments: HostArguments, plugin: RuntimePlugin) async throws -> JSONValue {
        switch method {
        case "toast":
            let kind = try arguments.optionalString(1) ?? "info"
            guard ["info", "success", "error"].contains(kind) else { throw arguments.invalid(1, "info, success or error") }
            await presenter.toast(try arguments.string(0), kind: kind, from: plugin)
            return .null
        default:
            throw arguments.unknownMethod()
        }
    }
}
