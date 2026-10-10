import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

struct KeyValueStoreTests {
    let location = PluginDataLocation.temporary()

    @Test func storesJSONValuesThatSurviveReopening() async throws {
        let folder = try location.dataFolder(for: "org.example.kv")
        let store = try KeyValueStore(folder: folder)
        let value: JSONValue = .object(["words": .array([.string("fox"), .string("狐")]), "count": .number(2), "on": .bool(true)])
        try await store.set("history", value)
        #expect(try await KeyValueStore(folder: folder).get("history") == value)
        #expect(try await store.keys() == ["history"])
        try await store.remove("history")
        #expect(try await store.get("history") == nil)
    }

    @Test func enforcesThePerValueLimit() async throws {
        let store = try KeyValueStore(folder: location.dataFolder(for: "org.example.kv"))
        let big = JSONValue.string(String(repeating: "x", count: KeyValueStore.valueLimit))
        await #expect(throws: HostError.self) { try await store.set("big", big) }
        #expect(try await store.keys().isEmpty)
    }

    @Test func enforcesTheQuotaWithoutPartialWrites() async throws {
        let store = try KeyValueStore(folder: location.dataFolder(for: "org.example.kv"))
        let chunk = JSONValue.string(String(repeating: "x", count: 1_000_000))
        for i in 0..<5 { try await store.set("k\(i)", chunk) }
        do {
            try await store.set("k5", chunk)
            Issue.record("accepted past the quota")
        } catch let error as HostError {
            #expect(error.code == "quota_exceeded")
        }
        #expect(try await store.keys().count == 5)
        try await store.set("k0", .string("small")) // replacing frees room
        try await store.set("k5", chunk)
        #expect(try await store.usage() <= KeyValueStore.quota)
    }

    @Test func refusesBadKeys() async throws {
        let store = try KeyValueStore(folder: location.dataFolder(for: "org.example.kv"))
        await #expect(throws: HostError.self) { try await store.set("", .null) }
        await #expect(throws: HostError.self) { try await store.set(String(repeating: "k", count: 257), .null) }
    }

    @Test func aThousandWritesAndReadsTakeUnderASecond() async throws {
        let store = try KeyValueStore(folder: location.dataFolder(for: "org.example.kv"))
        let clock = ContinuousClock()
        let start = clock.now
        for i in 0..<1000 { try await store.set("key\(i)", .object(["n": .number(Double(i))])) }
        for i in 0..<1000 { _ = try await store.get("key\(i)") }
        #expect(clock.now - start < .seconds(1))
    }

    @Test func pluginCodeStoresThroughTheService() async throws {
        let plugin = try makePlugin("""
        globalThis.__baronPlugin = { actions: { async run(ctx, host) {
            await host.storage.set('history', ['fox']);
            const keys = await host.storage.keys();
            try { await host.storage.set('big', 'x'.repeat(1100000)); } catch (e) { return { type: 'copy', text: keys.join() + ' ' + e.code + ' ' + JSON.stringify(await host.storage.get('history')) }; }
        } } };
        """)
        let runtime = PluginRuntime(handler: HostRouter(services: [StorageService(stores: PluginStores(location: location))]), limits: .fast)
        await runtime.register(plugin)
        #expect(try await runtime.dispatch(plugin.id, .action, name: "run", payload: DispatchPayload()).get()["text"] == .string("history quota_exceeded [\"fox\"]"))
    }
}
