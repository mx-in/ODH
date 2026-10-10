import BaronCore
import Foundation
@testable import BaronRuntime

/// A host that answers calls from a table, for runtime tests.
struct ScriptedHost: HostCallHandler {
    var answer: @Sendable (HostCall) -> Result<JSONValue, HostError> = { _ in .success(.null) }

    func handle(_ call: HostCall, from plugin: RuntimePlugin) async -> Result<JSONValue, HostError> {
        answer(call)
    }
}

/// Writes a throwaway plugin package with the given bundle.
func makePlugin(_ bundle: String, id: String = "org.example.test") throws -> RuntimePlugin {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("baron-runtime-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("dist"), withIntermediateDirectories: true)
    try Data(bundle.utf8).write(to: folder.appendingPathComponent("dist/main.js"))
    let manifest = #"{"id": "\#(id)", "name": "Test", "description": "D", "version": "1.0.0", "apiVersion": 1, "main": "dist/main.js", "actions": [{"id": "run", "title": "Run"}]}"#
    return RuntimePlugin(manifest: try JSONDecoder().decode(PluginManifest.self, from: Data(manifest.utf8)), package: folder)
}

extension RuntimeLimits {
    static var fast: RuntimeLimits {
        var limits = RuntimeLimits()
        limits.load = .milliseconds(300)
        limits.action = .milliseconds(300)
        limits.stuck = .milliseconds(300)
        limits.idle = .milliseconds(300)
        return limits
    }
}
