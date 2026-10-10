import AppKit
import BaronCore
import Foundation
import WebKit

/// A plugin page's web view. Clicks and typing in it count as the user acting on the plugin.
public final class PluginWebView: WKWebView {
    public let pluginID: String
    public let bridge: PageBridge
    /// Called on every click and key press in the page.
    public var onUserInput: (() -> Void)?
    /// WebKit holds its navigation and UI delegates weakly.
    var policy: PageNavigationPolicy?

    init(pluginID: String, bridge: PageBridge, configuration: WKWebViewConfiguration) {
        self.pluginID = pluginID
        self.bridge = bridge
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 320), configuration: configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override public func mouseDown(with event: NSEvent) {
        onUserInput?()
        super.mouseDown(with: event)
    }

    override public func keyDown(with event: NSEvent) {
        onUserInput?()
        super.keyDown(with: event)
    }

    /// Hands an event envelope to the page's `baron.view.onMessage` listeners.
    public func deliver(_ envelope: String) {
        evaluateJavaScript("__baronPageReceive(\(JSONValue.string(envelope).jsonString))")
    }
}

/// Keeps a page on its own origin: other navigations are refused, followed links open in the user's browser,
/// and `window.open` gets nothing. Design: docs/design/plugin-platform/07-web-views.md#serving-pages
final class PageNavigationPolicy: NSObject, WKNavigationDelegate, WKUIDelegate {
    let pluginID: String
    let openExternal: (URL) -> Void

    init(pluginID: String, openExternal: @escaping (URL) -> Void) {
        self.pluginID = pluginID
        self.openExternal = openExternal
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if url.scheme == PluginPageServer.scheme, url.host == pluginID { return decisionHandler(.allow) }
        if url.scheme == "about" { return decisionHandler(.allow) }
        if action.navigationType == .linkActivated, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            openExternal(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }
}
