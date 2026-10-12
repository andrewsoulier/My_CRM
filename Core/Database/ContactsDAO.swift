import Foundation
import SQLite3

/// DEPRECATED: This class is replaced by ContactRepository using GRDB
/// Will be removed in future version - kept for backwards compatibility only
/// Use ContactRepository with GRDBDatabaseManager instead
@available(*, deprecated, message: "Use ContactRepository with GRDB instead")
final class ContactsDAO {
    func ensureSchema(db: OpaquePointer?) {
        let sql = """
        CREATE TABLE IF NOT EXISTS contacts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            phone TEXT UNIQUE NOT NULL,
            name TEXT,
            nickname TEXT,
            first_name TEXT,
            last_name TEXT,
            email TEXT,
            address TEXT,
            notes TEXT,
            creation_date DATETIME DEFAULT CURRENT_TIMESTAMP,
            business TEXT,
            contact_group TEXT,
            birthday TEXT,
            apple_contact_id TEXT,
            profile_photo BLOB,
            first_message_date TEXT,
            last_message_date TEXT,
            last_message_sent_date TEXT,
            last_message_received_date TEXT,
            total_messages INTEGER DEFAULT 0,
            messages_sent INTEGER DEFAULT 0,
            messages_received INTEGER DEFAULT 0,
            is_primary_user INTEGER DEFAULT 0,
            sent_last_message INTEGER,
            groups TEXT DEFAULT '[]',
            tag_ids TEXT DEFAULT '[]',
            relationship_ids TEXT DEFAULT '[]'
        );
        """
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let e = err {
            print("❌ ContactsDAO ensureSchema error: \(String(cString: e))")
            sqlite3_free(err)
        }
        
        // Ensure new columns exist for older databases
        let columns = existingColumns(db: db, table: "contacts")
        addColumnIfMissing("nickname", type: "TEXT", defaultClause: nil, existingColumns: columns, db: db)
        addColumnIfMissing("tag_ids", type: "TEXT", defaultClause: "DEFAULT '[]'", existingColumns: columns, db: db)
        addColumnIfMissing("relationship_ids", type: "TEXT", defaultClause: "DEFAULT '[]'", existingColumns: columns, db: db)
        addColumnIfMissing("last_message_sent_date", type: "TEXT", defaultClause: nil, existingColumns: columns, db: db)
        addColumnIfMissing("last_message_received_date", type: "TEXT", defaultClause: nil, existingColumns: columns, db: db)
    }
    
