import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

final class FakeSystem: SystemActions, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    var clipboard = "on the clipboard"
    var editable = true
    var calls: [String] { lock.withLock { log } }
    private func note(_ line: String) { lock.withLock { log.append(line) } }

    func readClipboard() async -> String { note("read"); return clipboard }
    func writeClipboard(_ text: String) async { note("write \(text)") }
    func replaceSelection(with text: String) async -> Bool { note("replace \(text)"); return editable }
    func open(_ url: URL) async { note("open \(url.absoluteString)") }
    func openSettings(pluginID: String) async { note("settings \(pluginID)") }
}

struct SystemServicesTests {
    let plugin: RuntimePlugin
    init() throws { plugin = try makePlugin("") }

    func call(_ service: HostService, _ method: String, _ args: [JSONValue] = []) async -> Result<JSONValue, HostError> {
        await HostRouter(services: [service]).handle(HostCall(id: 1, namespace: service.namespace, method: method, arguments: args), from: plugin)
    }

    @Test func clipboardReadsAndWrites() async throws {
        let system = FakeSystem()
        #expect(try await call(ClipboardService(system: system), "readText").get() == .string("on the clipboard"))
        _ = try await call(ClipboardService(system: system), "writeText", [.string("fox")]).get()
        #expect(system.calls == ["read", "write fox"])
        #expect(await call(ClipboardService(system: system), "writeText", [.number(1)]).failure?.code == "invalid_argument")
    }
}
