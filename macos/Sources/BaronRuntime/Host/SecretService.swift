import BaronCore

/// `host.secrets`: the plugin's own Keychain items; needs `secrets` (checked by the gate).
public struct SecretService: HostService {
    public let namespace = "secrets"
    private let store: SecretStore

    public init(store: SecretStore = SecretStore()) {
        self.store = store
    }

    public func call(_ method: String, _ arguments: HostArguments, plugin: RuntimePlugin) async throws -> JSONValue {
        switch method {
        case "get": return try store.get(try arguments.string(0), pluginID: plugin.id).map(JSONValue.string) ?? .null
        case "set": try store.set(try arguments.string(0), try arguments.string(1), pluginID: plugin.id); return .null
        case "remove": try store.remove(try arguments.string(0), pluginID: plugin.id); return .null
        default: throw arguments.unknownMethod()
        }
    }
}
