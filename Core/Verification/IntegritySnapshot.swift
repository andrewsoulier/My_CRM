import Foundation
import SQLite3

struct IntegritySnapshot: Equatable {
    let contactCount: Int
    let groupCount: Int
    let inviteCount: Int
    let lastMessageTimestamp: Double

    static func collect() -> IntegritySnapshot {
        let dbPath = SQLiteDataProvider().getUserDatabasePath()
        var db: OpaquePointer?
        var contactCount = 0
        var groupCount = 0
        var inviteCount = 0
        var lastMessageTimestamp: Double = 0

        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            defer { sqlite3_close(db) }
            contactCount = queryCount(db: db, table: "contacts")
            groupCount = queryCount(db: db, table: "groups")
            inviteCount = queryCount(db: db, table: "invites")
            lastMessageTimestamp = queryMaxDouble(db: db, sql: "SELECT COALESCE(MAX(timestamp), 0) FROM messages;")
        }

        return IntegritySnapshot(contactCount: contactCount,
                                 groupCount: groupCount,
                                 inviteCount: inviteCount,
                                 lastMessageTimestamp: lastMessageTimestamp)
    }

    func diff(from other: IntegritySnapshot) -> [String: Any] {
        var result: [String: Any] = [:]
        if contactCount != other.contactCount { result["contactsDelta"] = contactCount - other.contactCount }
        if groupCount != other.groupCount { result["groupsDelta"] = groupCount - other.groupCount }
        if inviteCount != other.inviteCount { result["invitesDelta"] = inviteCount - other.inviteCount }
        if lastMessageTimestamp != other.lastMessageTimestamp { result["lastMessageTsDelta"] = lastMessageTimestamp - other.lastMessageTimestamp }
        return result
    }

    private static func queryCount(db: OpaquePointer?, table: String) -> Int {
        var stmt: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM \(table);"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW { return Int(sqlite3_column_int(stmt, 0)) }
        return 0
    }

    private static func queryMaxDouble(db: OpaquePointer?, sql: String) -> Double {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW { return sqlite3_column_double(stmt, 0) }
        return 0
    }
}




