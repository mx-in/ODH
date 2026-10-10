import BaronCore
import Foundation
import Testing
@testable import BaronRuntime

@Suite(.serialized)
struct PluginDataManagerTests {
    let location = PluginDataLocation.temporary()
    let secrets = SecretStore(servicePrefix: "org.odh.baron.test.\(UUID().uuidString).")
    let id = "org.example.data"

    var manager: PluginDataManager {
        PluginDataManager(stores: PluginStores(location: location), preferences: PreferencesStore(location: location),
                          secrets: secrets, grants: GrantStore(folder: location.dataRoot))
    }

    func fill(_ manager: PluginDataManager) async throws {
        try await manager.stores.storage(for: id).set("history", .array([.string("fox")]))
        try await manager.stores.cache(for: id).set("fox", "dog")
        try await manager.preferences.set("deck", to: .string("Words"), pluginID: id)
        try secrets.set("apiKey", "sk", pluginID: id)
        await manager.grants.record(.alwaysAllow, for: "network:dict.cn", pluginID: id)
    }

    @Test func reportsUsageAndClearsTheCache() async throws {
        let manager = self.manager
        defer { try? secrets.removeAll(pluginID: id) }
        try await fill(manager)
        let usage = try await manager.usage(id)
        #expect(usage.storageBytes > 0 && usage.cacheBytes > 0 && usage.secrets == 1)
        try await manager.clearCache(id)
        #expect(try await manager.usage(id).cacheBytes == 0)
        #expect(try await manager.usage(id).storageBytes == usage.storageBytes)
    }

    @Test func resetKeepsGrantsButDropsData() async throws {
        let manager = self.manager
        defer { try? secrets.removeAll(pluginID: id) }
        try await fill(manager)
        try await manager.reset(id)
        #expect(try await manager.usage(id) == PluginDataUsage(storageBytes: 0, cacheBytes: 0, secrets: 0))
        #expect(await manager.preferences.saved(id).isEmpty)
        #expect(await manager.grants.runtimeGrants(for: id).count == 1)
    }

    @Test func removeAllLeavesNothingOnDiskOrInTheKeychain() async throws {
        let manager = self.manager
        try await fill(manager)
        try await manager.removeAll(id)
        #expect(!FileManager.default.fileExists(atPath: location.dataRoot.appendingPathComponent(id).path))
        #expect(!FileManager.default.fileExists(atPath: location.cacheRoot.appendingPathComponent(id).path))
        #expect(secrets.keys(pluginID: id).isEmpty)
        #expect(await manager.grants.runtimeGrants(for: id).isEmpty)
    }
}
