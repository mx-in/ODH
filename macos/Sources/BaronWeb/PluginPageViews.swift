import BaronCore
import Foundation
import WebKit

/// What a page's `window.baron` starts from: the same environment and preferences an action gets, and for the
/// result panel its view id and `data`.
public struct PageConfig: Sendable {
    public var environment: JSONValue
    public var preferences: JSONValue
    /// Nil for a settings page.
    public var view: String?
    public var data: JSONValue

    public init(environment: JSONValue, preferences: JSONValue, view: String? = nil, data: JSONValue = .null) {
        self.environment = environment
        self.preferences = preferences
        self.view = view
        self.data = data
    }

    var json: String {
        JSONValue.object(["environment": environment, "preferences": preferences, "view": view.map(JSONValue.string) ?? .null, "data": data]).jsonString
    }
}

/// Makes plugin web views: pages served from the package, a non-persistent data store per plugin, the page
/// bridge, the navigation policy, and audio that plays without an extra click.
/// Design: docs/design/plugin-platform/07-web-views.md
public final class PluginPageViews {
    public let server: PluginPageServer
    private let route: PageBridge.Route
    private let openExternal: (URL) -> Void
    private var stores: [String: WKWebsiteDataStore] = [:]

    public static let bridgeSource: String = {
        guard let url = Bundle.module.url(forResource: "page-bridge", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return source
    }()

    public init(server: PluginPageServer, route: @escaping PageBridge.Route, openExternal: @escaping (URL) -> Void) {
        self.server = server
        self.route = route
        self.openExternal = openExternal
    }

    /// A web view loading `path` from the plugin's package.
    public func make(pluginID: String, path: String, config: PageConfig) -> PluginWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(server, forURLScheme: PluginPageServer.scheme)
        configuration.websiteDataStore = store(for: pluginID)
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let bridge = PageBridge(route: route)
        configuration.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: PageBridge.handlerName)

        let view = PluginWebView(pluginID: pluginID, bridge: bridge, configuration: configuration)
        let policy = PageNavigationPolicy(pluginID: pluginID, openExternal: openExternal)
        view.policy = policy
        view.navigationDelegate = policy
        view.uiDelegate = policy
        reload(view, path: path, config: config)
        return view
    }

    /// Loads `path` into a web view the plugin used before, with a new config: a view kept warm after closing
    /// skips starting a web content process.
    public func reload(_ view: PluginWebView, path: String, config: PageConfig) {
        let scripts = view.configuration.userContentController
        scripts.removeAllUserScripts()
        scripts.addUserScript(WKUserScript(source: "window.__baronPageConfig = \(config.json);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        scripts.addUserScript(WKUserScript(source: Self.bridgeSource, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        scripts.addUserScript(WKUserScript(source: PageTheme.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if let url = PluginPageServer.url(pluginID: view.pluginID, path: path) { view.load(URLRequest(url: url)) }
    }

    /// One non-persistent store per plugin: nothing survives, and plugins can't see each other's.
    private func store(for pluginID: String) -> WKWebsiteDataStore {
        if let store = stores[pluginID] { return store }
        let store = WKWebsiteDataStore.nonPersistent()
        stores[pluginID] = store
        return store
    }
}
