import BaronCore
import Foundation

/// `host.storage` for one plugin: JSON values in `PluginData/<id>/storage.sqlite`. Writes are serialised by the actor;
/// a write that would pass the quota (keys plus values, in bytes) fails with `quota_exceeded` and changes nothing.
public actor KeyValueStore {
    public static let quota = 5 * 1024 * 1024
    public static let valueLimit = 1024 * 1024
    public static let keyLimit = 256

    private let database: SQLiteDatabase

    public init(folder: URL) throws {
        database = try SQLiteDatabase(path: folder.appendingPathComponent("storage.sqlite"))
        try database.execute("CREATE TABLE IF NOT EXISTS entries (key TEXT PRIMARY KEY, value TEXT NOT NULL, size INTEGER NOT NULL)")
    }

    public func get(_ key: String) throws -> JSONValue? {
        try database.query("SELECT value FROM entries WHERE key = ?", [.text(key)]).first?.first?.text.flatMap { try? JSONValue(data: Data($0.utf8)) }
    }

    public func set(_ key: String, _ value: JSONValue) throws {
        try Self.checkKey(key)
        let json = value.jsonString
        let size = key.utf8.count + json.utf8.count
        if json.utf8.count > Self.valueLimit {
            throw Self.quotaError("A stored value can be at most 1 MB", limit: Self.valueLimit, used: json.utf8.count)
        }
        try database.transaction {
            let others = try database.query("SELECT COALESCE(SUM(size), 0) FROM entries WHERE key != ?", [.text(key)]).first?.first?.integer ?? 0
            if Int(others) + size > Self.quota {
                throw Self.quotaError("Storage is full (5 MB per plugin)", limit: Self.quota, used: Int(others))
            }
            try database.query("INSERT OR REPLACE INTO entries (key, value, size) VALUES (?, ?, ?)", [.text(key), .text(json), .integer(Int64(size))])
        }
    }

    public func remove(_ key: String) throws {
        try database.query("DELETE FROM entries WHERE key = ?", [.text(key)])
    }

    public func keys() throws -> [String] {
        try database.query("SELECT key FROM entries ORDER BY key").compactMap { $0.first?.text }
    }

    public func usage() throws -> Int {
        Int(try database.query("SELECT COALESCE(SUM(size), 0) FROM entries").first?.first?.integer ?? 0)
    }

    public func clear() throws {
        try database.execute("DELETE FROM entries")
    }

    static func checkKey(_ key: String) throws {
        guard !key.isEmpty, key.count <= keyLimit else { throw HostError("invalid_argument", "Keys are 1 to 256 characters", data: .object(["path": .string("/0")])) }
    }

    static func quotaError(_ message: String, limit: Int, used: Int) -> HostError {
        HostError("quota_exceeded", message, data: .object(["limit": .number(Double(limit)), "used": .number(Double(used))]))
    }
}
