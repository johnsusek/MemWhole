import Foundation
import SQLite3

struct SQLiteError: Error, CustomStringConvertible {
    let description: String
}

/// Tells SQLite to copy bound strings before the call returns.
nonisolated(unsafe) private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class Database {
    let handle: OpaquePointer

    init(path: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            throw SQLiteError(description: "Cannot open \(path): \(message)")
        }
        handle = db
    }

    deinit { sqlite3_close_v2(handle) }

    func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(error)
            throw SQLiteError(description: message)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        try Statement(db: self, sql: sql)
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try exec("COMMIT")
            return result
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }
    var errorMessage: String { String(cString: sqlite3_errmsg(handle)) }
}

protocol SQLBindable {
    func bind(to stmt: OpaquePointer, at index: Int32) -> Int32
}

extension String: SQLBindable {
    func bind(to stmt: OpaquePointer, at index: Int32) -> Int32 {
        sqlite3_bind_text(stmt, index, self, -1, SQLITE_TRANSIENT)
    }
}

extension Int: SQLBindable {
    func bind(to stmt: OpaquePointer, at index: Int32) -> Int32 {
        sqlite3_bind_int64(stmt, index, Int64(self))
    }
}

extension Int64: SQLBindable {
    func bind(to stmt: OpaquePointer, at index: Int32) -> Int32 {
        sqlite3_bind_int64(stmt, index, self)
    }
}

extension Double: SQLBindable {
    func bind(to stmt: OpaquePointer, at index: Int32) -> Int32 {
        sqlite3_bind_double(stmt, index, self)
    }
}

extension Bool: SQLBindable {
    func bind(to stmt: OpaquePointer, at index: Int32) -> Int32 {
        sqlite3_bind_int(stmt, index, self ? 1 : 0)
    }
}

final class Statement {
    private let stmt: OpaquePointer
    private unowned let db: Database

    init(db: Database, sql: String) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db.handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw SQLiteError(description: "\(db.errorMessage)\nin: \(sql)")
        }
        self.stmt = stmt
        self.db = db
    }

    deinit { sqlite3_finalize(stmt) }

    /// Resets the statement and binds `values` to parameters 1...n.
    @discardableResult
    func bind(_ values: [SQLBindable?]) throws -> Statement {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let rc = value?.bind(to: stmt, at: index) ?? sqlite3_bind_null(stmt, index)
            guard rc == SQLITE_OK else { throw SQLiteError(description: db.errorMessage) }
        }
        return self
    }

    /// Advances to the next row. Returns false when the statement is done.
    func step() throws -> Bool {
        switch sqlite3_step(stmt) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw SQLiteError(description: db.errorMessage)
        }
    }

    func run(_ values: SQLBindable?...) throws {
        try bind(values)
        while try step() {}
    }

    /// Runs the statement and returns the first column of the first row as an integer.
    func scalar(_ values: SQLBindable?...) throws -> Int64? {
        try bind(values)
        return try step() ? int64(0) : nil
    }

    func isNull(_ column: Int32) -> Bool { sqlite3_column_type(stmt, column) == SQLITE_NULL }
    func int64(_ column: Int32) -> Int64 { sqlite3_column_int64(stmt, column) }
    func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(stmt, column)) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(stmt, column) }

    func text(_ column: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: cString)
    }
}
