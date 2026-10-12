import Foundation
import SQLite3

enum DBIntegrityChecks {
    static func run() -> [String] {
        var issues: [String] = []
        let dbPath = SQLiteDataProvider().getUserDatabasePath()
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            issues.append("Could not open DB at \(dbPath)")
            return issues
        }
        defer { sqlite3_close(db) }

        // Enable foreign keys
        exec(db: db, sql: "PRAGMA foreign_keys = ON;")

        // Required tables exist
        for table in ["contacts", "groups", "invites"] {
            if !tableExists(db: db, name: table) {
                issues.append("Missing table: \(table)")
            }
        }

        // Basic FK check (if PRAGMA foreign_key_check exists)
        if let fkIssues = foreignKeyCheck(db: db), !fkIssues.isEmpty {
            issues.append(contentsOf: fkIssues)
        }

        return issues
    }

    private static func exec(db: OpaquePointer?, sql: String) {
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let e = err {
            print("DBIntegrityChecks exec error: \(String(cString: e))")
            sqlite3_free(err)
        }
    }

    private static func tableExists(db: OpaquePointer?, name: String) -> Bool {
        var stmt: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) == SQLITE_ROW { return true }
        return false
    }

    private static func foreignKeyCheck(db: OpaquePointer?) -> [String]? {
        var stmt: OpaquePointer?
        let sql = "PRAGMA foreign_key_check;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        var issues: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let table = String(cString: sqlite3_column_text(stmt, 0))
            let rowId = sqlite3_column_int64(stmt, 1)
            issues.append("FK violation in \(table) at rowid \(rowId)")
        }
        return issues
    }
}




