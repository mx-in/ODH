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

    @Test func replaceNeedsAnEditableSelection() async throws {
        let system = FakeSystem()
        _ = try await call(SelectionService(system: system), "replace", [.string("FOX")]).get()
        system.editable = false
        #expect(await call(SelectionService(system: system), "replace", [.string("FOX")]).failure?.code == "invalid_argument")
        #expect(system.calls == ["replace FOX", "replace FOX"])
    }

    func spans(_ value: JSONValue) -> [[Int]] {
        guard case .array(let items) = value else { return [] }
        return items.map { item in [item["start"], item["end"]].map { if case .number(let n)? = $0 { Int(n) } else { -1 } } }
    }

    @Test func segmentsSentencesAndWordsInUTF16() async throws {
        let text = "The fox runs. 狐狸很快。🦊 jumps!"
        let sentences = spans(try await call(TextService(), "segment", [.string(text), .string("sentence")]).get())
        let utf16 = Array(text.utf16)
        let pieces = sentences.map { String(decoding: utf16[$0[0]..<$0[1]], as: UTF16.self).trimmingCharacters(in: .whitespaces) }
        #expect(pieces == ["The fox runs.", "狐狸很快。", "🦊 jumps!"])
        let words = spans(try await call(TextService(), "segment", [.string("The fox, 🦊 runs"), .string("word")]).get())
        let wordUTF16 = Array("The fox, 🦊 runs".utf16)
        #expect(words.map { String(decoding: wordUTF16[$0[0]..<$0[1]], as: UTF16.self) }.contains("runs"))
        #expect(words.last == [12, 16])
        #expect(await call(TextService(), "segment", [.string("x"), .string("line")]).failure?.data == .object(["path": .string("/1")]))
    }
}
