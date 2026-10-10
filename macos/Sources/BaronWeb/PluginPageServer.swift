import BaronCore
import Foundation
import WebKit

/// What serving a plugin's pages needs to know about it.
public struct PluginPageSource: Sendable {
    public var package: URL
    /// Its permissions: the manifest's, plus run-time network grants, for the page's security policy.
    public var granted: [String]

    public init(package: URL, granted: [String]) {
        self.package = package
        self.granted = granted
    }
}

/// Serves `baron-plugin://<plugin id>/<path>` from the plugin's package, with the page security policy on every
/// response. Paths can't leave the package. Design: docs/design/plugin-platform/07-web-views.md#serving-pages
public final class PluginPageServer: NSObject, WKURLSchemeHandler {
    public static let scheme = "baron-plugin"

    private let lookup: (String) -> PluginPageSource?

    public init(lookup: @escaping (String) -> PluginPageSource?) {
        self.lookup = lookup
    }

    public static func url(pluginID: String, path: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = pluginID
        components.path = "/" + (path.hasPrefix("./") ? String(path.dropFirst(2)) : path)
        return components.url
    }

    public func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let source = url.host.flatMap(lookup)
        let policy = PageSecurityPolicy.header(granted: source?.granted ?? [])
        guard let source, let file = PluginPagePath.resolve(String(url.path.dropFirst()), in: source.package),
              let data = try? Data(contentsOf: file) else {
            respond(task, url: url, status: 404, headers: ["Content-Security-Policy": policy, "Content-Type": "text/plain"], body: Data())
            return
        }
        respond(task, url: url, status: 200, headers: [
            "Content-Type": PluginPagePath.mimeType(for: file),
            "Content-Security-Policy": policy,
            "Cache-Control": "no-store",
        ], body: data)
    }

    public func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func respond(_ task: WKURLSchemeTask, url: URL, status: Int, headers: [String: String], body: Data) {
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }
}
