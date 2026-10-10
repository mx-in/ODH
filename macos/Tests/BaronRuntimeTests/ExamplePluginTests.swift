import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

/// Builds the example plugins with `baron build` and runs their real bundles in Baron's runtime, with the real
/// prelude, router and services (the dictionary is stubbed). Skipped when Bun isn't installed.
@Suite(.serialized)
struct ExamplePluginTests {
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static let bun: String? = ["/opt/homebrew/bin/bun", "/usr/local/bin/bun", "\(NSHomeDirectory())/.bun/bin/bun"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    static func built(_ name: String) throws -> RuntimePlugin {
        let folder = repository.appendingPathComponent("examples/\(name)")
        let build = Process()
        build.executableURL = URL(fileURLWithPath: bun!)
        build.arguments = [repository.appendingPathComponent("packages/cli/bin/baron.ts").path, "build", folder.path]
        build.standardOutput = FileHandle.nullDevice
        try build.run()
        build.waitUntilExit()
        let result = ManifestValidator().validate(package: folder)
        guard build.terminationStatus == 0, let manifest = result.manifest else { throw HostError.internalError("baron build failed for \(name): \(result.issues)") }
        return RuntimePlugin(manifest: manifest, package: folder)
    }

    func context(_ text: String, editable: Bool) -> JSONValue {
        .object(["text": .string(text), "source": .string("ax-text"), "editable": .bool(editable),
                 "app": .object(["id": .string("com.apple.TextEdit"), "name": .string("TextEdit"), "pid": .number(1)]), "platform": .string("macos")])
    }

    @Test(.enabled(if: bun != nil, "needs Bun"))
    func uppercaseRunsInBaronsEngine() async throws {
        let plugin = try Self.built("uppercase")
        let runtime = PluginRuntime(handler: HostRouter(services: [LogService()]))
        await runtime.register(plugin)
        let value = try await runtime.dispatch(plugin.id, .action, name: "uppercase", payload: DispatchPayload(context: context("straße fox", editable: true))).get()
        #expect(PluginActionResult.parse(value, editable: true, mayReplace: true) == .success(.replace("STRASSE FOX")))
    }

    @Test(.enabled(if: bun != nil, "needs Bun"))
    func lookupFetchesThroughBaronsHTTPService() async throws {
        let plugin = try Self.built("lookup")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        StubProtocol.lock.withLock {
            StubProtocol.replies["https://dict.youdao.com/suggest?num=1&doctype=json&q=fox"] = .init(
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"data":{"entries":[{"entry":"fox","explain":"n. 狐狸"}]}}"#.utf8))
        }
        let runtime = PluginRuntime(handler: HostRouter(services: [LogService(), HTTPService(configuration: configuration)]))
        await runtime.register(plugin)
        let value = try await runtime.dispatch(plugin.id, .action, name: "define", payload: DispatchPayload(context: context("fox", editable: false))).get()
        #expect(PluginActionResult.parse(value, editable: false, mayReplace: false) == .success(.toast("fox: n. 狐狸", kind: "info")))
    }
}
