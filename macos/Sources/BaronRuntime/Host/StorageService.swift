import BaronCore

/// `host.storage`: JSON values private to the plugin. Design: 05-storage.md
public struct StorageService: HostService {
    public let namespace = "storage"
    private let stores: PluginStores

    public init(stores: PluginStores) {
        self.stores = stores
    }

    public func call(_ method: String, _ arguments: HostArguments, plugin: RuntimePlugin) async throws -> JSONValue {
        let store = try await stores.storage(for: plugin.id)
        switch method {
        case "get": return try await store.get(try arguments.string(0)) ?? .null
        case "set":
            guard arguments.values.count > 1 else { throw arguments.invalid(1, "a value") }
            try await store.set(try arguments.string(0), arguments.values[1])
            return .null
        case "remove": try await store.remove(try arguments.string(0)); return .null
        case "keys": return .array(try await store.keys().map(JSONValue.string))
        case "usage": return .number(Double(try await store.usage()))
        default: throw arguments.unknownMethod()
        }
    }
}