    /// Upsert with an existing database connection (preferred for batch operations)
    func upsertWithConnection(db: OpaquePointer?,
                             phone: String,
                             name: String?,
                             firstName: String?,
                             lastName: String?,
                             email: String?,
                             appleContactID: String?,
                             profilePhotoData: Data?,
                             nickname: String? = nil) {
        guard db != nil else {
            print("❌ ContactsDAO.upsertWithConnection: Invalid database connection")
            return
        }

        let columns = existingColumns(db: db, table: "contacts")

        // Determine if a row exists by phone (unique in schema)
        let exists = rowExists(db: db, phone: phone)
        
        // Auto-populate nickname with firstName if nickname is empty
        let finalNickname: String?
        if let nickname = nickname, !nickname.isEmpty {
            finalNickname = nickname
        } else if let firstName = firstName, !firstName.isEmpty {
            finalNickname = firstName
        } else {
            finalNickname = nil
        }

        // Build dynamic sets based on available columns
        var fields: [(String, Any?)] = [
            ("phone", phone),
            ("name", name),
            ("email", email),
            ("first_name", firstName),
            ("last_name", lastName),
            ("nickname", finalNickname),
            ("apple_contact_id", appleContactID),
            ("profile_photo", profilePhotoData)
        ]

        // Keep only columns that exist
        fields = fields.filter { columns.contains($0.0) }

        if exists {
            // Filter out phone from the update fields
            let updateFields = fields.filter { $0.0 != "phone" }
            let assignments = updateFields.map { "\($0.0) = ?" }.joined(separator: ", ")
            let sql = "UPDATE contacts SET \(assignments) WHERE phone = ?"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                var idx: Int32 = 1
                // Bind all non-phone field values in order
                for (_, value) in updateFields {
                    bind(value: value, to: stmt, index: idx)
                    idx += 1
                }
                // Bind phone for WHERE clause
                sqlite3_bind_text(stmt, idx, phone, -1, nil)
                let stepResult = sqlite3_step(stmt)
                if stepResult != SQLITE_DONE {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    print("❌ ContactsDAO.upsert: UPDATE failed for phone \(phone): \(errorMessage)")
                }
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                print("❌ ContactsDAO.upsert: Failed to prepare UPDATE statement: \(errorMessage)")
            }
            sqlite3_finalize(stmt)
        } else {
            let cols = fields.map { $0.0 }
            let placeholders = Array(repeating: "?", count: cols.count).joined(separator: ", ")
            let sql = "INSERT INTO contacts (\(cols.joined(separator: ", "))) VALUES (\(placeholders))"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                var idx: Int32 = 1
                for (_, value) in fields {
                    bind(value: value, to: stmt, index: idx)
                    idx += 1
                }
                let stepResult = sqlite3_step(stmt)
                if stepResult != SQLITE_DONE {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    print("❌ ContactsDAO.upsert: INSERT failed for phone \(phone): \(errorMessage)")
                }
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                print("❌ ContactsDAO.upsert: Failed to prepare INSERT statement: \(errorMessage)")
            }
            sqlite3_finalize(stmt)
        }
    }
    
    /// Legacy upsert method that opens its own connection (use upsertWithConnection for better performance)
    func upsert(phone: String,
                name: String?,
                firstName: String?,
                lastName: String?,
                email: String?,
                appleContactID: String?,
                profilePhotoData: Data?,
                nickname: String? = nil) {
        guard let db = try? CRMDatabase.shared.open() else {
            print("❌ ContactsDAO.upsert: Failed to open database")
            return
        }
        defer { sqlite3_close(db) }
        
        // Ensure contacts table exists before operations
        ensureSchema(db: db)
        
        // Call the new method with the connection
        upsertWithConnection(db: db,
                           phone: phone,
                           name: name,
                           firstName: firstName,
                           lastName: lastName,
                           email: email,
                           appleContactID: appleContactID,
                           profilePhotoData: profilePhotoData,
                           nickname: nickname)
    }
    
    private func existingColumns(db: OpaquePointer?, table: String) -> Set<String> {
        var stmt: OpaquePointer?
        var result: Set<String> = []
        let sql = "PRAGMA table_info(\(table));"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cstr = sqlite3_column_text(stmt, 1) {
                    result.insert(String(cString: cstr))
                }
            }
        }
        sqlite3_finalize(stmt)
        return result
    }

    func rowExistsPublic(db: OpaquePointer?, phone: String) -> Bool {
        rowExists(db: db, phone: phone)
    }

    private func rowExists(db: OpaquePointer?, phone: String) -> Bool {
        var stmt: OpaquePointer?
        let sql = "SELECT 1 FROM contacts WHERE phone = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(stmt, 1, phone, -1, nil)
        let step = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        return step == SQLITE_ROW
    }

    private func bind(value: Any?, to stmt: OpaquePointer?, index: Int32) {
        switch value {
        case let s as String:
            // Use withCString to ensure the C string pointer stays valid during the bind call
            s.withCString { cString in
                sqlite3_bind_text(stmt, index, cString, -1, SQLITE_TRANSIENT)
            }
        case let d as Data:
            d.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    sqlite3_bind_blob(stmt, index, base, Int32(d.count), SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, index)
                }
            }
        case .none:
            sqlite3_bind_null(stmt, index)
        default:
            sqlite3_bind_null(stmt, index)
        }
    }

    private func addColumnIfMissing(_ column: String, type: String, defaultClause: String?, existingColumns: Set<String>, db: OpaquePointer?) {
        guard !existingColumns.contains(column) else { return }
        var sql = "ALTER TABLE contacts ADD COLUMN \(column) \(type)"
        if let defaultClause = defaultClause {
            sql += " \(defaultClause)"
        }
        sql += ";"
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let e = err {
            print("❌ ContactsDAO: Failed to add column \(column): \(String(cString: e))")
            sqlite3_free(err)
        } else {
            print("✅ ContactsDAO: Added missing column \(column)")
        }
    }
}


