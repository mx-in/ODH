import BaronCore

/// `host.cache`: disposable strings the plugin can rebuild. Design: 05-storage.md
public struct CacheService: HostService {
    public let namespace = "cache"
    private let stores: PluginStores

    public init(stores: PluginStores) {
        self.stores = stores
    }

    public func call(_ method: String, _ arguments: HostArguments, plugin: RuntimePlugin) async throws -> JSONValue {
        let cache = try await stores.cache(for: plugin.id)
        switch method {
        case "get": return try await cache.get(try arguments.string(0)).map(JSONValue.string) ?? .null
        case "set": try await cache.set(try arguments.string(0), try arguments.string(1)); return .null
        case "remove": try await cache.remove(try arguments.string(0)); return .null
        case "clear": try await cache.clear(); return .null
        default: throw arguments.unknownMethod()
        }
    }
}
