import BaronCore
import BaronRuntime
import Foundation
import Testing
import WebKit
@testable import BaronWeb

/// Plugin pages in a real WKWebView, without a window.
@MainActor
@Suite(.serialized)
struct PageTests {
    let package: URL
    var calls: [(HostCall, String)] = []

    init() throws {
        package = FileManager.default.temporaryDirectory.appendingPathComponent("baron-web-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("views"), withIntermediateDirectories: true)
    }

    func write(_ path: String, _ text: String) throws {
        try Data(text.utf8).write(to: package.appendingPathComponent(path))
    }

    final class Recorder {
        var calls: [(HostCall, String)] = []
        var opened: [URL] = []
    }

    func views(_ recorder: Recorder, granted: [String] = []) -> PluginPageViews {
        let server = PluginPageServer { id in id == "org.example.web" ? PluginPageSource(package: package, granted: granted) : nil }
        return PluginPageViews(server: server, route: { call, plugin in
            recorder.calls.append((call, plugin))
            return .success(call.namespace == "storage" ? .string("stored") : .null)
        }, openExternal: { recorder.opened.append($0) })
    }

    /// Evaluates `expression` until it gives a non-empty string, or times out.
    func waitFor(_ expression: String, in view: WKWebView, timeout: Duration = .seconds(10)) async -> String? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let value = try? await view.evaluateJavaScript(expression) as? String, !value.isEmpty { return value }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    static let environment = JSONValue.object(["locale": .string("en"), "appearance": .string("light")])

    @Test func servesThePageWithTheBridge() async throws {
        try write("views/page.html", #"<!doctype html><title>t</title><script src="page.js"></script>"#)
        try write("views/page.js", #"document.title = "ready " + typeof baron + " " + baron.view.data.word;"#)
        let recorder = Recorder()
        let view = views(recorder).make(pluginID: "org.example.web", path: "views/page.html",
                                        config: PageConfig(environment: Self.environment, preferences: .object([:]), view: "view-1", data: .object(["word": .string("fox")])))
        #expect(await waitFor("document.title.startsWith('ready') ? document.title : ''", in: view) == "ready object fox")
    }

    @Test func givesPagesBaronsColoursForTheAppearance() async throws {
        try write("views/page.html", #"<!doctype html><html><head><script src="page.js"></script></head><body></body></html>"#)
        try write("views/page.js", """
        addEventListener("DOMContentLoaded", () => {
            const style = getComputedStyle(document.documentElement);
            document.title = [style.getPropertyValue("--baron-accent").trim() !== "", style.colorScheme, baron.environment.locale].join(" ");
        });
        """)
        let recorder = Recorder()
        let view = views(recorder).make(pluginID: "org.example.web", path: "views/page.html",
                                        config: PageConfig(environment: Self.environment, preferences: .object([:])))
        view.appearance = NSAppearance(named: .darkAqua)
        #expect(await waitFor("document.title", in: view) == "true light dark en")
        #expect(await waitFor("matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'", in: view) == "dark")
    }

    @Test func aWarmViewLoadsAgainWithNewData() async throws {
        try write("views/page.html", #"<!doctype html><script src="page.js"></script>"#)
        try write("views/page.js", #"document.title = baron.view.data.word;"#)
        let recorder = Recorder()
        let pages = views(recorder)
        let view = pages.make(pluginID: "org.example.web", path: "views/page.html",
                              config: PageConfig(environment: Self.environment, preferences: .object([:]), view: "view-1", data: .object(["word": .string("fox")])))
        #expect(await waitFor("document.title", in: view) == "fox")
        pages.reload(view, path: "views/page.html", config: PageConfig(environment: Self.environment, preferences: .object([:]), view: "view-2", data: .object(["word": .string("owl")])))
        #expect(await waitFor("document.title === 'owl' ? 'owl' : ''", in: view) == "owl")
    }

    @Test func callsCarryThePluginFromTheOrigin() async throws {
        try write("views/page.html", #"<!doctype html><script src="page.js"></script>"#)
        try write("views/page.js", #"baron.storage.get("k").then((v) => { document.title = "got " + v; });"#)
        let recorder = Recorder()
        let view = views(recorder).make(pluginID: "org.example.web", path: "views/page.html",
                                        config: PageConfig(environment: Self.environment, preferences: .object([:]), view: "view-1"))
        #expect(await waitFor("document.title", in: view) == "got stored")
        #expect(recorder.calls.map { "\($0.1) \($0.0.namespace).\($0.0.method)" } == ["org.example.web storage.get"])
    }

    @Test func blocksInlineScriptsUndeclaredImagesAndFetch() async throws {
        try write("views/page.html", #"<!doctype html><script>window.inlineRan = true</script><script src="page.js"></script>"#)
        try write("views/page.js", """
        const blocked = [];
        document.addEventListener("securitypolicyviolation", (e) => { blocked.push(e.violatedDirective.split(" ")[0]); report(); });
        function report() { document.title = "inline " + (window.inlineRan === true) + " blocked " + [...new Set(blocked)].sort().join(","); }
        const image = new Image(); image.src = "https://undeclared.example/a.png"; document.body?.appendChild(image);
        fetch("https://undeclared.example/data").catch(() => {});
        report();
        """)
        let recorder = Recorder()
        let view = views(recorder, granted: ["network:dict.cn"]).make(pluginID: "org.example.web", path: "views/page.html",
                                                                         config: PageConfig(environment: Self.environment, preferences: .object([:])))
        let title = await waitFor("document.title.includes('connect-src') && document.title.includes('img-src') ? document.title : ''", in: view)
        // The inline script is blocked too (inlineRan stays false); its report comes before page.js listens.
        #expect(title == "inline false blocked connect-src,img-src")
    }

    @Test func keepsThePageOnItsOrigin() async throws {
        try write("views/page.html", #"<!doctype html><a id="out" href="https://example.com/">out</a><script src="page.js"></script>"#)
        try write("views/page.js", """
        document.title = "opened " + (window.open("https://example.com/") === null);
        """)
        let recorder = Recorder()
        let view = views(recorder).make(pluginID: "org.example.web", path: "views/page.html",
                                        config: PageConfig(environment: Self.environment, preferences: .object([:])))
        #expect(await waitFor("document.title", in: view) == "opened true")
        _ = try? await view.evaluateJavaScript("location.href = 'https://example.com/elsewhere'; 'x'")
        try await Task.sleep(for: .milliseconds(500))
        #expect(view.url?.scheme == PluginPageServer.scheme)
        #expect(recorder.opened.isEmpty)
    }

    @Test func refusesPathsOutsideThePackageAndOtherPlugins() async throws {
        try write("views/page.html", "<p>hi</p>")
        let recorder = Recorder()
        let pages = views(recorder)
        let other = pages.make(pluginID: "org.example.other", path: "views/page.html", config: PageConfig(environment: Self.environment, preferences: .object([:])))
        try await Task.sleep(for: .milliseconds(800))
        #expect((try? await other.evaluateJavaScript("document.body ? document.body.innerText : ''") as? String) ?? "" == "")
    }
}
