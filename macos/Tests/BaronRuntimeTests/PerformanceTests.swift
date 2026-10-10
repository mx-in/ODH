import BaronCore
import Darwin
import Foundation
import Testing
@testable import BaronRuntime

/// The runtime design's targets (02-runtime.md#targets-to-measure). Debug builds are slower, so the limits here
/// are loose; `swift test -c release --filter PerformanceTests` prints the numbers recorded in the design.
@Suite(.serialized)
struct PerformanceTests {
    static func bundle(kilobytes: Int) -> String {
        var code = "globalThis.__baronPlugin = { actions: { run() { return { type: 'copy', text: 'ok' }; } } };\n"
        var i = 0
        while code.utf8.count < kilobytes * 1024 {
            code += "function helper\(i)(a, b) { const list = [a, b, \(i)]; return list.map((x) => String(x).padStart(4, '0')).join('-') + 'helper number \(i) adds some text'; }\n"
            i += 1
        }
        return code
    }

    static func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    @Test func loadsA200KilobyteBundleQuickly() async throws {
        let plugin = try makePlugin(Self.bundle(kilobytes: 200))
        var times: [Duration] = []
        for _ in 0..<5 {
            let runtime = PluginRuntime(handler: ScriptedHost())
            await runtime.register(plugin)
            let clock = ContinuousClock()
            let start = clock.now
            #expect(await runtime.load(plugin.id) == .ready)
            times.append(clock.now - start)
        }
        let median = times.sorted()[2]
        print("PERF load-200KB median \(median)")
        #expect(median < .milliseconds(500))
    }

    @Test func dispatchOverheadIsSmall() async throws {
        let plugin = try makePlugin("globalThis.__baronPlugin = { actions: { run() { return null; } } };")
        let runtime = PluginRuntime(handler: ScriptedHost())
        await runtime.register(plugin)
        _ = await runtime.dispatch(plugin.id, .action, name: "run", payload: DispatchPayload())
        let clock = ContinuousClock()
        let start = clock.now
        let rounds = 200
        for _ in 0..<rounds { _ = await runtime.dispatch(plugin.id, .action, name: "run", payload: DispatchPayload()) }
        let each = (clock.now - start) / rounds
        print("PERF dispatch-roundtrip \(each)")
        #expect(each < .milliseconds(20))
    }

    @Test func idleContextsAreSmall() async throws {
        let plugins = try (0..<20).map { try makePlugin("globalThis.__baronPlugin = { actions: { run() {} } };", id: "org.example.mem\($0)") }
        let runtime = PluginRuntime(handler: ScriptedHost())
        for plugin in plugins { await runtime.register(plugin) }
        // Warm up shared JavaScriptCore state with one context first.
        let warm = try makePlugin("globalThis.__baronPlugin = { actions: { run() {} } };", id: "org.example.warm")
        await runtime.register(warm)
        await runtime.load(warm.id)
        let before = Self.footprint()
        for plugin in plugins { await runtime.load(plugin.id) }
        let each = (Self.footprint() - before) / plugins.count
        print("PERF idle-context \(each / 1024) KB")
        #expect(each < 30 * 1024 * 1024)
    }
}
