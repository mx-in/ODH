import BaronCore
import Foundation

/// A run-time permission question for the user.
public struct PermissionRequest: Equatable, Sendable {
    public var pluginID: String
    public var pluginName: String
    public var permission: String
}

/// Asks the user; the app shows a native prompt. Design: 04-permissions-and-security.md#asking-at-run-time
public protocol PermissionPrompter: Sendable {
    func ask(_ request: PermissionRequest) async -> PromptAnswer
}

/// `host.permissions`: query states, and request optional permissions one prompt at a time.
public struct PermissionService: HostService {
    public let namespace = "permissions"
    private let grants: GrantStore
    private let prompter: PermissionPrompter
    private let queue = PromptQueue()
    /// The plugin's display name for prompts.
    private let displayName: @Sendable (RuntimePlugin) -> String

    public init(grants: GrantStore, prompter: PermissionPrompter, displayName: @escaping @Sendable (RuntimePlugin) -> String = { $0.manifest.name }) {
        self.grants = grants
        self.prompter = prompter
        self.displayName = displayName
    }

    public func call(_ method: String, _ arguments: HostArguments, plugin: RuntimePlugin) async throws -> JSONValue {
        let names = try Self.names(arguments)
        switch method {
        case "query":
            let set = await grants.grantedSet(for: plugin)
            return .object(Dictionary(uniqueKeysWithValues: names.map { name in (name, .string(Self.state(of: name, in: set))) }))
        case "request":
            var set = await grants.grantedSet(for: plugin)
            for name in names {
                guard let permission = PluginPermission(name), permission != .anyNetwork, set.mayRequest(permission) else {
                    throw HostError("invalid_argument", "\(name) can't be requested: list it (or network:*) in optionalPermissions and ask for one host at a time",
                                    data: .object(["permission": .string(name)]))
                }
                if Self.state(of: name, in: set) != "prompt" { continue }
                let answer = await queue.run { await prompter.ask(PermissionRequest(pluginID: plugin.id, pluginName: displayName(plugin), permission: name)) }
                await grants.record(answer, for: name, pluginID: plugin.id)
                set = await grants.grantedSet(for: plugin)
            }
            return .array(names.filter { Self.state(of: $0, in: set) == "granted" }.map(JSONValue.string))
        default:
            throw arguments.unknownMethod()
        }
    }

    static func names(_ arguments: HostArguments) throws -> [String] {
        guard case .array(let items)? = arguments.values.first else { throw arguments.invalid(0, "a list of permission names") }
        return try items.enumerated().map { index, item in
            guard case .string(let name) = item else { throw HostError("invalid_argument", "Permission names are strings", data: .object(["path": .string("/0/\(index)")])) }
            return name
        }
    }

    static func state(of name: String, in set: GrantedSet) -> String {
        guard let permission = PluginPermission(name) else { return "denied" }
        if case .network(let pattern) = permission {
            let url = URL(string: "\(pattern.scheme ?? (pattern.isLoopback ? "http" : "https"))://\(pattern.host)\(pattern.port.map { ":\($0)" } ?? "")/")
            if !pattern.wildcard, let url, set.networkPermission(covering: url) != nil { return "granted" }
        }
        if set.holds(permission) { return "granted" }
        return set.mayRequest(permission) && !set.recentlyDenied.contains(name) && permission != .anyNetwork ? "prompt" : "denied"
    }
}

/// Runs prompts one at a time, across all plugins.
actor PromptQueue {
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ body: @escaping @Sendable () async -> T) async -> T {
        let previous = tail
        let task = Task<T, Never> {
            await previous?.value
            return await body()
        }
        tail = Task { _ = await task.value }
        return await task.value
    }
}
