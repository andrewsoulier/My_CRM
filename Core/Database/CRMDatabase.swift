import Foundation
import SQLite3

enum CRMDatabaseError: Error {
    case openFailed(String)
}

/// DEPRECATED: This class is replaced by GRDBDatabaseManager
/// Will be removed in future version - kept for backwards compatibility only
/// Use GRDBDatabaseManager with GRDB instead
@available(*, deprecated, message: "Use GRDBDatabaseManager with GRDB instead")
final class CRMDatabase {
    static let shared = CRMDatabase()
    private init() {}
    
    /// Get the current database path from SettingsManager (always dynamic)
    private func getDatabasePath() -> String {
        let path = SettingsManager.shared.settings.database.path
        print("📁 CRMDatabase: Using database path from SettingsManager: \(path)")
        return path
    }

    func open() throws -> OpaquePointer? {
        let path = getDatabasePath()
        
        // Ensure database directory exists
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                print("✅ CRMDatabase: Created database directory at: \(directory.path)")
            } catch {
                print("❌ CRMDatabase: Failed to create database directory: \(error.localizedDescription)")
                throw CRMDatabaseError.openFailed("Failed to create database directory: \(error.localizedDescription)")
            }
        }
        
        var db: OpaquePointer?
        if sqlite3_open(path, &db) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw CRMDatabaseError.openFailed(msg)
        }
        
        // Set busy timeout to handle concurrent access (30 second retry window)
        sqlite3_busy_timeout(db, 30000)
        
        exec(db: db, sql: "PRAGMA foreign_keys = ON;")
        exec(db: db, sql: "PRAGMA journal_mode=WAL;")
        return db
    }

    func ensureSchema() {
        guard let db = try? open() else {
            print("❌ CRMDatabase.ensureSchema: Failed to open database")
            return
        }
        defer { sqlite3_close(db) }
        
        print("🔨 CRMDatabase.ensureSchema: Creating database schema...")
        
        createContactsTable(db: db)
        createGroupsTable(db: db)
        createInvitesTable(db: db)
        createTagsTable(db: db)
        createRelationshipsTable(db: db)
        createMessagesTable(db: db)
        createGridViewsTable(db: db)
        createGridCustomColumnsTable(db: db)
        createGridCustomCellValuesTable(db: db)
        createGridEditLogTable(db: db)
        
        print("✅ CRMDatabase.ensureSchema: Schema creation complete")
    }
    
    private func createContactsTable(db: OpaquePointer?) {
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
            print("❌ CRMDatabase: Failed to create contacts table: \(String(cString: e))")
            sqlite3_free(err)
        } else {
            print("✅ CRMDatabase: contacts table ready")
        }
    }
    
    private func createGroupsTable(db: OpaquePointer?) {
        let sql = """
        CREATE TABLE IF NOT EXISTS groups (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            color TEXT NOT NULL,
            created_at TEXT NOT NULL,
            parent_id TEXT,
            participants TEXT DEFAULT '[]',
            member_phones TEXT DEFAULT '[]',
            linked_group_ids TEXT,
            metadata TEXT,
            is_deck INTEGER DEFAULT 0,
            canvases TEXT,
            size INTEGER DEFAULT 0,
            tags TEXT DEFAULT '[]',
            child_group_ids TEXT DEFAULT '[]',
            parent_group_ids TEXT DEFAULT '[]'
        );
        """
        
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let e = err {
            print("❌ CRMDatabase: Failed to create groups table: \(String(cString: e))")
            sqlite3_free(err)
        } else {
            print("✅ CRMDatabase: groups table ready")
        }
    }
    
    private func createInvitesTable(db: OpaquePointer?) {
        let sql = """
        CREATE TABLE IF NOT EXISTS invites (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT,
            creation_date TEXT NOT NULL,
            last_modified_date TEXT NOT NULL,
            date_completed TEXT,
            completed INTEGER DEFAULT 0,
            completion_status TEXT DEFAULT 'pending',
            sent_received TEXT NOT NULL,
            to_phone TEXT,
            from_phone TEXT,
            priority INTEGER DEFAULT 1,
            due_date TEXT,
            parent_tasks TEXT DEFAULT '[]',
            child_tasks TEXT DEFAULT '[]',
            tags TEXT DEFAULT '{}',
            groups TEXT DEFAULT '[]',
            task_group TEXT DEFAULT '{}',
            ai_processed INTEGER DEFAULT 0,
            ai_suggestions TEXT DEFAULT '{}',
            ai_confidence REAL DEFAULT 0.0,
            reminder_date TEXT,
            message_origin_guid TEXT,
            is_recurring INTEGER DEFAULT 0,
            recurrence_type TEXT DEFAULT 'none',
            next_task_id TEXT,
            previous_task_id TEXT,
            is_next_task INTEGER DEFAULT 0,
            date_of_last_task TEXT,
            created_by TEXT,
            assigned_to TEXT,
            category TEXT,
            location TEXT,
            estimated_duration INTEGER,
            attachments TEXT DEFAULT '[]',
            external_id TEXT,
            last_ai_analysis TEXT,
            FOREIGN KEY (to_phone) REFERENCES contacts(phone) ON DELETE SET NULL ON UPDATE CASCADE,
            FOREIGN KEY (from_phone) REFERENCES contacts(phone) ON DELETE SET NULL ON UPDATE CASCADE,
            FOREIGN KEY (message_origin_guid) REFERENCES messages(guid) ON DELETE SET NULL ON UPDATE CASCADE,
            FOREIGN KEY (next_task_id) REFERENCES invites(id) ON DELETE SET NULL ON UPDATE CASCADE,
            FOREIGN KEY (previous_task_id) REFERENCES invites(id) ON DELETE SET NULL ON UPDATE CASCADE
        );
        """
        
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let e = err {
            print("❌ CRMDatabase: Failed to create invites table: \(String(cString: e))")
            sqlite3_free(err)
        } else {
            print("✅ CRMDatabase: invites table ready")
        }
    }
    
    private func createTagsTable(db: OpaquePointer?) {
        let sql = """
        CREATE TABLE IF NOT EXISTS tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            color TEXT,
            description TEXT,
            linked_contacts TEXT DEFAULT '[]',
            linked_groups TEXT DEFAULT '[]'
        );
        """
        
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let e = err {
            print("❌ CRMDatabase: Failed to create tags table: \(String(cString: e))")
            sqlite3_free(err)
        } else {
            print("✅ CRMDatabase: tags table ready")
        }
    }
    
    private func createRelationshipsTable(db: OpaquePointer?) {
        let sql = """
        CREATE TABLE IF NOT EXISTS relationships (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            color TEXT,
            description TEXT,
            linked_contacts TEXT DEFAULT '[]',
            linked_groups TEXT DEFAULT '[]'
        );
        """
        
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let e = err {
            print("❌ CRMDatabase: Failed to create relationships table: \(String(cString: e))")
            sqlite3_free(err)
        } else {
            print("✅ CRMDatabase: relationships table ready")
        }
    }
    
    private func createGridViewsTable(db: OpaquePointer?) {
        let sql = """
        CREATE TABLE IF NOT EXISTS grid_views (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            user_id TEXT NOT NULL DEFAULT 'default',
            visible_columns TEXT DEFAULT '[]',
            frozen_columns TEXT DEFAULT '[]',
            column_order TEXT DEFAULT '[]',
            sort_model TEXT DEFAULT '[]',
            filter_model TEXT DEFAULT '{}',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """
        
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let e = err {
            print("❌ CRMDatabase: Failed to create grid_views table: \(String(cString: e))")
            sqlite3_free(err)
        } else {
            print("✅ CRMDatabase: grid_views table ready")
        }
    }
    
    private func createGridCustomColumnsTable(db: OpaquePointer?) {
        let sql = """
        CREATE TABLE IF NOT EXISTS grid_custom_columns (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT UNIQUE NOT NULL,
            view_uuid TEXT,
            entity_type TEXT NOT NULL,
            user_id TEXT NOT NULL DEFAULT 'default',
            name TEXT NOT NULL,
            data_type TEXT NOT NULL,
            is_visible INTEGER DEFAULT 1,
            order_index INTEGER,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """
        
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let e = err {
            print("❌ CRMDatabase: Failed to create grid_custom_columns table: \(String(cString: e))")
            sqlite3_free(err)
        } else {
            print("✅ CRMDatabase: grid_custom_columns table ready")
        }
    }
    
    private func createGridCustomCellValuesTable(db: OpaquePointer?) {
        let sql = """
        CREATE TABLE IF NOT EXISTS grid_custom_cell_values (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            column_uuid TEXT NOT NULL,
            record_id TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            value TEXT,
            updated_at TEXT NOT NULL,
            UNIQUE(column_uuid, record_id) ON CONFLICT REPLACE,
            FOREIGN KEY(column_uuid) REFERENCES grid_custom_columns(uuid) ON DELETE CASCADE ON UPDATE CASCADE
        );
        """
        
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let e = err {
            print("❌ CRMDatabase: Failed to create grid_custom_cell_values table: \(String(cString: e))")
            sqlite3_free(err)
        } else {
            print("✅ CRMDatabase: grid_custom_cell_values table ready")
        }
    }
    
    private func createGridEditLogTable(db: OpaquePointer?) {
        let sql = """
        CREATE TABLE IF NOT EXISTS grid_edit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            record_id TEXT NOT NULL,
            column_id TEXT NOT NULL,
            previous_value TEXT,
            next_value TEXT,
            created_at TEXT NOT NULL,
            direction TEXT NOT NULL
        );
        """
        
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let e = err {
            print("❌ CRMDatabase: Failed to create grid_edit_log table: \(String(cString: e))")
            sqlite3_free(err)
        } else {
            print("✅ CRMDatabase: grid_edit_log table ready")
        }
    }
    
    private func createMessagesTable(db: OpaquePointer?) {
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
            print("❌ CRMDatabase: Failed to create messages table: \(String(cString: e))")
            sqlite3_free(err)
        } else {
            print("✅ CRMDatabase: messages table ready")
        }
    }

    private func exec(db: OpaquePointer?, sql: String) {
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let e = err {
            print("CRMDatabase exec error: \(String(cString: e))")
            sqlite3_free(err)
        }
    }
    
    // MARK: - Cleanup
    
    /// Close all database connections (called during app termination)
    func closeAllConnections() {
        print("🔌 CRMDatabase: Closing all connections...")
        // Note: CRMDatabase doesn't maintain persistent connections
        // Each method opens and closes its own connection
        // This method is here for consistency and future-proofing
        print("✅ CRMDatabase: All connections closed")
    }
}




