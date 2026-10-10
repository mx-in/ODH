import Foundation
import Testing
@testable import BaronRuntime

struct PluginLoadingTests {
    func runtime(_ bundle: String) async throws -> (PluginRuntime, String) {
        let plugin = try makePlugin(bundle)
        let runtime = PluginRuntime(handler: ScriptedHost(), limits: .fast)
        await runtime.register(plugin)
        return (runtime, plugin.id)
    }

    @Test func loadsAPluginThatDefinesActions() async throws {
        let (runtime, id) = try await runtime("globalThis.__baronPlugin = { actions: { run() {} } };")
        #expect(await runtime.state(of: id) == .unloaded)
        #expect(await runtime.load(id) == .ready)
    }

    @Test func aThrowingBundleIsBroken() async throws {
        let (runtime, id) = try await runtime("throw new Error('missing dictionary')")
        guard case .broken(let reason) = await runtime.load(id) else { Issue.record("not broken"); return }
        #expect(reason.contains("missing dictionary"))
    }

    @Test func aBundleWithoutActionsIsBroken() async throws {
        let (runtime, id) = try await runtime("globalThis.x = 1;")
        guard case .broken(let reason) = await runtime.load(id) else { Issue.record("not broken"); return }
        #expect(reason.contains("defines no actions"))
    }

    @Test func aBundleThatNeverFinishesLoadingIsBroken() async throws {
        let (runtime, id) = try await runtime("while (true) {}")
        guard case .broken(let reason) = await runtime.load(id) else { Issue.record("not broken"); return }
        #expect(reason.contains("longer than"))
    }

    @Test func aMissingBundleIsBroken() async throws {
        let plugin = try makePlugin("")
        try FileManager.default.removeItem(at: plugin.package.appendingPathComponent("dist/main.js"))
        let runtime = PluginRuntime(handler: ScriptedHost(), limits: .fast)
        await runtime.register(plugin)
        guard case .broken(let reason) = await runtime.load(plugin.id) else { Issue.record("not broken"); return }
        #expect(reason.contains("build the plugin"))
    }
}
