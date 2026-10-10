import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

final class RecordingPresenter: PluginPresenter, @unchecked Sendable {
    private let lock = NSLock()
    private var shown: [String] = []
    var toasts: [String] { lock.withLock { shown } }
    func toast(_ message: String, kind: String, from plugin: RuntimePlugin) async {
        lock.withLock { shown.append("\(kind): \(message)") }
    }
}

final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [String] = []
    var lines: [String] { lock.withLock { collected } }
    func add(_ line: String) { lock.withLock { collected.append(line) } }
}

struct BasicServicesTests {
    @Test func consoleAndToastsReachTheirServicesFromPluginCode() async throws {
        let presenter = RecordingPresenter()
        let lines = LineCollector()
        let router = HostRouter(services: [LogService(sink: { _, level, text in lines.add("\(level) \(text)") }), UIService(presenter: presenter)])
        let plugin = try makePlugin("""
        globalThis.__baronPlugin = { actions: { async run(ctx, host) {
            console.log('looking up', ctx.text);
            host.log.warn({ missing: true });
            await host.ui.toast('Added to Anki', 'success');
        } } };
        """)
        let runtime = PluginRuntime(handler: router, limits: .fast)
        await runtime.register(plugin)
        _ = try await runtime.dispatch(plugin.id, .action, name: "run", payload: DispatchPayload(context: .object(["text": .string("fox")]))).get()
        try await Task.sleep(for: .milliseconds(20))
        #expect(presenter.toasts == ["success: Added to Anki"])
        #expect(lines.lines == ["info looking up fox", #"warn {"missing":true}"#])
    }

    @Test func toastKindsAreChecked() async throws {
        let plugin = try makePlugin("")
        let result = await HostRouter(services: [UIService(presenter: RecordingPresenter())])
            .handle(HostCall(id: 1, namespace: "ui", method: "toast", arguments: [.string("x"), .string("loud")]), from: plugin)
        #expect(result.failure?.data == .object(["path": .string("/1")]))
    }

    @Test func preferencesStartAtTheirDefaults() throws {
        let corpus = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("packages/api/test/corpus/valid-every-preference/manifest.json")
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: corpus))
        let values = PreferenceDefaults.values(for: manifest)
        #expect(values["maxExamples"] == .number(2))
        #expect(values["ankiEnabled"] == .bool(false))
        #expect(values["dictionaries"] == .array([.string("collins")]))
        #expect(values["apiKey"] == nil && values["testAnki"] == nil && values["anki"] == nil)
        #expect(values["deck"] == nil)
    }
}
