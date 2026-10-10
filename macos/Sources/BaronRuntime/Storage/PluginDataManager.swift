import BaronCore
import Foundation

/// How much a plugin keeps, for the Data section of its settings.
public struct PluginDataUsage: Equatable, Sendable {
    public var storageBytes: Int
    public var cacheBytes: Int
    public var secrets: Int
}

/// Clears, resets and removes a plugin's data: storage, cache, preferences, secrets and grants. Design: 05-storage.md#update-and-uninstall
public struct PluginDataManager: Sendable {
    public let stores: PluginStores
    public let preferences: PreferencesStore
    public let secrets: SecretStore
    public let grants: GrantStore

    public init(stores: PluginStores, preferences: PreferencesStore, secrets: SecretStore, grants: GrantStore) {
        self.stores = stores
        self.preferences = preferences
        self.secrets = secrets
        self.grants = grants
    }

    public func usage(_ pluginID: String) async throws -> PluginDataUsage {
        PluginDataUsage(storageBytes: try await stores.storage(for: pluginID).usage(),
                        cacheBytes: try await stores.cache(for: pluginID).usage(),
                        secrets: secrets.keys(pluginID: pluginID).count)
    }

    public func clearCache(_ pluginID: String) async throws {
        try await stores.cache(for: pluginID).clear()
    }

    /// Back to a fresh install: storage, cache, preferences and secrets go; run-time grants stay.
    public func reset(_ pluginID: String) async throws {
        try await stores.storage(for: pluginID).clear()
        try await stores.cache(for: pluginID).clear()
        try await preferences.clearAll(pluginID: pluginID)
        try secrets.removeAll(pluginID: pluginID)
    }

    /// Everything Baron kept for the plugin, for uninstalling: nothing is left on disk or in the Keychain.
    public func removeAll(_ pluginID: String) async throws {
        try secrets.removeAll(pluginID: pluginID)
        await grants.forget(pluginID: pluginID)
        await stores.forget(pluginID)
        for root in [stores.location.dataRoot, stores.location.cacheRoot] {
            let folder = root.appendingPathComponent(pluginID, isDirectory: true)
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        }
    }
}
