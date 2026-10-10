import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

final class RecordingViews: PluginViewPresenter, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    private var open: Set<String> = []
    var calls: [String] { lock.withLock { log } }

    func openWebView(_ page: URL, path: String, request: WebViewRequest, for plugin: RuntimePlugin) async throws -> String {
        lock.withLock {
            log.append("open \(path) \(request.data.jsonString) \(request.height.map { "\(Int($0))" } ?? "-")")
            open.insert("view-1")
        }
        return "view-1"
    }

    func postMessage(_ message: JSONValue, toView view: String, from plugin: RuntimePlugin) async throws {
        try lock.withLock {
            guard open.contains(view) else { throw HostError.notFound("No view \(view)") }
            log.append("post \(view) \(message.jsonString)")
        }
    }

    func closeView(_ view: String, from plugin: RuntimePlugin) async throws {
        _ = lock.withLock { open.remove(view) }
    }
}

struct ViewTests {
    func setUp(_ bundle: String, limits: RuntimeLimits = RuntimeLimits()) async throws -> (PluginRuntime, RuntimePlugin, RecordingViews, RecordingPresenter) {
        let plugin = try makePlugin(bundle)
        try FileManager.default.createDirectory(at: plugin.package.appendingPathComponent("views"), withIntermediateDirectories: true)
        try Data("<p>popup</p>".utf8).write(to: plugin.package.appendingPathComponent("views/popup.html"))
        let views = RecordingViews(), toasts = RecordingPresenter()
        let runtime = PluginRuntime(handler: HostRouter(services: [UIService(presenter: toasts, views: views)]), limits: limits)
        await runtime.register(plugin)
        return (runtime, plugin, views, toasts)
    }

    static let opener = """
    globalThis.__baronPlugin = { actions: { async run(ctx, host) {
        const view = await host.ui.openWebView("views/popup.html", { data: { word: ctx.text }, height: 200 });
        view.onMessage((message) => host.ui.toast("page said " + message.text));
        view.closed.then(() => host.ui.toast("closed"));
        await view.postMessage({ hello: true });
        return { type: "none" };
    } } };
    """

    @Test func messagesFlowBothWaysAndClosingSettlesTheHandle() async throws {
        let (runtime, plugin, views, toasts) = try await setUp(Self.opener)
        _ = try await runtime.dispatch(plugin.id, .action, name: "run", payload: DispatchPayload(context: .object(["text": .string("fox")]))).get()
        #expect(views.calls == [#"open views/popup.html {"word":"fox"} 200"#, #"post view-1 {"hello":true}"#])

        await runtime.viewOpened(plugin.id, view: "view-1")
        await runtime.viewEvent(plugin.id, view: "view-1", name: "message", payload: .object(["text": .string("hi")]))
        await runtime.viewEvent(plugin.id, view: "view-1", name: "closed")
        try await Task.sleep(for: .milliseconds(100))
        #expect(toasts.toasts == ["info: page said hi", "info: closed"])
    }

    @Test func refusesPagesOutsideThePackage() async throws {
        let (runtime, plugin, _, _) = try await setUp("""
        globalThis.__baronPlugin = { actions: { async run(ctx, host) {
            try { await host.ui.openWebView("../../etc/hosts"); return { type: "copy", text: "opened" }; }
            catch (error) { return { type: "copy", text: error.code }; }
        } } };
        """)
        let result = try await runtime.dispatch(plugin.id, .action, name: "run", payload: DispatchPayload()).get()
        #expect(result["text"] == .string("not_found"))
    }

    @Test func anOpenViewKeepsThePluginLoaded() async throws {
        let (runtime, plugin, _, _) = try await setUp(Self.opener, limits: .fast)
        _ = try await runtime.dispatch(plugin.id, .action, name: "run", payload: DispatchPayload(context: .object(["text": .string("fox")]))).get()
        await runtime.viewOpened(plugin.id, view: "view-1")
        try await Task.sleep(for: .milliseconds(700))
        #expect(await runtime.isLoaded(plugin.id))
        await runtime.viewEvent(plugin.id, view: "view-1", name: "closed")
        try await Task.sleep(for: .milliseconds(700))
        #expect(!(await runtime.isLoaded(plugin.id)))
    }
}
