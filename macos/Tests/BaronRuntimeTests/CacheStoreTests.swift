import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

struct CacheStoreTests {
    let location = PluginDataLocation.temporary()

    @Test func keepsStringsAcrossReopening() async throws {
        let folder = try location.cacheFolder(for: "org.example.cache")
        try await CacheStore(folder: folder).set("fox", "<p>a small wild dog</p>")
        #expect(try await CacheStore(folder: folder).get("fox") == "<p>a small wild dog</p>")
    }

    @Test func evictsTheLeastRecentlyReadPastTheLimit() async throws {
        let cache = try CacheStore(folder: location.cacheFolder(for: "org.example.cache"))
        let mb = String(repeating: "x", count: 1_900_000)
        for i in 0..<5 { try await cache.set("k\(i)", mb) }  // about 9.5 MB
        _ = try await cache.get("k0")                       // k0 is now the most recently read
        try await cache.set("k5", mb)                        // over 10 MB: evicts k1, the least recently used
        #expect(try await cache.keys() == ["k0", "k2", "k3", "k4", "k5"])
        #expect(try await cache.usage() <= CacheStore.limit)
    }

    @Test func refusesValuesOverTwoMegabytes() async throws {
        let cache = try CacheStore(folder: location.cacheFolder(for: "org.example.cache"))
        await #expect(throws: HostError.self) { try await cache.set("big", String(repeating: "x", count: CacheStore.valueLimit + 1)) }
    }

    @Test func pluginCodeCachesThroughTheService() async throws {
        let plugin = try makePlugin("""
        globalThis.__baronPlugin = { actions: { async run(ctx, host) {
            await host.cache.set('fox', 'dog');
            const hit = await host.cache.get('fox');
            await host.cache.clear();
            return { type: 'copy', text: hit + ' ' + (await host.cache.get('fox')) };
        } } };
        """)
        let runtime = PluginRuntime(handler: HostRouter(services: [CacheService(stores: PluginStores(location: location))]), limits: .fast)
        await runtime.register(plugin)
        #expect(try await runtime.dispatch(plugin.id, .action, name: "run", payload: DispatchPayload()).get()["text"] == .string("dog undefined"))
    }
}
