import BaronCore
import BaronRuntime
import Foundation
import WebKit

/// Answers one page's `window.baron` calls. Host calls go through the same router, permission gate and
/// user-action check as the plugin's engine code; `baron.view` calls go to the view that shows the page.
/// The plugin is the page's origin (`baron-plugin://<plugin id>`), never something the page says.
/// Design: docs/design/plugin-platform/07-web-views.md#the-page-bridge
public final class PageBridge: NSObject, WKScriptMessageHandlerWithReply {
    public static let handlerName = "baron"

    /// Serves a host call for a plugin.
    public typealias Route = (HostCall, String) async -> Result<JSONValue, HostError>
    /// Serves a `baron.view` method: postMessage, resize or close.
    public typealias ViewCall = (String, [JSONValue]) async -> Result<JSONValue, HostError>

    private let route: Route
    public var viewCall: ViewCall?

    public init(route: @escaping Route) {
        self.route = route
    }

    public func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                                      replyHandler: @escaping (Any?, String?) -> Void) {
        let origin = message.frameInfo.securityOrigin
        guard origin.protocol == PluginPageServer.scheme, message.frameInfo.isMainFrame, !origin.host.isEmpty,
              let json = message.body as? String, let call = PageEnvelope.call(fromJSON: json) else {
            replyHandler(nil, "Only Baron plugin pages can call Baron")
            return
        }
        let pluginID = origin.host
        Task { @MainActor in
            let result: Result<JSONValue, HostError>
            if call.namespace == "view" {
                result = await viewCall?(call.method, call.arguments) ?? .failure(.unavailable("This page isn't in the result panel"))
            } else {
                result = await route(call, pluginID)
            }
            replyHandler(PageEnvelope.result(id: call.id, result), nil)
        }
    }
}
