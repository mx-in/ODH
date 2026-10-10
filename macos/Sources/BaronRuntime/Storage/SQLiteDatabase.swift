import Foundation
import SQLite3

/// A small wrapper over the system SQLite: one connection, used from one actor at a time.
final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?

    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    init(path: URL) throws {
        guard sqlite3_open_v2(path.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw Failure(description: "Can't open \(path.lastPathComponent)")
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw Failure(description: lastError) }
    }

    enum Value {
        case text(String)
        case integer(Int64)
        case real(Double)
        case null
    }

    /// Runs a statement with bound values and returns its rows.
    @discardableResult
    func query(_ sql: String, _ values: [Value] = []) throws -> [[Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw Failure(description: lastError) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, position, text, -1, transient)
            case .integer(let number): sqlite3_bind_int64(statement, position, number)
            case .real(let number): sqlite3_bind_double(statement, position, number)
            case .null: sqlite3_bind_null(statement, position)
            }
        }
        var rows: [[Value]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                rows.append((0..<sqlite3_column_count(statement)).map { column in
                    switch sqlite3_column_type(statement, column) {
                    case SQLITE_INTEGER: .integer(sqlite3_column_int64(statement, column))
                    case SQLITE_FLOAT: .real(sqlite3_column_double(statement, column))
                    case SQLITE_NULL: .null
                    default: .text(String(cString: sqlite3_column_text(statement, column)))
                    }
                })
            case SQLITE_DONE:
                return rows
            default:
                throw Failure(description: lastError)
            }
        }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private var lastError: String { String(cString: sqlite3_errmsg(handle)) }
}

extension SQLiteDatabase.Value {
    var text: String? { if case .text(let t) = self { t } else { nil } }
    var integer: Int64? { if case .integer(let n) = self { n } else { nil } }
}
