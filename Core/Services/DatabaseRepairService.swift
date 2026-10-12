//
//  DatabaseRepairService.swift
//  My CRM
//
//  Created for fixing remote database issues with missing tables and corruption
//

import Foundation
import SQLite3

/// Service for detecting and repairing database issues
@MainActor
class DatabaseRepairService {
    private let logger = LogManager.shared
    
    /// Check if database needs repair
    func needsRepair(database: OpaquePointer?) -> Bool {
        guard let db = database else { return false }
        
        // Check for missing tables
        let missingTables = checkMissingTables(db: db)
        
        if !missingTables.isEmpty {
            logger.warning("⚠️ Database needs repair - missing tables: \(missingTables.joined(separator: ", "))")
            return true
        }
        
        // Check integrity
        if !checkIntegrity(db: db) {
            logger.warning("⚠️ Database needs repair - integrity check failed")
            return true
        }
        
        return false
    }
    
    /// Repair database by creating missing tables
    func repairDatabase(database: OpaquePointer?, databasePath: String) async -> Bool {
        guard let db = database else {
            logger.error("❌ Cannot repair - database connection is nil")
            return false
        }
        
        logger.info("🔧 Starting database repair...")
        
        // Create backup before repair
        let backupCreated = await createBackup(databasePath: databasePath)
        if !backupCreated {
            logger.warning("⚠️ Could not create backup - proceeding with repair anyway")
        }
        
        // Get list of missing tables
        let missingTables = checkMissingTables(db: db)
        
        if missingTables.isEmpty {
            logger.info("✅ No missing tables - repair not needed")
            return true
        }
        
        // Create missing tables
        var allSuccess = true
        for tableName in missingTables {
            let created = await createMissingTable(db: db, tableName: tableName)
            if !created {
                allSuccess = false
                logger.error("❌ Failed to create table: \(tableName)")
            }
        }
        
        if allSuccess {
            logger.info("✅ Database repair completed successfully")
        } else {
            logger.error("❌ Database repair completed with errors")
        }
        
        return allSuccess
    }
    
    // MARK: - Private Helpers
    
    private func checkMissingTables(db: OpaquePointer) -> [String] {
        let requiredTables = ["contacts", "groups", "canvases", "batch_messages", "messages"]
        var missingTables: [String] = []
        
        for tableName in requiredTables {
            let checkQuery = "SELECT name FROM sqlite_master WHERE type='table' AND name='\(tableName)'"
            var statement: OpaquePointer?
            var exists = false
            
            if sqlite3_prepare_v2(db, checkQuery, -1, &statement, nil) == SQLITE_OK {
                if sqlite3_step(statement) == SQLITE_ROW {
                    exists = true
                }
            }
            sqlite3_finalize(statement)
            
            if !exists {
                missingTables.append(tableName)
            }
        }
        
        return missingTables
    }
    
    private func checkIntegrity(db: OpaquePointer) -> Bool {
        let integrityQuery = "PRAGMA integrity_check"
        var statement: OpaquePointer?
        var isHealthy = true
        
        if sqlite3_prepare_v2(db, integrityQuery, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let result = String(cString: sqlite3_column_text(statement, 0))
                if result != "ok" {
                    isHealthy = false
                    logger.error("❌ Integrity check result: \(result)")
                }
            }
        }
        sqlite3_finalize(statement)
        
        return isHealthy
    }
    
    private func createBackup(databasePath: String) async -> Bool {
        let fileManager = FileManager.default
        let backupPath = databasePath + ".backup_\(Date().timeIntervalSince1970)"
        
        do {
            try fileManager.copyItem(atPath: databasePath, toPath: backupPath)
            logger.info("✅ Created database backup at: \(backupPath)")
            return true
        } catch {
            logger.error("❌ Failed to create backup: \(error.localizedDescription)")
            return false
        }
    }
    
    private func createMissingTable(db: OpaquePointer, tableName: String) async -> Bool {
        logger.info("🔧 Creating missing table: \(tableName)")
        
        let createTableSQL = getCreateTableSQL(for: tableName)
        guard !createTableSQL.isEmpty else {
            logger.error("❌ No schema definition for table: \(tableName)")
            return false
        }
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, createTableSQL, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_DONE {
                logger.info("✅ Created table: \(tableName)")
                sqlite3_finalize(statement)
                return true
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                logger.error("❌ Failed to create table \(tableName): \(errorMessage)")
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            logger.error("❌ Failed to prepare CREATE TABLE for \(tableName): \(errorMessage)")
        }
        sqlite3_finalize(statement)
        
        return false
    }
    
    private func getCreateTableSQL(for tableName: String) -> String {
        switch tableName {
        case "groups":
            return """
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
                canvases TEXT DEFAULT '[]',
                size INTEGER DEFAULT 0,
                tags TEXT DEFAULT '[]',
                child_group_ids TEXT DEFAULT '[]',
                parent_group_ids TEXT DEFAULT '[]'
            );
            """
            
        case "contacts":
            return """
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
                groups TEXT DEFAULT '{}',
                tag_ids TEXT DEFAULT '[]',
                relationship_ids TEXT DEFAULT '[]'
            );
            """
            
        case "canvases":
            return """
            CREATE TABLE IF NOT EXISTS canvases (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                type TEXT NOT NULL,
                elements TEXT DEFAULT '[]',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """
            
        case "messages":
            return """
            CREATE TABLE IF NOT EXISTS messages (
                guid TEXT PRIMARY KEY,
                text TEXT,
                contact_phone TEXT,
                timestamp_ms INTEGER,
                is_from_me INTEGER,
                FOREIGN KEY (contact_phone) REFERENCES contacts(phone) ON DELETE SET NULL ON UPDATE CASCADE
            );
            """
            
        case "batch_messages":
            return """
            CREATE TABLE IF NOT EXISTS batch_messages (
                id TEXT PRIMARY KEY,
                message_template TEXT NOT NULL,
                field_metadata TEXT,
                recipients TEXT NOT NULL,
                scheduled_time TEXT,
                created_time TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',
                total_recipients INTEGER NOT NULL,
                sent_count INTEGER DEFAULT 0,
                failed_count INTEGER DEFAULT 0,
                failed_contacts TEXT DEFAULT '{}',
                completed_time TEXT,
                notify_when_sent INTEGER DEFAULT 0,
                error_log TEXT DEFAULT '[]',
                source_groups TEXT
            );
            """
            
        default:
            logger.warning("⚠️ No schema definition available for table: \(tableName)")
            return ""
        }
    }
}

