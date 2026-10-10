import Testing
@testable import BaronRuntime

struct PluginErrorMessageTests {
    @Test func namesThePluginForEveryKindOfFailure() {
        #expect(PluginErrorMessage.text(for: .timeout("x"), pluginName: "ODH") == "ODH took too long to answer.")
        #expect(PluginErrorMessage.text(for: HostError("plugin_error", "no word"), pluginName: "ODH") == "ODH failed: no word")
        #expect(PluginErrorMessage.text(for: .unavailable("It stopped responding"), pluginName: "ODH") == "ODH isn't available: It stopped responding")
        #expect(PluginErrorMessage.text(for: HostError("permission_denied", "network:x"), pluginName: "ODH") == "ODH: network:x")
    }

    @Test func aPluginThatThrowsProducesAMessageNamingIt() async throws {
        let plugin = try makePlugin("globalThis.__baronPlugin = { actions: { run() { throw new Error('dictionary offline') } } };")
        let runtime = PluginRuntime(handler: ScriptedHost(), limits: .fast)
        await runtime.register(plugin)
        let error = try #require(await runtime.dispatch(plugin.id, .action, name: "run", payload: DispatchPayload()).failure)
        #expect(PluginErrorMessage.text(for: error, pluginName: "Test") == "Test failed: dictionary offline")
    }
}
