import AppKit
import BaronCore
import BaronPlatform
import BaronRuntime
import BaronWeb

/// Shows plugin pages in the result panel, one at a time, next to the last selection, and passes messages
/// between each page and its plugin's `ViewHandle`. The panel closes on a click outside, Escape, an app switch
/// or a new selection, unless pinned. Design: docs/design/plugin-platform/07-web-views.md
@MainActor
final class WebViewPanels {
    /// Where the last selection was (top-left origin), for placing the panel.
    var anchor: (selection: CGRect?, pointer: CGPoint) = (nil, .zero)

    private let pages: PluginPageViews
    private let runtime: PluginRuntime
    private let describe: (RuntimePlugin) -> (name: String, icon: NSImage?)
    private let pageConfig: (RuntimePlugin, String, JSONValue) async -> PageConfig
    private let userInput: (String) -> Void
    private var panel: ResultPanel?
    private var shown: (view: String, pluginID: String)?
    private var nextID = 1
    private let dismissal = PanelDismissMonitor()
    /// The last closed page, kept loaded for `keepWarm` so the next one from the same plugin opens quickly.
    private var warm: (page: PluginWebView, release: Task<Void, Never>)?
    static let keepWarm: Duration = .seconds(30)

    init(pages: PluginPageViews, runtime: PluginRuntime, describe: @escaping (RuntimePlugin) -> (name: String, icon: NSImage?),
         pageConfig: @escaping (RuntimePlugin, String, JSONValue) async -> PageConfig, userInput: @escaping (String) -> Void) {
        self.pages = pages
        self.runtime = runtime
        self.describe = describe
        self.pageConfig = pageConfig
        self.userInput = userInput
        dismissal.onDismiss = { [weak self] in
            guard let self, self.panel?.isPinned != true else { return }
            self.close()
        }
    }

    func open(path: String, request: WebViewRequest, for plugin: RuntimePlugin) async -> String {
        close()
        let id = "view-\(nextID)"
        nextID += 1
        let config = await pageConfig(plugin, id, request.data)
        let page: PluginWebView
        if let kept = warm, kept.page.pluginID == plugin.id {
            kept.release.cancel()
            page = kept.page
            pages.reload(page, path: path, config: config)
        } else {
            page = pages.make(pluginID: plugin.id, path: path, config: config)
        }
        warm = nil
        page.onUserInput = { [userInput] in userInput(plugin.id) }
        page.bridge.viewCall = { [weak self] method, arguments in
            await self?.viewCall(method, arguments, view: id, pluginID: plugin.id) ?? .failure(.notFound("The view closed"))
        }
        let (name, icon) = describe(plugin)
        let panel = ResultPanel(page: page, name: name, icon: icon)
        panel.onClose = { [weak self] in self?.close() }
        let size = ResultPanel.size(for: CGSize(width: request.width ?? ResultPanel.defaultSize.width, height: request.height ?? ResultPanel.defaultSize.height))
        let screen = ScreenGeometry.visibleFrame(containing: anchor.pointer)
        let frame = BarPlacement.frame(barSize: size, selection: anchor.selection, pointer: anchor.pointer, visibleFrame: screen)
        panel.setFrame(ScreenGeometry.appKit(fromTopLeft: frame), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        shown = (id, plugin.id)
        await runtime.viewOpened(plugin.id, view: id)
        dismissal.start()
        return id
    }

    func postMessage(_ message: JSONValue, toView view: String, from pluginID: String) throws {
        guard let panel, shown?.view == view, shown?.pluginID == pluginID else { throw HostError.notFound("No open view \(view)") }
        panel.page.deliver(PageEnvelope.event(view: view, name: "message", payload: message))
    }

    func closeView(_ view: String, from pluginID: String) throws {
        guard shown?.view == view, shown?.pluginID == pluginID else { throw HostError.notFound("No open view \(view)") }
        close()
    }

    /// A new selection closes an unpinned panel.
    func selectionChanged() {
        if panel?.isPinned != true { close() }
    }

    func close() {
        guard let panel, let shown else { return }
        dismissal.stop()
        panel.orderOut(nil)
        self.panel = nil
        self.shown = nil
        keepWarm(panel.page)
        Task { await runtime.viewEvent(shown.pluginID, view: shown.view, name: "closed") }
    }

    private func keepWarm(_ page: PluginWebView) {
        warm?.release.cancel()
        page.removeFromSuperview()
        page.onUserInput = nil
        page.bridge.viewCall = nil
        let release = Task { [weak self] in
            try? await Task.sleep(for: Self.keepWarm)
            guard !Task.isCancelled else { return }
            self?.warm = nil
        }
        warm = (page, release)
    }

    private func viewCall(_ method: String, _ arguments: [JSONValue], view: String, pluginID: String) async -> Result<JSONValue, HostError> {
        guard shown?.view == view else { return .failure(.notFound("The view closed")) }
        switch method {
        case "postMessage":
            await runtime.viewEvent(pluginID, view: view, name: "message", payload: arguments.first ?? .null)
        case "resize":
            guard case .number(let height)? = arguments.first, height > 0 else { return .failure(.invalidArgument("resize takes a height in points")) }
            panel?.resizePage(to: height)
        case "close":
            close()
        default:
            return .failure(.invalidArgument("baron.view.\(method) doesn't exist"))
        }
        return .success(.null)
    }
}

/// Reports when an unpinned result panel should close: a click outside it, Escape, or another app activating.
/// Global monitors don't see events aimed at Baron's own panels, so clicks in the panel never close it.
@MainActor
final class PanelDismissMonitor {
    var onDismiss: (() -> Void)?
    private var monitors: [Any] = []
    private var activation: NSObjectProtocol?

    func start() {
        stop()
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.onDismiss?() }
        }) { monitors.append(outside) }
        // Escape, whether the source app or the panel (after a click into a form field) has keyboard focus.
        if let escape = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.onDismiss?() }
        }) { monitors.append(escape) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.onDismiss?() }
            return nil
        }) { monitors.append(local) }
        activation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onDismiss?() }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
    }
}

/// `PluginViewPresenter` for the runtime's `UIService`, set up before the panels exist (they need the runtime).
final class WebViewPresenter: PluginViewPresenter, @unchecked Sendable {
    @MainActor weak var panels: WebViewPanels?

    func openWebView(_ page: URL, path: String, request: WebViewRequest, for plugin: RuntimePlugin) async throws -> String {
        guard let panels = await panels else { throw HostError.unavailable("Pages can't be shown yet") }
        return await panels.open(path: path, request: request, for: plugin)
    }

    func postMessage(_ message: JSONValue, toView view: String, from plugin: RuntimePlugin) async throws {
        try await MainActor.run { try panels?.postMessage(message, toView: view, from: plugin.id) }
    }

    func closeView(_ view: String, from plugin: RuntimePlugin) async throws {
        try await MainActor.run { try panels?.closeView(view, from: plugin.id) }
    }
}
