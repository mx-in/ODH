import BaronCore
import Foundation

/// Decides whether a plugin may reach a URL: its granted network permissions, checked on the first URL and on
/// every redirect hop. Design: 04-permissions-and-security.md#network-patterns
public struct NetworkPolicy: Sendable {
    public let grants: GrantStore

    public init(grants: GrantStore) {
        self.grants = grants
    }

    /// Nil when allowed; otherwise the error the plugin sees.
    public func check(_ url: URL, for plugin: RuntimePlugin) async -> HostError? {
        guard let target = NetworkTarget(url) else { return .invalidArgument("Only http and https URLs can be fetched") }
        let set = await grants.grantedSet(for: plugin)
        if set.networkPermission(covering: url) != nil { return nil }
        let name = target.permissionName
        let requestable = PluginPermission(name).map(set.mayRequest) == true && !set.recentlyDenied.contains(name)
        return PermissionGate.denied(name, requestable: requestable)
    }
}
