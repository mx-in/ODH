import BaronCore
import Foundation

/// Opens each plugin's stores once and hands out the same actor afterwards, so writes stay serialised.
public actor PluginStores {
    public let location: PluginDataLocation
    private var storage: [String: KeyValueStore] = [:]
    private var caches: [String: CacheStore] = [:]

    public init(location: PluginDataLocation) {
        self.location = location
    }

    public func storage(for pluginID: String) throws -> KeyValueStore {
        if let store = storage[pluginID] { return store }
        let store = try KeyValueStore(folder: location.dataFolder(for: pluginID))
        storage[pluginID] = store
        return store
    }

    public func cache(for pluginID: String) throws -> CacheStore {
        if let store = caches[pluginID] { return store }
        let store = try CacheStore(folder: location.cacheFolder(for: pluginID))
        caches[pluginID] = store
        return store
    }
}
