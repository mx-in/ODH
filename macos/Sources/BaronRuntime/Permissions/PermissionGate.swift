import BaronCore
import Foundation

/// Checks every routed call before its service runs: the method's permission against the plugin's granted set,
/// and a recent user action where the method needs one. Network permissions are checked per URL by HTTPService.
/// Design: 04-permissions-and-security.md
public struct PermissionGate: Sendable {
    public let grants: GrantStore
    public let actions: UserActionTracker

    public init(grants: GrantStore, actions: UserActionTracker) {
        self.grants = grants
        self.actions = actions
    }

    public func check(_ call: HostCall, _ plugin: RuntimePlugin) async -> HostError? {
        guard let requirement = HostMethodRequirement.of(namespace: call.namespace, method: call.method) else { return nil }
        if let permission = requirement.permission {
            let set = await grants.grantedSet(for: plugin)
            if !set.holds(permission) {
                return Self.denied(permission.description, requestable: set.mayRequest(permission) && !set.recentlyDenied.contains(permission.description))
            }
        }
        if requirement.needsUserAction, !actions.hasRecentAction(plugin.id) {
            return HostError("user_action_required", "host.\(call.namespace).\(call.method) needs a click on the plugin within the last \(Int(UserActionTracker.window)) seconds")
        }
        return nil
    }

    static func denied(_ permission: String, requestable: Bool) -> HostError {
        HostError("permission_denied", "\(permission) isn't granted", data: .object(["permission": .string(permission), "requestable": .bool(requestable)]))
    }
}

extension HostRouter {
    /// A router whose every call passes the permission gate first.
    public init(services: [HostService], gate: PermissionGate) {
        self.init(services: services, check: { call, plugin in await gate.check(call, plugin) })
    }
}
