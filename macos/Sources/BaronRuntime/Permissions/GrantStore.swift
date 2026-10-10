import BaronCore
import Foundation

/// The user's answer to a run-time permission prompt.
public enum PromptAnswer: String, Codable, Sendable {
    case deny, allowOnce, alwaysAllow
}

/// A saved run-time decision. Design: 04-permissions-and-security.md#asking-at-run-time
public struct RuntimeGrant: Codable, Equatable, Sendable {
    public var permission: String
    public var answer: PromptAnswer
    public var decidedAt: Date
}

/// What a plugin may do right now: its install-time permissions plus run-time grants still in force.
public struct GrantedSet: Sendable {
    public var permissions: [PluginPermission]
    /// Permissions denied within the last 24 hours, which aren't asked about again.
    public var recentlyDenied: Set<String>
    /// The plugin's optional permissions, which it may ask for.
    public var optional: [PluginPermission]

    public func holds(_ permission: PluginPermission) -> Bool {
        permissions.contains(permission)
    }

    /// The network permission that covers the URL, if any.
    public func networkPermission(covering url: URL) -> NetworkPattern? {
        for case .network(let pattern) in permissions where pattern.covers(url) { return pattern }
        return nil
    }

    /// Whether the plugin may ask for the permission at run time.
    public func mayRequest(_ permission: PluginPermission) -> Bool {
        if optional.contains(permission) { return true }
        if case .network = permission { return optional.contains(.anyNetwork) }
        return false
    }
}

/// Keeps run-time grants per plugin in `<folder>/<plugin id>/grants.json`: Always Allow until revoked, Deny for
/// 24 hours; Allow Once lives in memory for 10 minutes.
public actor GrantStore {
    public static let denyLasts: TimeInterval = 24 * 60 * 60
    public static let allowOnceLasts: TimeInterval = 10 * 60

    private let folder: URL
    private let now: @Sendable () -> Date
    private var once: [String: [String: Date]] = [:]

    /// `folder` is Application Support/Baron/PluginData in the app.
    public init(folder: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.folder = folder
        self.now = now
    }

    public static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Baron.name).appendingPathComponent("PluginData")
    }

    public func grantedSet(for plugin: RuntimePlugin) -> GrantedSet {
        let time = now()
        var permissions = plugin.manifest.permissions.compactMap(PluginPermission.init)
        var denied = Set<String>()
        for grant in saved(plugin.id) {
            switch grant.answer {
            case .alwaysAllow: if let p = PluginPermission(grant.permission) { permissions.append(p) }
            case .deny: if time.timeIntervalSince(grant.decidedAt) < Self.denyLasts { denied.insert(grant.permission) }
            case .allowOnce: break
            }
        }
        for (name, until) in once[plugin.id] ?? [:] where until > time {
            if let p = PluginPermission(name) { permissions.append(p) }
        }
        return GrantedSet(permissions: permissions, recentlyDenied: denied, optional: plugin.manifest.optionalPermissions.compactMap(PluginPermission.init))
    }

    public func record(_ answer: PromptAnswer, for permission: String, pluginID: String) {
        if answer == .allowOnce {
            once[pluginID, default: [:]][permission] = now().addingTimeInterval(Self.allowOnceLasts)
            return
        }
        var grants = saved(pluginID).filter { $0.permission != permission }
        grants.append(RuntimeGrant(permission: permission, answer: answer, decidedAt: now()))
        save(grants, pluginID)
    }

    /// Run-time grants the user can see and remove in Settings (task-007).
    public func runtimeGrants(for pluginID: String) -> [RuntimeGrant] {
        saved(pluginID)
    }

    public func revoke(_ permission: String, pluginID: String) {
        once[pluginID]?[permission] = nil
        save(saved(pluginID).filter { $0.permission != permission }, pluginID)
    }

    /// Drops the plugin's grants, saved and in memory (uninstalling).
    public func forget(pluginID: String) {
        once[pluginID] = nil
        try? FileManager.default.removeItem(at: file(pluginID))
    }

    private func file(_ pluginID: String) -> URL {
        folder.appendingPathComponent(pluginID).appendingPathComponent("grants.json")
    }

    private func saved(_ pluginID: String) -> [RuntimeGrant] {
        guard let data = try? Data(contentsOf: file(pluginID)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RuntimeGrant].self, from: data)) ?? []
    }

    private func save(_ grants: [RuntimeGrant], _ pluginID: String) {
        let url = file(pluginID)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(grants).write(to: url, options: .atomic)
    }
}
