import Foundation

/// Remembers when the user last clicked a plugin's bar button (and, from task-010, its panel), so calls that act
/// on the user's behalf can't run in the background. Design: 03-host-api-and-ipc.md#namespace-rules
public final class UserActionTracker: @unchecked Sendable {
    public static let window: TimeInterval = 5

    private let lock = NSLock()
    private var last: [String: Date] = [:]
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func record(_ pluginID: String) {
        lock.withLock { last[pluginID] = now() }
    }

    public func hasRecentAction(_ pluginID: String) -> Bool {
        lock.withLock { last[pluginID].map { now().timeIntervalSince($0) <= Self.window } ?? false }
    }
}
