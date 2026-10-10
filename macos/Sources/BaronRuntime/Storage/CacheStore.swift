import BaronCore
import Foundation

/// `host.cache` for one plugin: disposable strings in `PluginCache/<id>/cache.sqlite`. After each write the least
/// recently read entries go until the cache is under 10 MB; macOS may also purge the folder. Design: 05-storage.md
public actor CacheStore {
    public static let limit = 10 * 1024 * 1024
    public static let valueLimit = 2 * 1024 * 1024

    private let database: SQLiteDatabase
    private var tick: Int64 = 0

    public init(folder: URL) throws {
        database = try SQLiteDatabase(path: folder.appendingPathComponent("cache.sqlite"))
        try database.execute("CREATE TABLE IF NOT EXISTS entries (key TEXT PRIMARY KEY, value TEXT NOT NULL, size INTEGER NOT NULL, used INTEGER NOT NULL)")
        tick = try database.query("SELECT COALESCE(MAX(used), 0) FROM entries").first?.first?.integer ?? 0
    }

    /// Reading marks the entry as recently used.
    public func get(_ key: String) throws -> String? {
        guard let value = try database.query("SELECT value FROM entries WHERE key = ?", [.text(key)]).first?.first?.text else { return nil }
        tick += 1
        try database.query("UPDATE entries SET used = ? WHERE key = ?", [.integer(tick), .text(key)])
        return value
    }

    public func set(_ key: String, _ value: String) throws {
        try KeyValueStore.checkKey(key)
        if value.utf8.count > Self.valueLimit {
            throw KeyValueStore.quotaError("A cached value can be at most 2 MB", limit: Self.valueLimit, used: value.utf8.count)
        }
        tick += 1
        try database.transaction {
            try database.query("INSERT OR REPLACE INTO entries (key, value, size, used) VALUES (?, ?, ?, ?)",
                               [.text(key), .text(value), .integer(Int64(key.utf8.count + value.utf8.count)), .integer(tick)])
            try evict()
        }
    }

    private func evict() throws {
        var total = try database.query("SELECT COALESCE(SUM(size), 0) FROM entries").first?.first?.integer ?? 0
        guard total > Self.limit else { return }
        for row in try database.query("SELECT key, size FROM entries ORDER BY used ASC") where total > Self.limit {
            guard let key = row[0].text, let size = row[1].integer else { continue }
            try database.query("DELETE FROM entries WHERE key = ?", [.text(key)])
            total -= size
        }
    }

    public func remove(_ key: String) throws {
        try database.query("DELETE FROM entries WHERE key = ?", [.text(key)])
    }

    public func clear() throws {
        try database.execute("DELETE FROM entries")
    }

    public func usage() throws -> Int {
        Int(try database.query("SELECT COALESCE(SUM(size), 0) FROM entries").first?.first?.integer ?? 0)
    }

    public func keys() throws -> [String] {
        try database.query("SELECT key FROM entries ORDER BY key").compactMap { $0.first?.text }
    }
}
