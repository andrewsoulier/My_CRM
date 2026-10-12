import Foundation
import SQLite3

/// DEPRECATED: This class is replaced by MessageRepository using GRDB
/// Will be removed in future version - kept for backwards compatibility only
/// Use MessageRepository with GRDBDatabaseManager instead
@available(*, deprecated, message: "Use MessageRepository with GRDB instead")
final class MessagesDAO {
    func ensureSchema(db: OpaquePointer?) {
        let sql = """
        CREATE TABLE IF NOT EXISTS messages (
            guid TEXT PRIMARY KEY,
            rowid INTEGER,
            body TEXT,
            phone_number TEXT,
            is_from_me BOOLEAN,
            cache_roomname TEXT,
            group_chat_name TEXT,
            timestamp INTEGER,
            service TEXT,
            account TEXT,
            chat_id TEXT,
            attributedBody BLOB,
            subject TEXT,
            country TEXT,
            error INTEGER,
            date_read INTEGER,
            date_delivered INTEGER,
            is_sent INTEGER,
            is_read INTEGER,
            has_attachments BOOLEAN DEFAULT 0,
            contact_id INTEGER,
            message_type TEXT,
            is_first_message INTEGER DEFAULT 0,
            is_last_message INTEGER DEFAULT 0,
            is_new INTEGER DEFAULT 0,
            source TEXT DEFAULT 'imessage'
        );
        """
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let e = err {
            print("MessagesDAO ensureSchema error: \(String(cString: e))")
            sqlite3_free(err)
        }
    }

    func upsertBatch(db: OpaquePointer?, rows: [[String: Any]]) {
        ensureSchema(db: db)
        let cols = [
            "guid","rowid","body","phone_number","is_from_me","cache_roomname","group_chat_name",
            "timestamp","service","account","chat_id","attributedBody","subject","country","error",
            "date_read","date_delivered","is_sent","is_read","has_attachments","contact_id","message_type",
            "is_first_message","is_last_message","is_new","source"
        ]
        let placeholders = Array(repeating: "?", count: cols.count).joined(separator: ",")
        let sql = "INSERT OR REPLACE INTO messages (\(cols.joined(separator: ","))) VALUES (\(placeholders))"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)
        for row in rows {
            var idx: Int32 = 1
            for key in cols {
                bind(row[key], to: stmt, index: idx)
                idx += 1
            }
            _ = sqlite3_step(stmt)
            sqlite3_reset(stmt)
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    private func bind(_ value: Any?, to stmt: OpaquePointer?, index: Int32) {
        switch value {
        case let s as String:
            s.withCString { cStringPtr in
                sqlite3_bind_text(stmt, index, cStringPtr, -1, SQLITE_TRANSIENT)
            }
        case let n as Int:
            sqlite3_bind_int64(stmt, index, sqlite3_int64(n))
        case let n as Int64:
            sqlite3_bind_int64(stmt, index, sqlite3_int64(n))
        case let b as Bool:
            sqlite3_bind_int(stmt, index, b ? 1 : 0)
        case let d as Data:
            d.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    sqlite3_bind_blob(stmt, index, base, Int32(d.count), SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, index)
                }
            }
        default:
            sqlite3_bind_null(stmt, index)
        }
    }
    
    /// Get the timestamp of the most recent message in the database
    /// Returns Unix epoch milliseconds or nil if no messages exist
    func getLastMessageTimestamp() -> Int64? {
        guard let db = try? CRMDatabase.shared.open() else {
            print("❌ MessagesDAO: Failed to open database")
            return nil
        }
        defer { sqlite3_close(db) }
        
        ensureSchema(db: db)
        
        let sql = """
        SELECT MAX(COALESCE(timestamp, 0))
        FROM messages
        WHERE timestamp IS NOT NULL AND timestamp > 0
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("❌ MessagesDAO: Failed to prepare getLastMessageTimestamp statement")
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            let timestamp = sqlite3_column_int64(stmt, 0)
            return timestamp > 0 ? timestamp : nil
        }
        
        return nil
    }
    
    /// Get the timestamp of the most recent message as a Date
    /// Returns Date or nil if no messages exist
    func getLastMessageDate() -> Date? {
        guard let timestamp = getLastMessageTimestamp() else {
            return nil
        }
        
        // Convert Unix epoch milliseconds to Date
        let seconds = Double(timestamp) / 1000.0
        return Date(timeIntervalSince1970: seconds)
    }
}


