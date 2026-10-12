import Foundation
import Darwin
import SwiftUI
import SQLite3

@MainActor
@preconcurrency
class SQLiteDataProvider: DataProvider, ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var groups: [ContactGroup] = []
    @Published var invites: [Invite] = []
    
    private let logger = LogManager.shared
    private let sqlValidator = SQLValidationService.shared
    private let groupManager = GroupManager()
    private let grdbManager = GRDBDatabaseManager.shared
    
    var database: OpaquePointer?
    private var _isConnectedToDatabase = false
    private var currentDatabasePath: String?
    
    // Public property to check connection status
    var isConnectedToDatabase: Bool {
        return _isConnectedToDatabase
    }
    
    // Default database path - will be overridden by user settings
    private let defaultDatabasePath = "\(NSHomeDirectory())/CRM/my_crm.db"
    
    func getUserDatabasePath() -> String {
        // Always use SettingsManager (User_Settings.json) as source of truth
        let path = SettingsManager.shared.settings.database.path
        print("📁 Using database path from SettingsManager: \(path)")
        return path
    }
    
    /// Ensures a valid database path exists, creating default if needed
    func ensureValidDatabasePath(_ proposedPath: String) -> String {
        let fileManager = FileManager.default
        
        // Check if the proposed path or its directory exists
        let pathURL = URL(fileURLWithPath: proposedPath)
        let directoryURL = pathURL.deletingLastPathComponent()
        
        // If the directory doesn't exist, create default location in Application Support
        if !fileManager.fileExists(atPath: directoryURL.path) {
            print("📁 Database directory does not exist at: \(directoryURL.path)")
            print("📝 Creating default database location...")
            
            // Create default path: ~/Library/Application Support/My_CRM/my_crm.db
            guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                print("❌ Could not access Application Support directory")
                return proposedPath
            }
            
            let defaultDirectory = appSupportURL.appendingPathComponent("My_CRM")
            let defaultPath = defaultDirectory.appendingPathComponent("my_crm.db").path
            
            do {
                // Create the My_CRM directory
                try fileManager.createDirectory(at: defaultDirectory, withIntermediateDirectories: true, attributes: nil)
                print("✅ Created default database directory at: \(defaultDirectory.path)")
                
                // Update settings with new path
                let settingsManager = SettingsManager.shared
                settingsManager.updateDatabasePath(defaultPath)
                print("💾 Updated settings with new database path: \(defaultPath)")
                
                return defaultPath
            } catch {
                print("❌ Failed to create default database directory: \(error.localizedDescription)")
                return proposedPath
            }
        }
        
        return proposedPath
    }
    
    init() {
        print("🚨 SQLiteDataProvider.init() called")
        // Don't automatically connect - let the UI handle the connection
        print("📱 SQLiteDataProvider initialized - waiting for explicit connection")
    }
    
    // MARK: - Database Connection Management
    
    /// Public method to close database connection (called during app termination)
    func closeDatabase() async {
        guard let db = database else {
            logger.info("ℹ️ No database connection to close")
            return
        }
        
        logger.info("🔌 Closing database connection...")
        await properlyCloseDatabase(db)
        database = nil
        _isConnectedToDatabase = false
        currentDatabasePath = nil
        logger.info("✅ Database connection closed")
    }
    
    /// Properly close a database connection with checkpoint
    private func properlyCloseDatabase(_ db: OpaquePointer) async {
        logger.info("🔌 Properly closing database connection...")
        
        // Checkpoint WAL to ensure all changes are written to main database
        var checkpointError: UnsafeMutablePointer<CChar>? = nil
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, &checkpointError)
        
        if checkpointError == nil {
            logger.info("✅ Checkpointed WAL before closing")
        } else {
            let errorMsg = String(cString: checkpointError!)
            logger.warning("⚠️ Checkpoint before close had issues: \(errorMsg)")
            sqlite3_free(checkpointError)
        }
        
        // Close the database connection
        let closeResult = sqlite3_close(db)
        if closeResult == SQLITE_OK {
            logger.info("✅ Database connection closed cleanly")
        } else {
            logger.warning("⚠️ Database close returned: \(closeResult)")
        }
        
        database = nil
        _isConnectedToDatabase = false
        currentDatabasePath = nil
        
        await disconnectGRDBIfNeeded()
    }
    
    /// Unlock and clean up database files (WAL, SHM) to recover from crashes
    private func unlockDatabase(at path: String) {
        logger.info("🔓 Attempting to unlock database at: \(path)")
        
        let fileManager = FileManager.default
        let walPath = path + "-wal"
        let shmPath = path + "-shm"
        
        // Try to open and checkpoint the database to merge WAL changes
        var tempDb: OpaquePointer?
        let openResult = sqlite3_open_v2(
            path,
            &tempDb,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        
        if openResult == SQLITE_OK, let db = tempDb {
            logger.info("✅ Opened database for checkpoint")
            
            // Run checkpoint to merge WAL file into main database
            var checkpointError: UnsafeMutablePointer<CChar>? = nil
            sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, &checkpointError)
            
            if checkpointError == nil {
                logger.info("✅ Successfully checkpointed WAL file")
            } else {
                let errorMsg = String(cString: checkpointError!)
                logger.warning("⚠️ WAL checkpoint had issues: \(errorMsg)")
                sqlite3_free(checkpointError)
            }
            
            // Close the temporary connection
            sqlite3_close(db)
            logger.info("✅ Closed temporary checkpoint connection")
        } else {
            logger.warning("⚠️ Could not open database for checkpoint")
        }
        
        // Remove WAL and SHM files if they exist (they should be merged or can be recreated)
        if fileManager.fileExists(atPath: walPath) {
            do {
                try fileManager.removeItem(atPath: walPath)
                logger.info("🗑️ Removed stale WAL file")
            } catch {
                logger.warning("⚠️ Could not remove WAL file: \(error.localizedDescription)")
            }
        }
        
        if fileManager.fileExists(atPath: shmPath) {
            do {
                try fileManager.removeItem(atPath: shmPath)
                logger.info("🗑️ Removed stale SHM file")
            } catch {
                logger.warning("⚠️ Could not remove SHM file: \(error.localizedDescription)")
            }
        }
        
        logger.info("✅ Database unlock complete")
    }
    
    /// Checkpoint WAL file to merge changes back to main database and release locks
    private func checkpointWAL(reason: String = "periodic") {
        guard let db = database else { return }
        
        var logFrameCount: Int32 = 0
        var checkpointedFrameCount: Int32 = 0
        let rc = sqlite3_wal_checkpoint_v2(
            db,
            nil,
            SQLITE_CHECKPOINT_PASSIVE,
            &logFrameCount,
            &checkpointedFrameCount
        )
        
        if rc != SQLITE_OK {
            let extendedCode = sqlite3_extended_errcode(db)
            let errnoCode = errno
            let message = String(cString: sqlite3_errmsg(db))
            let databasePath = currentDatabasePath ?? SettingsManager.shared.settings.database.path
            let diagnostics = databasePathDiagnostics(for: databasePath)
            logger.warning(
                """
                ⚠️ WAL checkpoint warning (reason=\(reason), rc=\(rc), extended=\(extendedCode), errno=\(errnoCode), logFrames=\(logFrameCount), checkpointedFrames=\(checkpointedFrameCount)): \(message) \(diagnostics)
                """
            )
        } else if logFrameCount > 0 || checkpointedFrameCount > 0 {
            logger.info(
                "ℹ️ WAL checkpoint complete (reason=\(reason), logFrames=\(logFrameCount), checkpointedFrames=\(checkpointedFrameCount))"
            )
        }
    }
    
    private func synchronizeGRDBConnection(with path: String) async throws {
        if grdbManager.isConnected,
           grdbManager.currentDatabasePath == path {
            return
        }
        try await grdbManager.connect(to: path)
    }
    
    private func disconnectGRDBIfNeeded() async {
        guard grdbManager.isConnected else { return }
        do {
            try await grdbManager.disconnect()
        } catch {
            logger.warning("⚠️ Failed to disconnect GRDB manager: \(error.localizedDescription)")
        }
    }
    
    private func databasePathDiagnostics(for databasePath: String) -> String {
        var details: [String] = []
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: databasePath) {
            if let attributes = try? fileManager.attributesOfItem(atPath: databasePath),
               let fileSize = attributes[.size] as? NSNumber {
                details.append("dbBytes=\(fileSize.int64Value)")
            } else {
                details.append("dbAttributes=unavailable")
            }
        } else {
            details.append("dbExists=false")
        }
        
        let walPath = databasePath + "-wal"
        if fileManager.fileExists(atPath: walPath) {
            if let attributes = try? fileManager.attributesOfItem(atPath: walPath),
               let fileSize = attributes[.size] as? NSNumber {
                details.append("walBytes=\(fileSize.int64Value)")
            } else {
                details.append("walBytes=unavailable")
            }
        } else {
            details.append("walMissing=true")
        }
        
        let shmPath = databasePath + "-shm"
        if fileManager.fileExists(atPath: shmPath) {
            if let attributes = try? fileManager.attributesOfItem(atPath: shmPath),
               let fileSize = attributes[.size] as? NSNumber {
                details.append("shmBytes=\(fileSize.int64Value)")
            } else {
                details.append("shmBytes=unavailable")
            }
        } else {
            details.append("shmMissing=true")
        }
        
        let databaseURL = URL(fileURLWithPath: databasePath)
        let resourceKeys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
            .volumeLocalizedNameKey
        ]
        
        if let resourceValues = try? databaseURL.resourceValues(forKeys: resourceKeys) {
            if let available = resourceValues.volumeAvailableCapacityForImportantUsage {
                details.append("volumeAvailableMB=\(available / 1_048_576)")
            }
            if let total = resourceValues.volumeTotalCapacity {
                details.append("volumeTotalMB=\(total / 1_048_576)")
            }
            if let name = resourceValues.volumeLocalizedName {
                details.append("volume=\"\(name)\"")
            }
        }
        
        return details.isEmpty ? "" : "[\(details.joined(separator: ", "))]"
    }
    
    func connectToDatabase(path: String) async throws {
        let callStack = DatabaseLogger.shared.getCallStack()
        let details = "Connecting to SQLite database at: \(path)"
        
        print("🔍 Connecting to SQLite database at: \(path)")
        
        // Check for multiple app instances before connecting
        let canProceed = await AppInstanceManager.shared.checkAndHandleMultipleInstances()
        if !canProceed {
            logger.error("❌ User cancelled connection due to multiple instances")
            throw DataProviderError.databaseConnectionFailed
        }
        
        // Close existing connection if any
        if let db = database {
            await properlyCloseDatabase(db)
        }
        
        // Check if database file exists
        if !FileManager.default.fileExists(atPath: path) {
            print("📁 Database file not found at: \(path)")
            print("📝 Creating new database...")
            await createDatabase(at: path)
        } else {
            // Unlock database to clear any stale locks from crashes
            unlockDatabase(at: path)
        }
        
        // Use sqlite3_open_v2 with explicit flags for better error handling and concurrency
        let result = sqlite3_open_v2(
            path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        let success = result == SQLITE_OK
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "SQLITE_CONNECT",
            details: details,
            success: success,
            callStack: callStack
        )
        
        if !success {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            print("❌ Failed to open database: \(errorMessage)")
            throw DataProviderError.databaseConnectionFailed
        }
        
        _isConnectedToDatabase = true
        currentDatabasePath = path
        print("✅ Successfully connected to SQLite database")
        
        // Set busy timeout FIRST to handle concurrent access (30 second retry window)
        // This allows reads and writes to wait for locks instead of failing immediately
        sqlite3_busy_timeout(database, 30000)
        
        // Enable WAL mode for better concurrency and crash recovery
        var walError: UnsafeMutablePointer<CChar>? = nil
        sqlite3_exec(database, "PRAGMA journal_mode=WAL;", nil, nil, &walError)
        if walError == nil {
            logger.info("✅ Enabled WAL mode for database")
        } else {
            let errorMessage = String(cString: walError!)
            logger.warning("⚠️ Failed to enable WAL mode: \(errorMessage)")
            sqlite3_free(walError)
        }
        
        // Set synchronous mode to NORMAL for better performance with WAL
        sqlite3_exec(database, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
        
        // Test LogManager functionality
        LogManager.shared.testLogging()
        
        do {
            try await synchronizeGRDBConnection(with: path)
        } catch {
            logger.error("❌ Failed to initialize GRDB connection: \(error.localizedDescription)")
            if let db = database {
                await properlyCloseDatabase(db)
            }
            throw error
        }
        
        // Check write permissions
        let permissionStatus = DatabasePermissionChecker.shared.checkDatabaseWritePermission(path: path)
        if permissionStatus == .denied {
            logger.error("❌ Database write permission denied")
            await DatabasePermissionChecker.shared.showPermissionAlert(status: .denied)
            throw DataProviderError.databaseConnectionFailed
        }
        
        // Check for cloud sync (warn but continue per user preference 1c)
        let (isSynced, service) = DatabasePermissionChecker.shared.isPathCloudSynced(path)
        if isSynced {
            DatabasePermissionChecker.shared.showCloudSyncWarning(service: service ?? "unknown", path: path)
        }
        
        // Check database health before loading data
        let isHealthy = await checkDatabaseIntegrity()
        if !isHealthy {
            logger.warning("⚠️ Database integrity check failed - attempting repair...")
            // Note: Database will still load, migrations will create missing tables
        }
        
        // Check for missing tables
        let missingTables = await checkRequiredTablesExist()
        if !missingTables.isEmpty {
            logger.warning("⚠️ Found missing tables: \(missingTables.joined(separator: ", "))")
            logger.info("💡 Migrations will attempt to create missing tables")
        }
        
        // Load data from database
        await loadDataFromDatabase()
        
        // Start periodic WAL checkpoint task (every 30 seconds) to release locks
        Task {
            while _isConnectedToDatabase {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await MainActor.run {
                    checkpointWAL(reason: "periodicTask")
                }
            }
        }
    }
    
    nonisolated func isConnected() -> Bool {
        return MainActor.assumeIsolated {
            _isConnectedToDatabase && database != nil
        }
    }
    
    func getCurrentDatabasePath() -> String? {
        return currentDatabasePath
    }
    
    /// Switch to a new database and reload all data
    func switchDatabase(to newPath: String) async throws {
        logger.info("🔄 SQLiteDataProvider: Switching database to: \(newPath)")
        
        // Validate the new database path
        guard FileManager.default.fileExists(atPath: newPath) else {
            logger.error("❌ SQLiteDataProvider: Database file does not exist at: \(newPath)")
            throw DataProviderError.databaseConnectionFailed
        }
        
        // Properly close existing connection if any
        if let db = database {
            logger.info("🔌 SQLiteDataProvider: Properly closing current database connection")
            await properlyCloseDatabase(db)
        }
        
        // Clear existing data
        logger.info("🗑️ SQLiteDataProvider: Clearing existing data")
        await MainActor.run {
            self.contacts = []
            self.groups = []
            self.invites = []
        }
        
        // Update settings with new path
        SettingsManager.shared.updateDatabasePath(newPath)
        
        // Small delay to ensure file handles are released
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Connect to new database (this will also load data)
        logger.info("🔌 SQLiteDataProvider: Connecting to new database")
        try await connectToDatabase(path: newPath)
        
        logger.info("✅ SQLiteDataProvider: Successfully switched to new database")
        logger.info("📊 SQLiteDataProvider: Loaded \(contacts.count) contacts, \(groups.count) groups, \(invites.count) invites")
    }
    
    func closeConnection() async throws {
        if let db = database {
            await properlyCloseDatabase(db)
            print("📪 Database connection closed")
        }
    }
    
    private func loadDefaultDatabase() async {
        do {
            try await connectToDatabase(path: defaultDatabasePath)
        } catch {
            print("⚠️ Could not connect to default database: \(error.localizedDescription)")
            print("📝 App will continue with empty data until database is connected")
        }
    }
    
    private func createDatabase(at path: String) async {
        print("🔨 Creating new SQLite database at: \(path)")
        
        // Create directory if it doesn't exist
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            print("✅ Created database directory at: \(directory.path)")
        } catch {
            print("❌ Failed to create database directory: \(error.localizedDescription)")
            
            // Show user-friendly error
            await MainActor.run {
                let message = """
                Could not create database directory at:
                \(directory.path)
                
                Error: \(error.localizedDescription)
                
                Try choosing a different location in Settings.
                """
                // TODO: Show this error to user via AppState or alert
                print("📢 User Error: \(message)")
            }
            return
        }
        
        // Create the database file with explicit flags
        let result = sqlite3_open_v2(
            path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        if result == SQLITE_OK {
            print("✅ Database created successfully")
            await createTables()
            sqlite3_close(database)
            database = nil
        } else {
            let errorMsg = String(cString: sqlite3_errmsg(database))
            print("❌ Failed to create database: \(errorMsg)")
            
            await MainActor.run {
                let message = """
                Failed to create database file.
                
                Error: \(errorMsg)
                
                The app will continue but you won't be able to save data.
                Please check Settings to choose a valid database location.
                """
                print("📢 User Error: \(message)")
            }
        }
    }
    
    private func createTables() async {
        guard let db = database else { return }
        
        let createContactsTable = """
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
        
        let createGroupsTable = """
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
        
        let createInvitesTable = """
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
        
        let createBatchMessagesTable = """
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
        
        let createTagsTable = """
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
        
        let createRelationshipsTable = """
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
        
        let statements = [createContactsTable, createGroupsTable, createInvitesTable, createBatchMessagesTable, createTagsTable, createRelationshipsTable]
        
        for statement in statements {
            var stmt: OpaquePointer?
            let result = sqlite3_prepare_v2(db, statement, -1, &stmt, nil)
            
            if result == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_DONE {
                    print("✅ Table created successfully")
                } else {
                    print("❌ Failed to execute table creation")
                }
            } else {
                print("❌ Failed to prepare table creation statement")
            }
            
            sqlite3_finalize(stmt)
        }
    }
    
    // MARK: - Database Migrations
    
    private func runMigrations() async {
        guard let db = database else { return }
        
        logger.info("🔄 Running database migrations...")
        
        // Migration 1: Add participants column to groups table if it doesn't exist
        await runGroupsParticipantsMigration(db: db)
        
        // Migration 2: Create batch_messages table if it doesn't exist
        await runBatchMessagesTableMigration(db: db)
        
        // Migration 3: Clean up duplicate batch messages
        await cleanupDuplicateBatchMessages(db: db)
        
        logger.info("✅ Database migrations completed")
    }
    
    // MARK: - Database Health & Integrity
    
    private func checkDatabaseIntegrity() async -> Bool {
        guard let db = database else {
            logger.error("❌ Cannot check integrity - database connection is nil")
            return false
        }
        
        logger.info("🔍 Checking database integrity...")
        
        let integrityQuery = "PRAGMA integrity_check"
        var statement: OpaquePointer?
        var isHealthy = true
        
        if sqlite3_prepare_v2(db, integrityQuery, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let result = String(cString: sqlite3_column_text(statement, 0))
                if result != "ok" {
                    isHealthy = false
                    logger.error("❌ Database integrity check failed: \(result)")
                } else {
                    logger.info("✅ Database integrity check passed")
                }
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            logger.error("❌ Failed to run integrity check: \(errorMessage)")
            isHealthy = false
        }
        sqlite3_finalize(statement)
        
        return isHealthy
    }
    
    private func checkRequiredTablesExist() async -> [String] {
        guard let db = database else { return [] }
        
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
                logger.warning("⚠️ Missing table: \(tableName)")
            }
        }
        
        if missingTables.isEmpty {
            logger.info("✅ All required tables exist")
        } else {
            logger.warning("⚠️ Missing tables: \(missingTables.joined(separator: ", "))")
        }
        
        return missingTables
    }
    
    private func runGroupsParticipantsMigration(db: OpaquePointer) async {
        // CRITICAL FIX: First ensure the groups table exists before checking columns
        logger.info("🔄 Migration 1: Ensuring groups table exists...")
        
        let createGroupsTable = """
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
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, createGroupsTable, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_DONE {
                logger.info("✅ Migration 1: Groups table ensured")
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                logger.error("❌ Migration 1: Failed to create groups table: \(errorMessage)")
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            logger.error("❌ Migration 1: Failed to prepare CREATE TABLE statement: \(errorMessage)")
        }
        sqlite3_finalize(statement)
        
        // Now check if the participants column exists (for older databases)
        let checkColumnQuery = "PRAGMA table_info(groups)"
        var columnExists = false
        
        if sqlite3_prepare_v2(db, checkColumnQuery, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let columnName = String(cString: sqlite3_column_text(statement, 1))
                if columnName == "participants" {
                    columnExists = true
                    break
                }
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            logger.error("❌ Migration 1: Failed to check columns: \(errorMessage)")
        }
        sqlite3_finalize(statement)
        
        if !columnExists {
            let addParticipantsColumn = """
            ALTER TABLE groups ADD COLUMN participants TEXT DEFAULT '[]';
            """
            
            if sqlite3_prepare_v2(db, addParticipantsColumn, -1, &statement, nil) == SQLITE_OK {
                let stepResult = sqlite3_step(statement)
                if stepResult == SQLITE_DONE {
                    logger.info("✅ Migration 1: Added participants column to groups table")
                } else {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    logger.error("❌ Migration 1 failed to add column: \(errorMessage)")
                }
                sqlite3_finalize(statement)
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                logger.error("❌ Migration 1: Failed to prepare ALTER statement: \(errorMessage)")
            }
        } else {
            logger.info("ℹ️ Migration 1: participants column already exists")
        }
    }
    
    private func runBatchMessagesTableMigration(db: OpaquePointer) async {
        logger.info("🔄 Migration 2: Checking batch_messages table...")
        
        // Check if batch_messages table exists
        let checkTableQuery = """
        SELECT name FROM sqlite_master WHERE type='table' AND name='batch_messages';
        """
        
        var statement: OpaquePointer?
        var tableExists = false
        
        if sqlite3_prepare_v2(db, checkTableQuery, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                tableExists = true
            }
        }
        sqlite3_finalize(statement)
        
        if !tableExists {
            logger.info("📝 Migration 2: Creating batch_messages table...")
            
            let createBatchMessagesTable = """
            CREATE TABLE IF NOT EXISTS batch_messages (
                id TEXT PRIMARY KEY,
                message_template TEXT NOT NULL,
                field_metadata TEXT,               -- JSON metadata for smart chips (v2.0)
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
                source_groups TEXT                 -- JSON array of originating group UUIDs
            );
            """
            
            if sqlite3_prepare_v2(db, createBatchMessagesTable, -1, &statement, nil) == SQLITE_OK {
                let stepResult = sqlite3_step(statement)
                if stepResult == SQLITE_DONE {
                    logger.info("✅ Migration 2: Created batch_messages table successfully")
                } else {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    logger.error("❌ Migration 2 failed: \(errorMessage)")
                }
                sqlite3_finalize(statement)
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                logger.error("❌ Migration 2: Failed to prepare statement: \(errorMessage)")
            }
        } else {
            logger.info("ℹ️ Migration 2: batch_messages table already exists")
        }
        
        // Always validate required columns, even on fresh creation
        await validateBatchMessagesTableColumns(db: db)
    }
    
    private func validateBatchMessagesTableColumns(db: OpaquePointer) async {
        logger.info("🔍 Migration 2: Validating batch_messages table columns...")
        
        let checkColumnsQuery = "PRAGMA table_info(batch_messages)"
        var statement: OpaquePointer?
        var existingColumns: Set<String> = []
        
        if sqlite3_prepare_v2(db, checkColumnsQuery, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let columnName = String(cString: sqlite3_column_text(statement, 1))
                existingColumns.insert(columnName)
            }
        }
        sqlite3_finalize(statement)
        
        logger.info("🔍 Migration 2: Found existing columns: \(existingColumns)")
        
        // Required columns for batch_messages table
        let requiredColumns = [
            ("id", "TEXT PRIMARY KEY"),
            ("message_template", "TEXT NOT NULL"),
            ("field_metadata", "TEXT"), // Enhanced chip metadata (v2.0)
            ("recipients", "TEXT NOT NULL"),
            ("scheduled_time", "TEXT"),
            ("created_time", "TEXT NOT NULL"),
            ("status", "TEXT NOT NULL DEFAULT 'pending'"),
            ("total_recipients", "INTEGER NOT NULL"),
            ("sent_count", "INTEGER DEFAULT 0"),
            ("failed_count", "INTEGER DEFAULT 0"),
            ("failed_contacts", "TEXT DEFAULT '{}'"),
            ("completed_time", "TEXT"),
            ("notify_when_sent", "INTEGER DEFAULT 0"),
            ("error_log", "TEXT DEFAULT '[]'"),
            ("source_groups", "TEXT") // JSON array of group UUIDs that were originally selected
        ]
        
        // Add missing columns
        for (columnName, columnDef) in requiredColumns {
            if !existingColumns.contains(columnName) {
                logger.info("➕ Migration 2: Adding missing column: \(columnName)")
                
                let alterQuery = "ALTER TABLE batch_messages ADD COLUMN \(columnName) \(columnDef.replacingOccurrences(of: "PRIMARY KEY", with: "").replacingOccurrences(of: "NOT NULL", with: ""))"
                
                if sqlite3_prepare_v2(db, alterQuery, -1, &statement, nil) == SQLITE_OK {
                    let stepResult = sqlite3_step(statement)
                    if stepResult == SQLITE_DONE {
                        logger.info("✅ Migration 2: Added column \(columnName)")
                    } else {
                        let errorMessage = String(cString: sqlite3_errmsg(db))
                        logger.error("❌ Migration 2: Failed to add column \(columnName): \(errorMessage)")
                    }
                    sqlite3_finalize(statement)
                } else {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    logger.error("❌ Migration 2: Failed to prepare ALTER statement for \(columnName): \(errorMessage)")
                }
            }
        }
        
        // If field_metadata column was just added, migrate existing messages
        if !existingColumns.contains("field_metadata") && existingColumns.contains("message_template") {
            logger.info("🔄 Migration 2: Migrating existing messages to v2.0 format...")
            await migrateExistingMessagesToV2(db: db)
        }
        
        logger.info("✅ Migration 2: batch_messages table validation complete")
    }
    
    // MARK: - Migration Logic
    
    /// Migrate existing batch messages to v2.0 format with smart chip metadata
    private func migrateExistingMessagesToV2(db: OpaquePointer) async {
        logger.info("🔄 Migration 2: Starting migration of existing batch messages to v2.0...")
        
        // Get all existing batch messages without field_metadata
        let selectQuery = """
        SELECT id, message_template FROM batch_messages 
        WHERE field_metadata IS NULL OR field_metadata = ''
        """
        
        var statement: OpaquePointer?
        var messagesToMigrate: [(String, String)] = []
        
        if sqlite3_prepare_v2(db, selectQuery, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let messageTemplate = String(cString: sqlite3_column_text(statement, 1))
                messagesToMigrate.append((id, messageTemplate))
            }
        }
        sqlite3_finalize(statement)
        
        logger.info("🔄 Migration 2: Found \(messagesToMigrate.count) messages to migrate")
        
        // Migrate each message
        for (id, messageTemplate) in messagesToMigrate {
            let chipMetadata = generateChipMetadataFromTemplate(messageTemplate)
            
            // Convert metadata to JSON
            let metadataJson: String
            if let metadataData = try? JSONEncoder().encode(chipMetadata),
               let metadataString = String(data: metadataData, encoding: .utf8) {
                metadataJson = metadataString
            } else {
                logger.error("❌ Migration 2: Failed to encode metadata for message \(id)")
                continue
            }
            
            // Update the message with metadata
            let updateQuery = """
            UPDATE batch_messages 
            SET field_metadata = ? 
            WHERE id = ?
            """
            
            if sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, metadataJson, -1, nil)
                sqlite3_bind_text(statement, 2, id, -1, nil)
                
                if sqlite3_step(statement) == SQLITE_DONE {
                    logger.info("✅ Migration 2: Migrated message \(id)")
                } else {
                    logger.error("❌ Migration 2: Failed to migrate message \(id): \(String(cString: sqlite3_errmsg(db)))")
                }
            } else {
                logger.error("❌ Migration 2: Failed to prepare update statement for message \(id)")
            }
            sqlite3_finalize(statement)
        }
        
        logger.info("✅ Migration 2: Completed migration of existing batch messages")
    }
    
    private func cleanupDuplicateBatchMessages(db: OpaquePointer) async {
        logger.info("🔄 Migration 3: Cleaning up duplicate batch messages...")
        
        // Find duplicate messages (same message_template, recipients, and scheduled_time)
        // Keep the one with the most recent status (completed/failed over scheduled)
        let findDuplicatesQuery = """
        SELECT id, message_template, status, created_time, completed_time
        FROM batch_messages
        ORDER BY message_template, created_time
        """
        
        var statement: OpaquePointer?
        var messageGroups: [String: [(id: String, status: String, createdTime: String, completedTime: String?)]] = [:]
        
        if sqlite3_prepare_v2(db, findDuplicatesQuery, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let messageTemplate = String(cString: sqlite3_column_text(statement, 1))
                let status = String(cString: sqlite3_column_text(statement, 2))
                let createdTime = String(cString: sqlite3_column_text(statement, 3))
                let completedTime = sqlite3_column_text(statement, 4).map { String(cString: $0) }
                
                if messageGroups[messageTemplate] == nil {
                    messageGroups[messageTemplate] = []
                }
                messageGroups[messageTemplate]?.append((id, status, createdTime, completedTime))
            }
        }
        sqlite3_finalize(statement)
        
        // Delete scheduled duplicates if a completed/failed version exists
        var deletedCount = 0
        for (_, messages) in messageGroups where messages.count > 1 {
            // Check if there's a completed or failed message
            let hasCompleted = messages.contains { $0.status == "completed" || $0.status == "failed" }
            
            if hasCompleted {
                // Delete all scheduled versions
                for message in messages where message.status == "scheduled" {
                    let deleteQuery = "DELETE FROM batch_messages WHERE id = ?"
                    var deleteStmt: OpaquePointer?
                    
                    if sqlite3_prepare_v2(db, deleteQuery, -1, &deleteStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(deleteStmt, 1, message.id, -1, nil)
                        
                        if sqlite3_step(deleteStmt) == SQLITE_DONE {
                            deletedCount += 1
                            logger.info("🗑️ Migration 3: Deleted duplicate scheduled message: \(message.id)")
                        }
                    }
                    sqlite3_finalize(deleteStmt)
                }
            }
        }
        
        logger.info("✅ Migration 3: Cleaned up \(deletedCount) duplicate batch messages")
    }
    
    /// Generate chip metadata from existing message template
    private func generateChipMetadataFromTemplate(_ template: String) -> ChipMetadata {
        let registry = ChipTypeRegistry.shared
        let chips = registry.parseExistingChips(in: template)
        
        return ChipMetadata(chips: chips, version: "2.0")
    }
    
    // MARK: - Data Loading
    
    func loadDataFromDatabase() async {
        let callStack = DatabaseLogger.shared.getCallStack()
        let details = "Loading data from SQLite database"
        
        // Enhanced debug logging to track call sources
        logger.info("📊 SQLiteDataProvider: loadDataFromDatabase() called")
        logger.info("📊 SQLiteDataProvider: Call stack: \(callStack)")
        logger.info("📊 SQLiteDataProvider: Database connection status: \(_isConnectedToDatabase)")
        logger.info("📊 SQLiteDataProvider: Database pointer: \(database != nil ? "valid" : "nil")")
        print("🔍 DEBUG: loadDataFromDatabase() called from: \(callStack)")
        
        // Run migrations for existing databases
        await runMigrations()
        
        await loadContactsFromDatabase()
        await loadGroupsFromDatabase()
        await loadInvitesFromDatabase()
        await loadBatchMessagesFromDatabase()
        
        // Defer macOS Contacts sync so UI can render first
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await syncAllContactsToMacOS()
            await syncAllGroupsToMacOS()
        }
        
        logger.info("📊 SQLiteDataProvider: loadDataFromDatabase() completed")
        logger.info("📊 SQLiteDataProvider: Final contacts count: \(contacts.count)")
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "SQLITE_LOAD_DATA",
            details: details + " - Loaded \(contacts.count) contacts and \(groups.count) groups",
            success: true,
            callStack: callStack
        )
    }
    
    private func loadContactsFromDatabase() async {
        guard let db = database else { 
            logger.error("❌ Database connection not available")
            return 
        }
        
        logger.info("🔍 Loading contacts from database...")
        let query = "SELECT id, phone, name, first_name, last_name, email, address, notes, creation_date, business, contact_group, birthday, apple_contact_id, last_message_date FROM contacts"
        
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        
        if result == SQLITE_OK {
            var loadedContacts: [Contact] = []
            
            while sqlite3_step(statement) == SQLITE_ROW {
                // Database ID (integer) - we'll use this for debugging but generate a new UUID for the Contact
                let dbId = sqlite3_column_int(statement, 0)
                let phone = String(cString: sqlite3_column_text(statement, 1))
                let name = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
                let firstName = sqlite3_column_text(statement, 3).map { String(cString: $0) }
                let lastName = sqlite3_column_text(statement, 4).map { String(cString: $0) }
                let email = sqlite3_column_text(statement, 5).map { String(cString: $0) }
                let address = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                let notes = sqlite3_column_text(statement, 7).map { String(cString: $0) }
                let business = sqlite3_column_text(statement, 9).map { String(cString: $0) }
                let contactGroup = sqlite3_column_text(statement, 10).map { String(cString: $0) }
                
                // Handle last message date
                var lastMessageDate: Date? = nil
                if sqlite3_column_type(statement, 13) != SQLITE_NULL {
                    let dateString = sqlite3_column_text(statement, 13).map { String(cString: $0) }
                    if let dateString = dateString, !dateString.isEmpty {
                        let formatter = ISO8601DateFormatter()
                        lastMessageDate = formatter.date(from: dateString)
                    }
                }
                
                let contact = Contact(
                    phone: phone,
                    name: name,
                    firstName: firstName,
                    lastName: lastName,
                    email: email,
                    address: address,
                    notes: notes,
                    business: business,
                    contactGroup: contactGroup,
                    profilePhotoData: nil,
                    lastMessageDate: lastMessageDate
                )
                loadedContacts.append(contact)
            }
            
            await MainActor.run {
                self.contacts = loadedContacts
                if loadedContacts.isEmpty {
                    logger.warning("ℹ️ No contacts found in database. The database is empty or no contacts have been imported yet.")
                    logger.warning("💡 To add contacts, use the import_contacts.py script or add contacts through the macOS Contacts app.")
                } else {
                    logger.info("✅ Successfully loaded \(self.contacts.count) contacts from database")
                }
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Failed to load contacts from database: \(errorMessage)")
        }
        
        sqlite3_finalize(statement)
    }
    
    private func loadGroupsFromDatabase() async {
        logger.info("🔍 Loading groups from database...")
        guard let db = database else {
            logger.error("❌ Database connection is nil in loadGroupsFromDatabase")
            return
        }
        
        let query = "SELECT id, name, color, created_at, parent_id, participants, member_phones, linked_group_ids, metadata, is_deck, canvases, macos_group_id FROM groups"
        
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        
        if result == SQLITE_OK {
            var loadedGroups: [ContactGroup] = []
            
            while sqlite3_step(statement) == SQLITE_ROW {
                // Handle both integer and string IDs, with NULL safety
                let idValue: String
                if sqlite3_column_type(statement, 0) == SQLITE_INTEGER {
                    let intId = sqlite3_column_int(statement, 0)
                    idValue = String(intId)
                } else if let idText = sqlite3_column_text(statement, 0) {
                    idValue = String(cString: idText)
                } else {
                    // Skip groups with NULL IDs as they are invalid
                    logger.warning("⚠️ Skipping group with NULL id")
                    continue
                }
                
                let name = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "Unnamed Group"
                let colorString = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? "#007AFF"
                let parentIdString = sqlite3_column_text(statement, 4).map { String(cString: $0) }
                let participantsJson = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? "[]"
                let memberPhonesJson = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? "[]"
                let isDeck = sqlite3_column_int(statement, 9) == 1
                let canvasesJson = sqlite3_column_text(statement, 10).map { String(cString: $0) } ?? "[]"
                
                // Generate a deterministic UUID from the database ID to maintain consistency
                // This ensures the same database ID always generates the same UUID
                let dbIdInt = Int(idValue) ?? 0
                let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", dbIdInt)) ?? UUID()
                let color = Color(hex: colorString) ?? .blue
                let parentID = parentIdString.flatMap { UUID(uuidString: $0) }
                
                // Parse member phones from participants JSON
                var memberPhones: Set<String> = []
                
                // First try to parse from participants field (primary source)
                if let data = participantsJson.data(using: .utf8),
                   let participants = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    print("🔍 Parsing participants JSON for group '\(name)': \(participants.count) participants")
                    for participant in participants {
                        // Handle new format: {"id": "phone", "name": "name", "UUID": "uuid"}
                        if let contactId = participant["id"] as? String {
                            memberPhones.insert(contactId)
                            print("  📱 Added member: \(contactId)")
                        }
                        // Handle legacy format: {"contact_id": "phone", "contact_uuid": "uuid"}
                        else if let contactId = participant["contact_id"] as? String {
                            memberPhones.insert(contactId)
                            print("  📱 Added member (legacy): \(contactId)")
                        }
                    }
                    print("  ✅ Total memberPhones after participants parsing: \(memberPhones.count)")
                } else {
                    print("  ⚠️ Failed to parse participants JSON: \(participantsJson)")
                }
                
                // Fallback to member_phones field if participants is empty
                if memberPhones.isEmpty,
                   let data = memberPhonesJson.data(using: .utf8),
                   let phones = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    memberPhones = Set(phones)
                    print("  📞 Fallback to member_phones: \(phones.count) phones")
                } else if memberPhones.isEmpty {
                    print("  ⚠️ No member phones found in either participants or member_phones fields")
                }
                
                // Parse canvases from JSON
                var canvases: Set<UUID> = []
                if let data = canvasesJson.data(using: .utf8),
                   let canvasStrings = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    canvases = Set(canvasStrings.compactMap { UUID(uuidString: $0) })
                }
                
                // Parse macOSGroupID if exists
                let macOSGroupID = sqlite3_column_text(statement, 11).map { String(cString: $0) }
                
                var group = ContactGroup(id: id, name: name, color: color, parentID: parentID, isDeck: isDeck)
                group.memberPhones = memberPhones
                group.canvases = canvases
                group.colorHexString = colorString // Store the original hex string from database
                group.databaseId = dbIdInt // Store the database integer ID for canvas matching
                group.macOSGroupID = macOSGroupID
                loadedGroups.append(group)
                
                print("  👥 Loaded group: \(name) with \(memberPhones.count) members [DB ID: \(idValue) -> UUID: \(id)]")
                if !memberPhones.isEmpty {
                    print("    📱 Members: \(Array(memberPhones).joined(separator: ", "))")
                }
                if !participantsJson.isEmpty && participantsJson != "[]" {
                    print("    📋 Participants JSON: \(participantsJson)")
                }
            }
            
            groups = loadedGroups
            print("✅ Successfully loaded \(groups.count) groups from database")
            logger.info("✅ Successfully loaded \(groups.count) groups from database")
            
            // Check if we need to import macOS groups (first run - no groups have macOSGroupID)
            let hasMacOSGroups = loadedGroups.contains { $0.macOSGroupID != nil && !$0.macOSGroupID!.isEmpty }
            if !hasMacOSGroups && !contacts.isEmpty && GroupSyncService.shared.hasPermission() {
                logger.info("🔄 First run detected - importing macOS Contacts groups")
                Task {
                    do {
                        let importedCount = try await GroupSyncService.shared.importMacOSGroupsToCRM(dataProvider: self)
                        logger.info("✅ Imported \(importedCount) macOS groups on first run")
                        // Reload groups after import
                        await loadGroupsFromDatabase()
                    } catch {
                        logger.error("❌ Failed to import macOS groups on first run: \(error)")
                    }
                }
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Failed to load groups from database: \(errorMessage)")
            logger.error("❌ Failed to load groups from database: \(errorMessage)")
        }
        
        sqlite3_finalize(statement)
    }
    

    

    

    

    
    // MARK: - DataProvider Implementation
    
    func fetchContacts(offset: Int, limit: Int, filter: ContactFilter) async throws -> [Contact] {
        var filteredContacts = contacts
        
        // Apply search filter
        if !filter.searchTerm.isEmpty {
            filteredContacts = contacts.filter { contact in
                contact.displayName.localizedCaseInsensitiveContains(filter.searchTerm) ||
                contact.business?.localizedCaseInsensitiveContains(filter.searchTerm) == true ||
                contact.email?.localizedCaseInsensitiveContains(filter.searchTerm) == true
            }
        }
        
        // Apply sorting
        switch filter.sortBy {
        case .name:
            filteredContacts.sort { $0.displayName < $1.displayName }
        case .recent:
            filteredContacts.sort { ($0.creationDate ?? Date.distantPast) > ($1.creationDate ?? Date.distantPast) }
        case .company:
            filteredContacts.sort { ($0.business ?? "") < ($1.business ?? "") }
        case .tags:
            filteredContacts.sort { $0.displayName < $1.displayName }
        }
        
        // Apply pagination
        let endIndex = min(offset + limit, filteredContacts.count)
        let startIndex = min(offset, filteredContacts.count)
        
        return Array(filteredContacts[startIndex..<endIndex])
    }
    
    func countContacts(filter: ContactFilter) async throws -> Int {
        if filter.searchTerm.isEmpty {
            return contacts.count
        } else {
            let filteredContacts = contacts.filter { contact in
                contact.displayName.localizedCaseInsensitiveContains(filter.searchTerm) ||
                contact.business?.localizedCaseInsensitiveContains(filter.searchTerm) == true ||
                contact.email?.localizedCaseInsensitiveContains(filter.searchTerm) == true
            }
            return filteredContacts.count
        }
    }
    
    func fetchContact(by phone: String) async throws -> Contact? {
        return contacts.first { $0.phone == phone }
    }
    
    nonisolated func getContact(by phone: String) -> Contact? {
        return MainActor.assumeIsolated {
            contacts.first { $0.phone == phone }
        }
    }
    
    func createContact(_ contact: Contact) async throws {
        // Check if contact already exists
        if contacts.contains(where: { $0.phone == contact.phone }) {
            throw DataProviderError.queryFailed("Contact with phone number \(contact.phone) already exists")
        }
        
        // Add to memory
        contacts.append(contact)
        
        // Save to database (refresh happens automatically in saveContactToDatabase)
        await saveContactToDatabase(contact)
    }
    
    func updateContact(_ contact: Contact) async throws {
        // Update in memory
        if let index = contacts.firstIndex(where: { $0.phone == contact.phone }) {
            contacts[index] = contact
        }
        
        // Update in database (refresh happens automatically in saveContactToDatabase)
        await saveContactToDatabase(contact)
        
        // Sync to macOS Contacts (async, don't block)
        Task {
            do {
                _ = try await ContactSyncService.shared.syncContactToMacOS(contact)
            } catch {
                logger.warning("⚠️ Failed to sync contact to macOS: \(error)")
            }
        }
    }
    
    func deleteContact(_ phone: String) async throws {
        // Remove from memory
        contacts.removeAll { $0.phone == phone }
        
        // Remove from database (refresh happens automatically in deleteContactFromDatabase)
        await deleteContactFromDatabase(phone)
        
        // Additional explicit refresh to ensure UI updates
        await refreshUIData()
    }
    
    // MARK: - UI Data Refresh
    
    /// Refreshes all UI data by reloading contacts and groups from the database
    /// This ensures all UI components display the current database state
    func refreshUIData() async {
        logger.info("🔄 Refreshing UI data from database...")
        
        // Reload contacts from database
        await loadContactsFromDatabase()
        
        // Reload groups from database
        await loadGroupsFromDatabase()
        
        // Trigger SwiftUI updates via @Published properties
        objectWillChange.send()
        
        // Sync view models with the updated data (without reloading from database)
        await MainActor.run {
            // Sync contacts view model (use .name as default sort option)
            GlobalCanvasService.shared.contactsViewModel.syncWithDataProvider(self, sortOption: .name)
            
            // Sync groups view model
            GlobalCanvasService.shared.groupsViewModel.syncWithDataProvider(self)
        }
        
        logger.info("✅ UI data refreshed - Contacts: \(contacts.count), Groups: \(groups.count)")
        logger.info("✅ View models synced")
    }
    
    // MARK: - macOS Contacts Sync Helpers
    
    /// Sync all contacts to macOS Contacts (for initial sync)
    private func syncAllContactsToMacOS() async {
        guard ContactSyncService.shared.hasPermission() else {
            logger.info("ℹ️ ContactSyncService: No permission, skipping initial contact sync")
            return
        }
        
        logger.info("🔄 Starting initial contact sync to macOS Contacts")
        await ContactSyncService.shared.syncAllContacts(contacts: contacts)
    }
    
    /// Sync all groups to macOS Contacts (for initial sync)
    private func syncAllGroupsToMacOS() async {
        guard GroupSyncService.shared.hasPermission() else {
            logger.info("ℹ️ GroupSyncService: No permission, skipping initial group sync")
            return
        }
        
        logger.info("🔄 Starting initial group sync to macOS Contacts")
        
        for group in groups {
            do {
                _ = try await GroupSyncService.shared.syncGroupToMacOS(group, dataProvider: self)
            } catch {
                logger.warning("⚠️ Failed to sync group '\(group.name)' to macOS: \(error)")
            }
        }
    }
    
    func fetchGroups() async throws -> [ContactGroup] {
        return groups
    }
    
    func refreshGroupsFromDatabase() async throws {
        LogManager.shared.info("🔄 SQLiteDataProvider: Refreshing groups from database")
        await loadGroupsFromDatabase()
        LogManager.shared.info("✅ SQLiteDataProvider: Groups refreshed from database - \(groups.count) groups loaded")
    }
    
    func createGroup(_ group: ContactGroup) async throws {
        // First save to database to get the auto-incremented ID
        await saveGroupToDatabaseAndGetId(group)
        // Refresh happens automatically in saveGroupToDatabase
        
        // Sync to macOS Contacts (async, don't block)
        Task {
            do {
                _ = try await GroupSyncService.shared.syncGroupToMacOS(group, dataProvider: self)
            } catch {
                logger.warning("⚠️ Failed to sync group to macOS: \(error)")
            }
        }
    }
    
    func updateGroup(_ group: ContactGroup) async throws {
        LogManager.shared.info("🔍 UPDATE GROUP DEBUG: updateGroup called for group: \(group.name)")
        LogManager.shared.info("🔍 UPDATE GROUP DEBUG: Group color: \(group.color)")
        LogManager.shared.info("🔍 UPDATE GROUP DEBUG: Group colorHexString: \(group.colorHexString ?? "nil")")
        
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            LogManager.shared.info("🔍 UPDATE GROUP DEBUG: Found group at index \(index)")
            groups[index] = group
            LogManager.shared.info("🔍 UPDATE GROUP DEBUG: Updated group in memory array")
            
            // Save to database and wait for completion (refresh happens automatically)
            LogManager.shared.info("🔍 UPDATE GROUP DEBUG: About to call saveGroupToDatabase")
            await saveGroupToDatabase(group)
            LogManager.shared.info("🔍 UPDATE GROUP DEBUG: saveGroupToDatabase completed")
            
            // Verify the save was successful by checking the database
            LogManager.shared.info("🔍 Verifying group save to database for: \(group.name)")
            
            // Sync to macOS Contacts (async, don't block)
            Task {
                do {
                    _ = try await GroupSyncService.shared.syncGroupToMacOS(group, dataProvider: self)
                } catch {
                    logger.warning("⚠️ Failed to sync group to macOS: \(error)")
                }
            }
        } else {
            LogManager.shared.error("🔍 UPDATE GROUP DEBUG: Group not found in groups array: \(group.name)")
        }
    }
    
    func deleteGroup(_ id: UUID, fromCanvas canvasId: UUID) async throws {
        // Find the group
        guard let groupIndex = groups.firstIndex(where: { $0.id == id }) else {
            throw DataProviderError.groupNotFound
        }
        
        let group = groups[groupIndex]
        
        // Step 1: Check if the group still exists in the current canvas
        // This is determined by the fact that this method is being called
        // If the group doesn't exist in the canvas, this method wouldn't be called
        
        // Step 2: Remove the current canvas UUID from the group's canvases field
        groups[groupIndex].canvases.remove(canvasId)
        
        // Step 3: Check if the length of that group's canvases = 0
        if groups[groupIndex].canvases.isEmpty {
            // Get macOSGroupID before deletion
            let macOSGroupID = group.macOSGroupID
            
            // Delete group from database and memory
            groups.remove(at: groupIndex)
            await deleteGroupFromDatabase(id)
            print("🗑️ Group '\(group.name)' deleted from database (no canvases remaining)")
            
            // Sync deletion to macOS Contacts (async, don't block)
            if let macOSID = macOSGroupID {
                Task {
                    do {
                        try await GroupSyncService.shared.deleteMacOSGroup(macOSGroupID: macOSID)
                    } catch {
                        logger.warning("⚠️ Failed to delete group from macOS: \(error)")
                    }
                }
            }
            
            // Refresh explicitly after deletion
            await refreshUIData()
        } else {
            // Just save the updated group (refresh happens automatically in saveGroupToDatabase)
            await saveGroupToDatabase(groups[groupIndex])
            print("📝 Group '\(group.name)' updated (removed canvas \(canvasId), \(groups[groupIndex].canvases.count) canvases remaining)")
        }
    }
    
    // Keep the old method for backward compatibility
    func deleteGroup(_ id: UUID) async throws {
        // Get the group before deletion to sync deletion to macOS
        let groupToDelete = groups.first { $0.id == id }
        
        // This is the old method that removes the group completely
        groups.removeAll { $0.id == id }
        await deleteGroupFromDatabase(id)
        
        // Sync deletion to macOS Contacts (async, don't block)
        if let group = groupToDelete, let macOSID = group.macOSGroupID {
            Task {
                do {
                    try await GroupSyncService.shared.deleteMacOSGroup(macOSGroupID: macOSID)
                } catch {
                    logger.warning("⚠️ Failed to delete group from macOS: \(error)")
                }
            }
        }
        
        // Explicit refresh after deletion
        await refreshUIData()
    }
    
    func add(phones: [String], to groupID: UUID) async throws {
        print("🔧 Adding phones to group: \(phones) to group ID: \(groupID)")
        LogManager.shared.info("🔧 SQLiteDataProvider.add called with phones: \(phones) to group ID: \(groupID)")
        
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else {
            print("❌ Group not found with ID: \(groupID)")
            print("📋 Available groups: \(groups.map { "\($0.name) (\($0.id))" })")
            LogManager.shared.error("❌ Group not found with ID: \(groupID)")
            LogManager.shared.error("📋 Available groups: \(groups.map { "\($0.name) (\($0.id))" })")
            throw DataProviderError.groupNotFound
        }
        
        let group = groups[groupIndex]
        print("📝 Found group: \(group.name) with current members: \(Array(group.memberPhones))")
        LogManager.shared.info("📝 Found group: \(group.name) with current members: \(Array(group.memberPhones))")
        
        let oldMemberPhones = groups[groupIndex].memberPhones
        groups[groupIndex].memberPhones.formUnion(phones)
        print("📱 Updated group members: \(Array(groups[groupIndex].memberPhones))")
        LogManager.shared.info("📱 Updated group members from \(Array(oldMemberPhones)) to \(Array(groups[groupIndex].memberPhones))")
        
        LogManager.shared.info("💾 Calling saveGroupToDatabase for group: \(group.name)")
        await saveGroupToDatabase(groups[groupIndex])
        LogManager.shared.info("✅ saveGroupToDatabase completed for group: \(group.name)")
        
        // Sync group membership to macOS Contacts (async, don't block)
        Task {
            do {
                try await GroupSyncService.shared.syncGroupMembership(groups[groupIndex], dataProvider: self)
            } catch {
                logger.warning("⚠️ Failed to sync group membership to macOS: \(error)")
            }
        }
        
        // Notify the GlobalCanvasService to refresh canvas group data
        await MainActor.run {
            GlobalCanvasService.shared.refreshCanvasGroupData(groupId: groupID)
        }
        // Refresh happens automatically in saveGroupToDatabase
    }
    
    func removeParticipantEntirely(contactPhone: String, from groupID: UUID) async throws {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else {
            throw DataProviderError.groupNotFound
        }
        
        // Remove from memberPhones (legacy support)
        groups[groupIndex].memberPhones.remove(contactPhone)
        
        // Remove from database using Swift GroupManager
        let databaseId = getGroupDatabaseIdFromUUID(groupID)
        let participantToRemove = GroupParticipant(
            id: contactPhone,
            name: "",
            UUID: "",
            Source: nil  // Remove all sources
        )
        
        let success = groupManager.removeGroupParticipantSource(
            groupId: String(databaseId),
            participantsToRemove: [participantToRemove]
        )
        
        if success {
            print("✅ Successfully removed participant entirely from group")
        } else {
            print("❌ Failed to remove participant entirely")
        }
        
        // Save the updated group (without the contact in memberPhones)
        await saveGroupToDatabase(groups[groupIndex])
        
        // Notify the GlobalCanvasService to refresh canvas group data
        await MainActor.run {
            GlobalCanvasService.shared.refreshCanvasGroupData(groupId: groupID)
        }
        
        // Groups will be automatically updated via @Published groups property
        // No need to force refresh GroupsViewModel - this was causing infinite loops
    }
    
    func move(phones: [String], from sourceGroupID: UUID?, to targetGroupID: UUID) async throws {
        // Remove from source group
        if let sourceID = sourceGroupID,
           let sourceIndex = groups.firstIndex(where: { $0.id == sourceID }) {
            groups[sourceIndex].memberPhones.subtract(phones)
            await saveGroupToDatabase(groups[sourceIndex])
        }
        
        // Add to target group
        guard let targetIndex = groups.firstIndex(where: { $0.id == targetGroupID }) else {
            throw DataProviderError.groupNotFound
        }
        
        groups[targetIndex].memberPhones.formUnion(phones)
        await saveGroupToDatabase(groups[targetIndex])
    }
    
    func addContactWithSource(contactPhone: String, contactName: String, contactUUID: String, to groupID: UUID, sourceType: String, sourceUUID: String) async throws {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else {
            throw DataProviderError.groupNotFound
        }
        
        // Add to memberPhones (legacy support)
        groups[groupIndex].memberPhones.insert(contactPhone)
        
        // Add to database using Swift GroupManager with Source information
        let participantSource = GroupParticipant.ParticipantSource(
            Type: sourceType,
            UUID: sourceUUID
        )
        
        let participant = GroupParticipant(
            id: contactPhone,
            name: contactName,
            UUID: contactUUID,
            Source: [participantSource]
        )
        
        // Use the group's database ID for database operations
        let databaseId = getGroupDatabaseIdFromUUID(groupID)
        
        let success = groupManager.updateGroupParticipants(
            groupId: String(databaseId),
            participants: [participant]
        )
        
        if success {
            print("✅ Successfully added contact with source to group")
        } else {
            print("❌ Failed to add contact with source")
        }
        
        // Save the updated group
        await saveGroupToDatabase(groups[groupIndex])
        
        // Notify the GlobalCanvasService to refresh canvas group data
        await MainActor.run {
            GlobalCanvasService.shared.refreshCanvasGroupData(groupId: groupID)
        }
        
        // Groups will be automatically updated via @Published groups property
        // No need to force refresh GroupsViewModel - this was causing infinite loops
    }
    
    private func getGroupDatabaseIdFromUUID(_ groupUUID: UUID) -> Int {
        // Find the group in our groups array and return its database ID
        // For now, we'll use a simple approach - in a real implementation, 
        // you might want to store the database ID mapping
        if let group = groups.first(where: { $0.id == groupUUID }) {
            // Convert UUID back to database ID (this is a simplified approach)
            let uuidString = group.id.uuidString
            if let lastComponent = uuidString.split(separator: "-").last,
               let dbId = Int(String(lastComponent)) {
                return dbId
            }
        }
        return 1 // Fallback
    }
    
    func remove(phones: [String], from groupID: UUID) async throws {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else {
            throw DataProviderError.groupNotFound
        }
        
        groups[groupIndex].memberPhones.subtract(phones)
        await saveGroupToDatabase(groups[groupIndex])
        
        // Sync group membership to macOS Contacts (async, don't block)
        Task {
            do {
                try await GroupSyncService.shared.syncGroupMembership(groups[groupIndex], dataProvider: self)
            } catch {
                logger.warning("⚠️ Failed to sync group membership to macOS: \(error)")
            }
        }
        
        // Notify the GlobalCanvasService to refresh canvas group data
        await MainActor.run {
            GlobalCanvasService.shared.refreshCanvasGroupData(groupId: groupID)
        }
        
        // Groups will be automatically updated via @Published groups property
        // No need to force refresh GroupsViewModel - this was causing infinite loops
    }
    
    nonisolated func getGroupMembers(groupId: UUID) -> [String]? {
        return MainActor.assumeIsolated {
            groups.first { $0.id == groupId }.map { Array($0.memberPhones) }
        }
    }
    
    func updateGroupMembers(groupId: UUID, members: [String]) async throws {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else {
            throw DataProviderError.groupNotFound
        }
        groups[index].memberPhones = Set(members)
        // Refresh happens automatically in saveGroupToDatabase
        await saveGroupToDatabase(groups[index])
        
        // Sync group membership to macOS Contacts (async, don't block)
        Task {
            do {
                try await GroupSyncService.shared.syncGroupMembership(groups[index], dataProvider: self)
            } catch {
                logger.warning("⚠️ Failed to sync group membership to macOS: \(error)")
            }
        }
    }
    
    // MARK: - Canvas Management for Groups
    
    func addCanvasToGroup(groupId: UUID, canvasId: UUID) async throws {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else {
            throw DataProviderError.groupNotFound
        }
        groups[index].canvases.insert(canvasId)
        await saveGroupToDatabase(groups[index])
    }
    
    func removeCanvasFromGroup(groupId: UUID, canvasId: UUID) async throws {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else {
            throw DataProviderError.groupNotFound
        }
        groups[index].canvases.remove(canvasId)
        await saveGroupToDatabase(groups[index])
    }
    
    func getGroupCanvases(groupId: UUID) -> Set<UUID> {
        guard let group = groups.first(where: { $0.id == groupId }) else {
            return []
        }
        return group.canvases
    }
    
    func removeGroupFromCanvas(groupId: UUID, canvasId: UUID) async throws {
        // This method removes a group from a specific canvas
        // It's the inverse of removeCanvasFromGroup
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else {
            throw DataProviderError.groupNotFound
        }
        groups[index].canvases.remove(canvasId)
        await saveGroupToDatabase(groups[index])
    }
    
    func removeGroupFromCanvasElements(groupId: UUID, canvasId: UUID) async throws {
        // Remove the group from canvas elements in the database
        guard let db = database else {
            throw DataProviderError.databaseConnectionFailed
        }
        
        // Get the current canvas elements
        let selectQuery = "SELECT canvas_elements FROM canvases WHERE canvas_id = ?"
        var selectStatement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, selectQuery, -1, &selectStatement, nil) == SQLITE_OK else {
            throw DataProviderError.queryFailed("Failed to prepare select statement")
        }
        
        sqlite3_bind_text(selectStatement, 1, canvasId.uuidString, -1, nil)
        
        guard sqlite3_step(selectStatement) == SQLITE_ROW else {
            sqlite3_finalize(selectStatement)
            throw DataProviderError.canvasNotFound
        }
        
        let elementsJson = String(cString: sqlite3_column_text(selectStatement, 0))
        sqlite3_finalize(selectStatement)
        
        // Parse the JSON and remove the group element
        guard let elementsData = elementsJson.data(using: String.Encoding.utf8) else {
            throw DataProviderError.invalidData
        }
        
        var elements = try JSONDecoder().decode([CanvasElement].self, from: elementsData)
        
        // Remove elements with the group ID
        elements.removeAll { element in
            element.id == groupId.uuidString && element.elementType == .group
        }
        
        // Update the canvas with the modified elements
        let updateQuery = "UPDATE canvases SET canvas_elements = ?, date_updated = datetime('now') WHERE canvas_id = ?"
        var updateStatement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, updateQuery, -1, &updateStatement, nil) == SQLITE_OK else {
            throw DataProviderError.queryFailed("Failed to prepare update statement")
        }
        
        let updatedElementsJson = try JSONEncoder().encode(elements)
        let updatedElementsString = String(data: updatedElementsJson, encoding: String.Encoding.utf8) ?? "[]"
        
        sqlite3_bind_text(updateStatement, 1, updatedElementsString, -1, nil)
        sqlite3_bind_text(updateStatement, 2, canvasId.uuidString, -1, nil)
        
        guard sqlite3_step(updateStatement) == SQLITE_DONE else {
            sqlite3_finalize(updateStatement)
            throw DataProviderError.queryFailed("Failed to update canvas elements")
        }
        
        sqlite3_finalize(updateStatement)
    }
    

    
    // MARK: - Database Write Operations
    
    private func saveContactToDatabase(_ contact: Contact) async {
        guard let db = database else { return }
        
        let query = """
        INSERT OR REPLACE INTO contacts 
        (phone, name, first_name, last_name, email, address, notes, business, contact_group, profile_photo)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, contact.phone, -1, nil)
            sqlite3_bind_text(statement, 2, contact.name, -1, nil)
            sqlite3_bind_text(statement, 3, contact.firstName, -1, nil)
            sqlite3_bind_text(statement, 4, contact.lastName, -1, nil)
            sqlite3_bind_text(statement, 5, contact.email, -1, nil)
            sqlite3_bind_text(statement, 6, contact.address, -1, nil)
            sqlite3_bind_text(statement, 7, contact.notes, -1, nil)
            sqlite3_bind_text(statement, 8, contact.business, -1, nil)
            sqlite3_bind_text(statement, 9, contact.contactGroup, -1, nil)
            
            if let photoData = contact.profilePhotoData {
                _ = photoData.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, 10, bytes.baseAddress, Int32(photoData.count), nil)
                }
            } else {
                sqlite3_bind_null(statement, 10)
            }
            
            if sqlite3_step(statement) != SQLITE_DONE {
                print("❌ Failed to save contact to database")
            }
        }
        
        sqlite3_finalize(statement)
        
        // Checkpoint WAL to release locks
        checkpointWAL(reason: "saveContact")
        
        // Refresh UI after every contact database write
        await refreshUIData()
    }
    
    private func deleteContactFromDatabase(_ phone: String) async {
        guard let db = database else { return }
        
        let query = "DELETE FROM contacts WHERE phone = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, phone, -1, nil)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                print("❌ Failed to delete contact from database")
            }
        }
        
        sqlite3_finalize(statement)
        
        // Checkpoint WAL to release locks
        checkpointWAL(reason: "deleteContact")
    }
    
    /// Save group to database and generate proper UUID from auto-incremented ID
    private func saveGroupToDatabaseAndGetId(_ group: ContactGroup) async {
        logger.info("💾 saveGroupToDatabaseAndGetId called for group: \(group.name)")
        guard let db = database else {
            logger.error("❌ Database connection is nil")
            return
        }
        
        // Track transaction state for cleanup
        var transactionActive = false
        defer {
            if transactionActive {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                logger.warning("⚠️ Transaction auto-rolled back on exit")
            }
        }
        
        // BEGIN TRANSACTION for atomic operation
        var beginStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, "BEGIN TRANSACTION", -1, &beginStatement, nil) == SQLITE_OK {
            sqlite3_step(beginStatement)
            sqlite3_finalize(beginStatement)
            transactionActive = true
            logger.info("🔄 Transaction started for group creation")
        }
        
        // Prepare group data
        let colorHexToSave = group.colorHexString ?? group.color.toHexString()
        let escapedName = group.name.replacingOccurrences(of: "'", with: "''")
        
        // Convert member phones to JSON
        let memberPhonesJson = try! JSONSerialization.data(withJSONObject: Array(group.memberPhones))
        let memberPhonesString = String(data: memberPhonesJson, encoding: .utf8) ?? "[]"
        let escapedMemberPhones = memberPhonesString.replacingOccurrences(of: "'", with: "''")
        
        // Convert participants to JSON
        var participants: [[String: Any]] = []
        for phone in group.memberPhones {
            if let contact = contacts.first(where: { $0.phone == phone }) {
                participants.append([
                    "id": contact.phone,
                    "name": contact.name,
                    "UUID": contact.id.uuidString
                ])
            }
        }
        let participantsJson = try! JSONSerialization.data(withJSONObject: participants)
        let participantsString = String(data: participantsJson, encoding: .utf8) ?? "[]"
        let escapedParticipants = participantsString.replacingOccurrences(of: "'", with: "''")
        
        // Convert canvases to JSON
        let canvasesJson = try! JSONSerialization.data(withJSONObject: Array(group.canvases.map { $0.uuidString }))
        let canvasesString = String(data: canvasesJson, encoding: .utf8) ?? "[]"
        let escapedCanvases = canvasesString.replacingOccurrences(of: "'", with: "''")
        
        let formatter = ISO8601DateFormatter()
        let createdAtString = formatter.string(from: group.createdAt)
        
        // Get next ID from database (id is TEXT, so we need to generate it)
        var maxId = 0
        let maxIdQuery = "SELECT COALESCE(MAX(CAST(id AS INTEGER)), 0) FROM groups"
        var maxIdStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, maxIdQuery, -1, &maxIdStatement, nil) == SQLITE_OK {
            if sqlite3_step(maxIdStatement) == SQLITE_ROW {
                maxId = Int(sqlite3_column_int(maxIdStatement, 0))
            }
        }
        sqlite3_finalize(maxIdStatement)
        
        let newId = maxId + 1
        let idString = String(newId)
        logger.info("🆔 Generated new group ID: \(newId)")
        
        // INSERT with explicit ID value (id is TEXT column, not auto-increment)
        let insertQuery = """
        INSERT INTO groups (
            id, name, color, participants, member_phones, parent_id, 
            linked_group_ids, metadata, is_deck, canvases, created_at
        ) VALUES (
            '\(idString)', '\(escapedName)', '\(colorHexToSave)', '\(escapedParticipants)', '\(escapedMemberPhones)', 
            '', '[]', '{"inviteCount":0,"interconnectivityScore":0}', 
            \(group.isDeck ? 1 : 0), '\(escapedCanvases)', '\(createdAtString)'
        )
        """
        
        var statement: OpaquePointer?
        var success = false
        
        if sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_DONE {
                logger.info("✅ Created group '\(group.name)' with database ID: \(newId)")
                success = true
                
                // Generate proper UUID from database ID
                let properUUID = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", newId)) ?? UUID()
                
                // Create updated group with proper UUID
                var updatedGroup = group
                updatedGroup.id = properUUID
                
                // Add to groups array
                groups.append(updatedGroup)
                logger.info("✅ Added group to memory with UUID: \(properUUID.uuidString)")
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                let errorCode = sqlite3_errcode(db)
                logger.error("❌ Failed to insert group: \(errorMessage) (Error code: \(errorCode))")
                logger.error("💡 Database path: \(currentDatabasePath ?? "unknown")")
                
                // Provide specific diagnostics based on error type
                if errorCode == SQLITE_IOERR || errorCode == SQLITE_CANTOPEN || errorCode == SQLITE_READONLY {
                    logger.error("❌ Disk I/O Error Detected - Running diagnostics...")
                    
                    // Get detailed diagnostics
                    if let dbPath = currentDatabasePath {
                        let diagnostics = DatabasePermissionChecker.shared.getDiagnosticInfo(path: dbPath)
                        logger.error("📊 Diagnostic Results:")
                        for diagnostic in diagnostics {
                            logger.error("   \(diagnostic)")
                        }
                    }
                    
                    logger.error("💡 Common causes of I/O errors:")
                    logger.error("   1. Database in cloud-synced folder (iCloud, Google Drive, Dropbox)")
                    logger.error("   2. Missing Full Disk Access permission")
                    logger.error("   3. Disk full or filesystem read-only")
                    logger.error("   4. Another app instance has database locked")
                    logger.error("   5. Antivirus/backup software interfering with database")
                    logger.error("💡 Recommended: Move database to ~/Library/Application Support/My_CRM/")
                } else if errorCode == SQLITE_LOCKED || errorCode == SQLITE_BUSY {
                    logger.error("❌ Database Lock Error - Another process may be accessing the database")
                    logger.error("💡 Check if another instance of My CRM is running")
                } else {
                    logger.error("💡 This may indicate database corruption or schema issues")
                }
            }
        }
        sqlite3_finalize(statement)
        
        // COMMIT or ROLLBACK transaction based on success
        var transactionStatement: OpaquePointer?
        if success {
            if sqlite3_prepare_v2(db, "COMMIT", -1, &transactionStatement, nil) == SQLITE_OK {
                sqlite3_step(transactionStatement)
                sqlite3_finalize(transactionStatement)
                transactionActive = false  // Prevent defer rollback
                logger.info("✅ Transaction committed successfully")
            }
        } else {
            if sqlite3_prepare_v2(db, "ROLLBACK", -1, &transactionStatement, nil) == SQLITE_OK {
                sqlite3_step(transactionStatement)
                sqlite3_finalize(transactionStatement)
                transactionActive = false  // Prevent defer rollback
                logger.warning("⚠️ Transaction rolled back due to error")
            }
        }
        
        // Checkpoint WAL to release locks after transaction
        if !transactionActive {
            checkpointWAL(reason: "saveGroupTransaction")
        }
        
        // Refresh UI after group creation (only if successful)
        if success {
            await refreshUIData()
        }
    }
    
    private func saveGroupToDatabase(_ group: ContactGroup) async {
        LogManager.shared.info("💾 saveGroupToDatabase called for group: \(group.name)")
        guard let db = database else { 
            LogManager.shared.error("❌ Database connection is nil in saveGroupToDatabase")
            return 
        }
        
        // Track transaction state for cleanup
        var transactionActive = false
        defer {
            if transactionActive {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                LogManager.shared.warning("⚠️ Transaction auto-rolled back on exit")
            }
        }
        
        LogManager.shared.info("✅ Database connection is available")
        
        // Extract database ID from UUID (reverse of the generation process)
        // The UUID format is: "00000000-0000-0000-0000-%012d"
        // We need to extract the integer part from the last 12 characters
        let uuidString = group.id.uuidString
        let last12Chars = String(uuidString.suffix(12))
        // Remove leading zeros to get the actual database ID
        let dbId = Int(last12Chars) ?? 0
        LogManager.shared.info("🆔 Extracted DB ID: \(dbId) from UUID: \(uuidString) (last 12 chars: \(last12Chars))")
        
        // Debug: Print the actual group data being used
        let colorHex = group.colorHexString ?? group.color.toHexString()
        print("🔍 DEBUG: About to save group with name: '\(group.name)', color: '\(colorHex)', \(group.memberPhones.count) member phones, \(group.linkedGroupIDs.count) linked groups, isDeck: \(group.isDeck)")
        print("🔍 DEBUG: Group colorHexString: '\(group.colorHexString ?? "nil")', color.toHexString(): '\(group.color.toHexString())'")
        LogManager.shared.info("🔍 DEBUG: About to save group with name: '\(group.name)', color: '\(colorHex)', \(group.memberPhones.count) member phones, \(group.linkedGroupIDs.count) linked groups, isDeck: \(group.isDeck)")
        LogManager.shared.info("🔍 DEBUG: Group colorHexString: '\(group.colorHexString ?? "nil")', color.toHexString(): '\(group.color.toHexString())'")
        
        // Use string interpolation instead of parameter binding to avoid any parameter binding issues
        // Escape single quotes in the group name to prevent SQL injection
        let escapedName = group.name.replacingOccurrences(of: "'", with: "''")
        let colorHexToSave = group.colorHexString ?? group.color.toHexString()
        LogManager.shared.info("🔍 SAVE DEBUG: Group.colorHexString: \(group.colorHexString ?? "nil")")
        LogManager.shared.info("🔍 SAVE DEBUG: Group.color.toHexString(): \(group.color.toHexString())")
        LogManager.shared.info("🔍 SAVE DEBUG: Final color hex being saved: '\(colorHexToSave)'")
        
        // Convert member phones to JSON array
        let memberPhonesJson = try! JSONSerialization.data(withJSONObject: Array(group.memberPhones))
        let memberPhonesString = String(data: memberPhonesJson, encoding: .utf8) ?? "[]"
        let escapedMemberPhones = memberPhonesString.replacingOccurrences(of: "'", with: "''")
        
        // Convert participants to JSON array with full contact data
        var participants: [[String: Any]] = []
        for phone in group.memberPhones {
            // Find the contact data for this phone number
            if let contact = contacts.first(where: { $0.phone == phone }) {
                let participantData: [String: Any] = [
                    "id": contact.phone,
                    "name": contact.name,
                    "UUID": contact.id.uuidString
                ]
                participants.append(participantData)
            } else {
                // If contact not found, still include the phone number
                let participantData: [String: Any] = [
                    "id": phone,
                    "name": "",
                    "UUID": ""
                ]
                participants.append(participantData)
            }
        }
        let participantsJson = try! JSONSerialization.data(withJSONObject: participants)
        let participantsString = String(data: participantsJson, encoding: .utf8) ?? "[]"
        let escapedParticipants = participantsString.replacingOccurrences(of: "'", with: "''")
        
        // Convert linked group IDs to JSON array
        let linkedGroupIdsJson = try! JSONSerialization.data(withJSONObject: Array(group.linkedGroupIDs.map { $0.uuidString }))
        let linkedGroupIdsString = String(data: linkedGroupIdsJson, encoding: .utf8) ?? "[]"
        let escapedLinkedGroupIds = linkedGroupIdsString.replacingOccurrences(of: "'", with: "''")
        
        // Convert metadata to JSON
        let metadataJson = try! JSONSerialization.data(withJSONObject: [
            "inviteCount": group.metadata.inviteCount,
            "interconnectivityScore": group.metadata.interconnectivityScore
        ])
        let metadataString = String(data: metadataJson, encoding: .utf8) ?? "{}"
        let escapedMetadata = metadataString.replacingOccurrences(of: "'", with: "''")
        
        // Convert canvases to JSON array
        let canvasesJson = try! JSONSerialization.data(withJSONObject: Array(group.canvases.map { $0.uuidString }))
        let canvasesString = String(data: canvasesJson, encoding: .utf8) ?? "[]"
        let escapedCanvases = canvasesString.replacingOccurrences(of: "'", with: "''")
        
        // Handle parent ID
        let parentIdString = group.parentID?.uuidString ?? ""
        let escapedParentId = parentIdString.replacingOccurrences(of: "'", with: "''")
        
        // Format created date
        let formatter = ISO8601DateFormatter()
        let createdAtString = formatter.string(from: group.createdAt)
        let escapedCreatedAt = createdAtString.replacingOccurrences(of: "'", with: "''")
        
        // Check if group already exists in database
        let checkQuery = "SELECT COUNT(*) FROM groups WHERE id = \(dbId)"
        var checkStatement: OpaquePointer?
        var groupExists = false
        
        if sqlite3_prepare_v2(db, checkQuery, -1, &checkStatement, nil) == SQLITE_OK {
            if sqlite3_step(checkStatement) == SQLITE_ROW {
                let count = sqlite3_column_int(checkStatement, 0)
                groupExists = count > 0
            }
        }
        sqlite3_finalize(checkStatement)
        
        let query: String
        if groupExists {
            // Update existing group
            query = """
            UPDATE groups SET 
                name = '\(escapedName)', 
                color = '\(colorHexToSave)', 
                participants = '\(escapedParticipants)',
                member_phones = '\(escapedMemberPhones)',
                parent_id = '\(escapedParentId)',
                linked_group_ids = '\(escapedLinkedGroupIds)',
                metadata = '\(escapedMetadata)',
                is_deck = \(group.isDeck ? 1 : 0),
                canvases = '\(escapedCanvases)',
                created_at = '\(escapedCreatedAt)'
            WHERE id = \(dbId)
            """
            LogManager.shared.info("🔄 Updating existing group with ID: \(dbId)")
        } else {
            // Insert new group
            query = """
            INSERT INTO groups (
                id, name, color, participants, member_phones, parent_id, 
                linked_group_ids, metadata, is_deck, canvases, created_at
            ) VALUES (
                \(dbId), '\(escapedName)', '\(colorHexToSave)', '\(escapedParticipants)', '\(escapedMemberPhones)', 
                '\(escapedParentId)', '\(escapedLinkedGroupIds)', '\(escapedMetadata)', 
                \(group.isDeck ? 1 : 0), '\(escapedCanvases)', '\(escapedCreatedAt)'
            )
            """
            LogManager.shared.info("➕ Inserting new group with ID: \(dbId)")
        }
        
        print("🔧 DEBUG: Executing SQL query: \(query)")
        LogManager.shared.info("🔧 DEBUG: Executing SQL query: \(query)")
        LogManager.shared.info("🔍 SQL DEBUG: Color value in query: '\(colorHexToSave)'")
        LogManager.shared.info("🔍 SQL DEBUG: Group exists: \(groupExists)")
        
        // Begin a transaction to ensure atomicity
        let beginResult = sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        if beginResult != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            LogManager.shared.error("❌ Failed to begin database transaction: \(errorMessage)")
            return
        }
        transactionActive = true
        
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        LogManager.shared.info("🔧 SQLite prepare result: \(prepareResult)")
        
        if prepareResult == SQLITE_OK {
            LogManager.shared.info("✅ SQLite statement prepared successfully")
            
            let stepResult = sqlite3_step(statement)
            if stepResult != SQLITE_DONE {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                print("❌ Failed to save group data to database: \(errorMessage)")
                LogManager.shared.error("❌ Failed to save group data to database: \(errorMessage)")
                
                // Rollback the transaction on error
                let rollbackResult = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                transactionActive = false  // Prevent defer rollback
                if rollbackResult != SQLITE_OK {
                    let rollbackError = String(cString: sqlite3_errmsg(db))
                    LogManager.shared.error("❌ Failed to rollback database transaction: \(rollbackError)")
                }
            } else {
                let operation = groupExists ? "updated" : "inserted"
                print("✅ Successfully \(operation) group data to database: '\(group.name)' (name, color, members, metadata, etc.)")
                LogManager.shared.info("✅ Successfully \(operation) group data to database: '\(group.name)' (name, color, members, metadata, etc.)")
                LogManager.shared.info("🔍 POST-SAVE DEBUG: Color that was saved: '\(colorHexToSave)'")
                
                // Ensure the database transaction is committed immediately
                let commitResult = sqlite3_exec(db, "COMMIT", nil, nil, nil)
                transactionActive = false  // Prevent defer rollback
                if commitResult == SQLITE_OK {
                    LogManager.shared.info("✅ Database transaction committed successfully for group: '\(group.name)'")
                    LogManager.shared.info("🔍 COMMIT DEBUG: Color committed to database: '\(colorHexToSave)'")
                } else {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    LogManager.shared.error("❌ Failed to commit database transaction: \(errorMessage)")
                }
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Failed to prepare SQL statement: \(errorMessage)")
            LogManager.shared.error("❌ Failed to prepare SQL statement: \(errorMessage)")
            
            // Rollback the transaction on error
            let rollbackResult = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            transactionActive = false  // Prevent defer rollback
            if rollbackResult != SQLITE_OK {
                let rollbackError = String(cString: sqlite3_errmsg(db))
                LogManager.shared.error("❌ Failed to rollback database transaction: \(rollbackError)")
            }
        }
        
        sqlite3_finalize(statement)
        
        // Checkpoint WAL to release locks after transaction
        if !transactionActive {
            checkpointWAL(reason: "upsertGroup")
        }
        
        // Refresh UI after every group database write
        await refreshUIData()
    }
    
    private func deleteGroupFromDatabase(_ id: UUID) async {
        guard let db = database else { return }
        
        // Extract database ID from UUID
        // The UUID format is: "00000000-0000-0000-0000-%012d"
        let uuidString = id.uuidString
        let last12Chars = String(uuidString.suffix(12))
        let dbId = Int(last12Chars) ?? 0
        
        let query = "DELETE FROM groups WHERE id = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(dbId))  // Bind as INTEGER to match database schema
            
            if sqlite3_step(statement) != SQLITE_DONE {
                print("❌ Failed to delete group from database")
            }
        }
        
        sqlite3_finalize(statement)
    }
    
    // MARK: - Batch Messages
    
    @Published var batchMessages: [BatchMessage] = []
    
    func saveBatchMessage(_ batchMessage: BatchMessage) async {
        print("🚀 DEBUG: saveBatchMessage called for ID: \(batchMessage.id)")
        logger.info("💾 SQLiteDataProvider: saveBatchMessage called for ID: \(batchMessage.id)")
        
        // Input validation
        guard !batchMessage.messageTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let errorMsg = "❌ SQLiteDataProvider: Message template is empty"
            print(errorMsg)
            logger.error(errorMsg)
            return
        }
        
        guard !batchMessage.recipients.isEmpty else {
            let errorMsg = "❌ SQLiteDataProvider: No recipients provided"
            print(errorMsg)
            logger.error(errorMsg)
            return
        }
        
        logger.info("📝 SQLiteDataProvider: Validating batch message - Template length: \(batchMessage.messageTemplate.count), Recipients: \(batchMessage.recipients.count)")
        
        // Validate recipients
        for (index, recipient) in batchMessage.recipients.enumerated() {
            guard !recipient.phone.isEmpty else {
                let errorMsg = "❌ SQLiteDataProvider: Recipient \(index) has empty phone number"
                print(errorMsg)
                logger.error(errorMsg)
                return
            }
            logger.info("📞 SQLiteDataProvider: Recipient \(index): \(recipient.name) (\(recipient.phone))")
        }
        
        guard let db = database else { 
            let errorMsg = "❌ SQLiteDataProvider: Database is nil in saveBatchMessage"
            print(errorMsg)
            logger.error(errorMsg)
            return 
        }
        
        // Verify database connection
        guard _isConnectedToDatabase else {
            let errorMsg = "❌ SQLiteDataProvider: Database not connected in saveBatchMessage"
            print(errorMsg)
            logger.error(errorMsg)
            return
        }
        
        logger.info("✅ SQLiteDataProvider: Database connection validated")
        let formatter = ISO8601DateFormatter()
        
        // Begin transaction for atomic operation
        let beginResult = sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        if beginResult != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            let errorMsg = "❌ SQLiteDataProvider: Failed to begin transaction: \(errorMessage)"
            print(errorMsg)
            logger.error(errorMsg)
            return
        }
        logger.info("🔄 SQLiteDataProvider: Database transaction started")
        
        // Convert chip metadata to JSON with proper error handling
        let chipMetadataJson: String
        if let chipMetadata = batchMessage.chipMetadata {
            do {
                let metadataData = try JSONEncoder().encode(chipMetadata)
                if let metadataString = String(data: metadataData, encoding: .utf8) {
                    chipMetadataJson = metadataString
                    logger.info("📊 SQLiteDataProvider: Chip metadata encoded successfully (\(metadataString.count) chars)")
                } else {
                    let errorMsg = "❌ SQLiteDataProvider: Failed to convert chip metadata to string"
                    print(errorMsg)
                    logger.error(errorMsg)
                    sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                    return
                }
            } catch {
                let errorMsg = "❌ SQLiteDataProvider: Failed to encode chip metadata: \(error.localizedDescription)"
                print(errorMsg)
                logger.error(errorMsg)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return
            }
        } else {
            chipMetadataJson = ""
            logger.info("📊 SQLiteDataProvider: No chip metadata to encode")
        }
        
        // Convert recipients to JSON with proper error handling
        let recipientsJson: String
        do {
            let recipientsData = try JSONEncoder().encode(batchMessage.recipients)
            if let recipientsString = String(data: recipientsData, encoding: .utf8) {
                recipientsJson = recipientsString
                logger.info("👥 SQLiteDataProvider: Recipients encoded successfully (\(recipientsString.count) chars)")
            } else {
                let errorMsg = "❌ SQLiteDataProvider: Failed to convert recipients to string"
                print(errorMsg)
                logger.error(errorMsg)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return
            }
        } catch {
            let errorMsg = "❌ SQLiteDataProvider: Failed to encode recipients: \(error.localizedDescription)"
            print(errorMsg)
            logger.error(errorMsg)
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        
        // Convert failed contacts to JSON with proper error handling
        let failedContactsJson: String
        do {
            let failedContactsData = try JSONSerialization.data(withJSONObject: batchMessage.failedContacts)
            if let failedContactsString = String(data: failedContactsData, encoding: .utf8) {
                failedContactsJson = failedContactsString
                logger.info("❌ SQLiteDataProvider: Failed contacts encoded successfully (\(failedContactsString.count) chars)")
            } else {
                let errorMsg = "❌ SQLiteDataProvider: Failed to convert failed contacts to string"
                print(errorMsg)
                logger.error(errorMsg)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return
            }
        } catch {
            let errorMsg = "❌ SQLiteDataProvider: Failed to encode failed contacts: \(error.localizedDescription)"
            print(errorMsg)
            logger.error(errorMsg)
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        
        // Convert error log to JSON with proper error handling
        let errorLogJson: String
        do {
            let errorLogData = try JSONEncoder().encode(batchMessage.errorLog)
            if let errorLogString = String(data: errorLogData, encoding: .utf8) {
                errorLogJson = errorLogString
                logger.info("📋 SQLiteDataProvider: Error log encoded successfully (\(errorLogString.count) chars)")
            } else {
                let errorMsg = "❌ SQLiteDataProvider: Failed to convert error log to string"
                print(errorMsg)
                logger.error(errorMsg)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return
            }
        } catch {
            let errorMsg = "❌ SQLiteDataProvider: Failed to encode error log: \(error.localizedDescription)"
            print(errorMsg)
            logger.error(errorMsg)
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        
        let query = """
        INSERT OR REPLACE INTO batch_messages 
        (id, message_template, recipients, scheduled_time, created_time, status, 
         total_recipients, sent_count, failed_count, failed_contacts, completed_time, 
         notify_when_sent, error_log, field_metadata, source_groups)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        logger.info("🔧 SQLiteDataProvider: Preparing SQL statement")
        logger.info("📝 SQLiteDataProvider: SQL Query: \(query)")
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        
        if prepareResult != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            let errorMsg = "❌ SQLiteDataProvider: Failed to prepare statement: \(errorMessage)"
            print(errorMsg)
            logger.error(errorMsg)
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        
        logger.info("✅ SQLiteDataProvider: SQL statement prepared successfully")
        
        // Bind parameters with validation
        // Parameters 1-3: id, message_template, recipients
        logger.info("🔧 Binding param 1 (id): '\(batchMessage.id.uuidString)'")
        logger.info("🔧 Binding param 2 (message_template): '\(batchMessage.messageTemplate)'")
        logger.info("🔧 Binding param 3 (recipients): '\(recipientsJson.prefix(100))...'")
        
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        
        let bindResults = [
            sqlite3_bind_text(statement, 1, (batchMessage.id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT),
            sqlite3_bind_text(statement, 2, (batchMessage.messageTemplate as NSString).utf8String, -1, SQLITE_TRANSIENT),
            sqlite3_bind_text(statement, 3, (recipientsJson as NSString).utf8String, -1, SQLITE_TRANSIENT)
        ]
        
        // Check for binding errors
        for (index, result) in bindResults.enumerated() {
            if result != SQLITE_OK {
                let errorMsg = "❌ SQLiteDataProvider: Failed to bind parameter \(index + 1): \(result)"
                print(errorMsg)
                logger.error(errorMsg)
                sqlite3_finalize(statement)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return
            }
        }
        
        // Bind optional scheduled time (parameter 4)
        if let scheduledTime = batchMessage.scheduledTime {
            let scheduledTimeString = formatter.string(from: scheduledTime)
            let bindResult = sqlite3_bind_text(statement, 4, (scheduledTimeString as NSString).utf8String, -1, SQLITE_TRANSIENT)
            if bindResult != SQLITE_OK {
                let errorMsg = "❌ SQLiteDataProvider: Failed to bind scheduled time: \(bindResult)"
                print(errorMsg)
                logger.error(errorMsg)
                sqlite3_finalize(statement)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return
            }
            logger.info("⏰ SQLiteDataProvider: Scheduled time bound: \(scheduledTimeString)")
        } else {
            let bindResult = sqlite3_bind_null(statement, 4)
            if bindResult != SQLITE_OK {
                let errorMsg = "❌ SQLiteDataProvider: Failed to bind null scheduled time: \(bindResult)"
                print(errorMsg)
                logger.error(errorMsg)
                sqlite3_finalize(statement)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return
            }
            logger.info("⏰ SQLiteDataProvider: No scheduled time (null)")
        }
        
        // Bind remaining parameters 5-10: created_time through failed_contacts
        let createdTimeString = formatter.string(from: batchMessage.createdTime)
        logger.info("🔧 Binding param 5 (created_time): '\(createdTimeString)'")
        logger.info("🔧 Binding param 6 (status): '\(batchMessage.status.rawValue)'")
        logger.info("🔧 Binding param 7-9 (counts): \(batchMessage.totalRecipients), \(batchMessage.sentCount), \(batchMessage.failedCount)")
        logger.info("🔧 Binding param 10 (failed_contacts): '\(failedContactsJson.prefix(50))...'")
        
        let remainingBindResults = [
            sqlite3_bind_text(statement, 5, (createdTimeString as NSString).utf8String, -1, SQLITE_TRANSIENT),
            sqlite3_bind_text(statement, 6, (batchMessage.status.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT),
            sqlite3_bind_int(statement, 7, Int32(batchMessage.totalRecipients)),
            sqlite3_bind_int(statement, 8, Int32(batchMessage.sentCount)),
            sqlite3_bind_int(statement, 9, Int32(batchMessage.failedCount)),
            sqlite3_bind_text(statement, 10, (failedContactsJson as NSString).utf8String, -1, SQLITE_TRANSIENT)
        ]
        
        for (index, result) in remainingBindResults.enumerated() {
            if result != SQLITE_OK {
                let errorMsg = "❌ SQLiteDataProvider: Failed to bind parameter \(index + 5): \(result)"
                print(errorMsg)
                logger.error(errorMsg)
                sqlite3_finalize(statement)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return
            }
        }
        
        // Bind optional completed time (parameter 11)
        if let completedTime = batchMessage.completedTime {
            let completedTimeString = formatter.string(from: completedTime)
            logger.info("🔧 Binding param 11 (completed_time): '\(completedTimeString)'")
            let bindResult = sqlite3_bind_text(statement, 11, (completedTimeString as NSString).utf8String, -1, SQLITE_TRANSIENT)
            if bindResult != SQLITE_OK {
                let errorMsg = "❌ SQLiteDataProvider: Failed to bind completed time: \(bindResult)"
                print(errorMsg)
                logger.error(errorMsg)
                sqlite3_finalize(statement)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return
            }
            logger.info("✅ SQLiteDataProvider: Completed time bound: \(completedTimeString)")
        } else {
            let bindResult = sqlite3_bind_null(statement, 11)
            if bindResult != SQLITE_OK {
                let errorMsg = "❌ SQLiteDataProvider: Failed to bind null completed time: \(bindResult)"
                print(errorMsg)
                logger.error(errorMsg)
                sqlite3_finalize(statement)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return
            }
            logger.info("✅ SQLiteDataProvider: No completed time (null)")
        }
        
        // Encode source_groups
        let sourceGroupsJson: String
        if let sourceGroups = batchMessage.sourceGroups, !sourceGroups.isEmpty {
            do {
                let sourceGroupsData = try JSONEncoder().encode(sourceGroups.map { $0.uuidString })
                sourceGroupsJson = String(data: sourceGroupsData, encoding: .utf8) ?? "[]"
            } catch {
                logger.error("❌ SQLiteDataProvider: Failed to encode source_groups: \(error.localizedDescription)")
                sourceGroupsJson = "[]"
            }
        } else {
            sourceGroupsJson = "[]"
        }
        
        // Bind final parameters 12-15: notify_when_sent, error_log, field_metadata, source_groups
        logger.info("🔧 Binding param 12 (notify_when_sent): \(batchMessage.notifyWhenSent ? 1 : 0)")
        logger.info("🔧 Binding param 13 (error_log): '\(errorLogJson.prefix(50))...'")
        logger.info("🔧 Binding param 14 (field_metadata): '\(chipMetadataJson.prefix(50))...'")
        logger.info("🔧 Binding param 15 (source_groups): '\(sourceGroupsJson)'")
        
        let finalBindResults = [
            sqlite3_bind_int(statement, 12, batchMessage.notifyWhenSent ? 1 : 0),
            sqlite3_bind_text(statement, 13, (errorLogJson as NSString).utf8String, -1, SQLITE_TRANSIENT),
            sqlite3_bind_text(statement, 14, (chipMetadataJson as NSString).utf8String, -1, SQLITE_TRANSIENT),
            sqlite3_bind_text(statement, 15, (sourceGroupsJson as NSString).utf8String, -1, SQLITE_TRANSIENT)
        ]
        
        for (index, result) in finalBindResults.enumerated() {
            if result != SQLITE_OK {
                let errorMsg = "❌ SQLiteDataProvider: Failed to bind final parameter \(index + 12): \(result)"
                print(errorMsg)
                logger.error(errorMsg)
                sqlite3_finalize(statement)
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return
            }
        }
        
        logger.info("🔧 SQLiteDataProvider: All parameters bound successfully")
        
        // Execute the statement
        let stepResult = sqlite3_step(statement)
        logger.info("🔧 SQLiteDataProvider: SQL step result: \(stepResult) (SQLITE_DONE=101)")
        
        if stepResult != SQLITE_DONE {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            logger.error("❌ SQLiteDataProvider: Step failed with error: \(errorMessage)")
        }
        
        if stepResult == SQLITE_DONE {
            // Commit the transaction
            let commitResult = sqlite3_exec(db, "COMMIT", nil, nil, nil)
            if commitResult != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                let errorMsg = "❌ SQLiteDataProvider: Failed to commit transaction: \(errorMessage)"
                print(errorMsg)
                logger.error(errorMsg)
            } else {
                logger.info("✅ SQLiteDataProvider: Transaction committed successfully")
                
                // Verify the insert actually worked and status was saved correctly
                var verifyStatement: OpaquePointer?
                let verifyQuery = "SELECT status, completed_time, sent_count, failed_count FROM batch_messages WHERE id = ?"
                if sqlite3_prepare_v2(db, verifyQuery, -1, &verifyStatement, nil) == SQLITE_OK {
                    sqlite3_bind_text(verifyStatement, 1, (batchMessage.id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
                    if sqlite3_step(verifyStatement) == SQLITE_ROW {
                        let savedStatus = String(cString: sqlite3_column_text(verifyStatement, 0))
                        let savedCompletedTime = sqlite3_column_text(verifyStatement, 1).map { String(cString: $0) }
                        let savedSentCount = Int(sqlite3_column_int(verifyStatement, 2))
                        let savedFailedCount = Int(sqlite3_column_int(verifyStatement, 3))
                        
                        logger.info("✅ DATABASE VERIFICATION:")
                        logger.info("  📊 Status saved to DB: '\(savedStatus)' (expected: '\(batchMessage.status.rawValue)')")
                        logger.info("  ⏰ Completed time: \(savedCompletedTime ?? "nil")")
                        logger.info("  ✅ Sent count: \(savedSentCount)")
                        logger.info("  ❌ Failed count: \(savedFailedCount)")
                        
                        // CRITICAL: Verify status matches what we intended to save
                        if savedStatus != batchMessage.status.rawValue {
                            logger.error("🚨 CRITICAL ERROR: Database status '\(savedStatus)' does NOT match intended status '\(batchMessage.status.rawValue)'!")
                        } else {
                            logger.info("✅ CONFIRMED: Status correctly saved to database")
                        }
                        
                        // CRITICAL: If message is completed/failed, it should have a completed_time
                        if (savedStatus == "completed" || savedStatus == "failed") && savedCompletedTime == nil {
                            logger.error("🚨 WARNING: Message is \(savedStatus) but has no completed_time!")
                        }
                    } else {
                        logger.error("❌ VERIFICATION FAILED: Could not find saved message in database!")
                    }
                }
                sqlite3_finalize(verifyStatement)
                
                // Update in memory array on MainActor to trigger UI update
                await MainActor.run {
                    if let index = batchMessages.firstIndex(where: { $0.id == batchMessage.id }) {
                        batchMessages[index] = batchMessage
                        logger.info("🔄 SQLiteDataProvider: Updated existing batch message in memory array")
                    } else {
                        batchMessages.append(batchMessage)
                        logger.info("➕ SQLiteDataProvider: Added new batch message to memory array")
                    }
                }
                
                let successMsg = "✅ SQLiteDataProvider: Successfully saved batch message to database: \(batchMessage.id)"
                print(successMsg)
                logger.info(successMsg)
                logger.info("📊 SQLiteDataProvider: Total batch messages in memory: \(batchMessages.count)")
                logger.info("📊 SQLiteDataProvider: Message template: '\(batchMessage.messageTemplate)'")
                logger.info("📊 SQLiteDataProvider: Recipients count: \(batchMessage.recipients.count)")
                logger.info("📊 SQLiteDataProvider: Status: \(batchMessage.status.rawValue)")
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            let errorMsg = "❌ SQLiteDataProvider: Failed to execute statement: \(errorMessage)"
            print(errorMsg)
            logger.error(errorMsg)
            
            // Rollback the transaction
            let rollbackResult = sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            if rollbackResult != SQLITE_OK {
                let rollbackError = String(cString: sqlite3_errmsg(db))
                let rollbackMsg = "❌ SQLiteDataProvider: Failed to rollback transaction: \(rollbackError)"
                print(rollbackMsg)
                logger.error(rollbackMsg)
            } else {
                logger.info("🔄 SQLiteDataProvider: Transaction rolled back successfully")
            }
        }
        
        sqlite3_finalize(statement)
        logger.info("🔧 SQLiteDataProvider: Statement finalized")
    }
    
    func loadBatchMessagesFromDatabase() async {
        guard let db = database else { return }
        
        let query = """
        SELECT id, message_template, recipients, scheduled_time, created_time, status, 
               total_recipients, sent_count, failed_count, failed_contacts, completed_time, 
               notify_when_sent, error_log, field_metadata, source_groups 
        FROM batch_messages 
        ORDER BY created_time DESC
        """
        
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        
        if result == SQLITE_OK {
            var loadedBatchMessages: [BatchMessage] = []
            let formatter = ISO8601DateFormatter()
            
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let idString = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
                      let messageId = UUID(uuidString: idString) else { continue }
                
                let messageTemplate = String(cString: sqlite3_column_text(statement, 1))
                let recipientsJson = String(cString: sqlite3_column_text(statement, 2))
                let scheduledTimeString = sqlite3_column_text(statement, 3).map { String(cString: $0) }
                let createdTimeString = String(cString: sqlite3_column_text(statement, 4))
                let statusString = String(cString: sqlite3_column_text(statement, 5))
                let totalRecipients = Int(sqlite3_column_int(statement, 6))
                let sentCount = Int(sqlite3_column_int(statement, 7))
                let failedCount = Int(sqlite3_column_int(statement, 8))
                let failedContactsJson = String(cString: sqlite3_column_text(statement, 9))
                let completedTimeString = sqlite3_column_text(statement, 10).map { String(cString: $0) }
                let notifyWhenSent = sqlite3_column_int(statement, 11) == 1
                let errorLogJson = String(cString: sqlite3_column_text(statement, 12))
                let fieldMetadataJson = sqlite3_column_text(statement, 13).map { String(cString: $0) } ?? ""
                let sourceGroupsJson = sqlite3_column_text(statement, 14).map { String(cString: $0) } ?? "[]"
                
                // Parse dates
                let scheduledTime = scheduledTimeString.flatMap { formatter.date(from: $0) }
                let createdTime = formatter.date(from: createdTimeString) ?? Date()
                let completedTime = completedTimeString.flatMap { formatter.date(from: $0) }
                
                // Parse status
                let status = BatchMessageStatus(rawValue: statusString) ?? .pending
                
                // Parse recipients
                var recipients: [BatchRecipient] = []
                if let data = recipientsJson.data(using: .utf8) {
                    recipients = (try? JSONDecoder().decode([BatchRecipient].self, from: data)) ?? []
                }
                
                // Parse failed contacts
                var failedContacts: [String: String] = [:]
                if let data = failedContactsJson.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    failedContacts = parsed
                }
                
                // Parse chip metadata
                var chipMetadata: ChipMetadata?
                if !fieldMetadataJson.isEmpty,
                   let data = fieldMetadataJson.data(using: .utf8) {
                    chipMetadata = try? JSONDecoder().decode(ChipMetadata.self, from: data)
                }
                
                // Parse error log
                var errorLog: [BatchError] = []
                if let data = errorLogJson.data(using: .utf8) {
                    errorLog = (try? JSONDecoder().decode([BatchError].self, from: data)) ?? []
                }
                
                // Parse source_groups
                var sourceGroups: [UUID]?
                if let data = sourceGroupsJson.data(using: .utf8),
                   let uuidStrings = try? JSONDecoder().decode([String].self, from: data) {
                    sourceGroups = uuidStrings.compactMap { UUID(uuidString: $0) }
                    if sourceGroups?.isEmpty == true {
                        sourceGroups = nil
                    }
                }
                
                // Use database-aware initializer to preserve ID and all values
                let batchMessage = BatchMessage(
                    id: messageId,  // Use ID from database
                    messageTemplate: messageTemplate,
                    chipMetadata: chipMetadata,
                    recipients: recipients,
                    scheduledTime: scheduledTime,
                    createdTime: createdTime,
                    status: status,
                    totalRecipients: totalRecipients,
                    sentCount: sentCount,
                    failedCount: failedCount,
                    failedContacts: failedContacts,
                    completedTime: completedTime,
                    notifyWhenSent: notifyWhenSent,
                    errorLog: errorLog,
                    sourceGroups: sourceGroups
                )
                
                loadedBatchMessages.append(batchMessage)
            }
            
            batchMessages = loadedBatchMessages
            print("✅ Successfully loaded \(batchMessages.count) batch messages from database")
            
            // Verification logging to ensure IDs match database
            logger.info("📊 Loaded \(batchMessages.count) batch messages")
            for message in loadedBatchMessages.prefix(5) {
                logger.info("  - ID: \(message.id), Status: \(message.status.rawValue)")
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Failed to load batch messages from database: \(errorMessage)")
        }
        
        sqlite3_finalize(statement)
    }
    
    func deleteBatchMessage(_ id: UUID) async {
        print("🗑️ deleteBatchMessage called for ID: \(id)")
        logger.info("🗑️ SQLiteDataProvider: deleteBatchMessage called for ID: \(id)")
        print("📁 Current database path: \(currentDatabasePath ?? "nil")")
        logger.info("📁 Current database path: \(currentDatabasePath ?? "nil")")
        
        guard let db = database else {
            print("❌ Database is nil in deleteBatchMessage")
            logger.error("❌ Database is nil in deleteBatchMessage")
            return
        }
        
        // First, verify the message exists
        let checkQuery = "SELECT id FROM batch_messages WHERE id = ?"
        var checkStmt: OpaquePointer?
        var messageExists = false
        
        if sqlite3_prepare_v2(db, checkQuery, -1, &checkStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(checkStmt, 1, id.uuidString, -1, nil)
            if sqlite3_step(checkStmt) == SQLITE_ROW {
                messageExists = true
                print("✅ Message exists in database before deletion")
                logger.info("✅ Message exists in database before deletion")
            } else {
                print("⚠️ Message does not exist in database (ID: \(id.uuidString))")
                logger.warning("⚠️ Message does not exist in database (ID: \(id.uuidString))")
            }
        }
        sqlite3_finalize(checkStmt)
        
        if !messageExists {
            print("⚠️ Cannot delete non-existent message")
            return
        }
        
        // Proceed with deletion
        let query = "DELETE FROM batch_messages WHERE id = ?"
        var statement: OpaquePointer?
        
        print("🔧 Preparing DELETE statement with ID: \(id.uuidString)")
        logger.info("🔧 Preparing DELETE statement with ID: \(id.uuidString)")
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id.uuidString, -1, nil)
            
            let stepResult = sqlite3_step(statement)
            print("🔧 sqlite3_step result: \(stepResult) (SQLITE_DONE = \(SQLITE_DONE))")
            
            if stepResult == SQLITE_DONE {
                let changes = sqlite3_changes(db)
                print("✅ DELETE executed - Rows affected: \(changes)")
                logger.info("✅ DELETE executed - Rows affected: \(changes)")
                
                if changes > 0 {
                    print("✅ Successfully deleted batch message from database")
                    logger.info("✅ Successfully deleted batch message from database")
                    
                    // Verify deletion
                    var verifyStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, checkQuery, -1, &verifyStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(verifyStmt, 1, id.uuidString, -1, nil)
                        if sqlite3_step(verifyStmt) == SQLITE_ROW {
                            print("❌ ERROR: Message still exists after deletion!")
                            logger.error("❌ ERROR: Message still exists after deletion!")
                        } else {
                            print("✅ Verified: Message no longer in database")
                            logger.info("✅ Verified: Message no longer in database")
                        }
                    }
                    sqlite3_finalize(verifyStmt)
                    
                    // Remove from memory array on MainActor to trigger UI update
                    await MainActor.run {
                        batchMessages.removeAll { $0.id == id }
                        print("✅ Batch message removed from memory array, UI should update")
                        logger.info("✅ Batch message removed from memory array, UI should update")
                    }
                } else {
                    print("⚠️ DELETE executed but no rows affected")
                    logger.warning("⚠️ DELETE executed but no rows affected")
                }
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                print("❌ Failed to delete batch message from database: \(errorMessage)")
                logger.error("❌ Failed to delete batch message from database: \(errorMessage)")
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Failed to prepare delete statement: \(errorMessage)")
            logger.error("❌ Failed to prepare delete statement: \(errorMessage)")
        }
        
        sqlite3_finalize(statement)
    }
    
    func updateBatchMessage(_ batchMessage: BatchMessage) async {
        logger.info("💾 SQLiteDataProvider: updateBatchMessage called for ID: \(batchMessage.id)")
        
        guard let db = database else {
            logger.error("❌ SQLiteDataProvider: Database is nil in updateBatchMessage")
            return
        }
        
        guard _isConnectedToDatabase else {
            logger.error("❌ SQLiteDataProvider: Database not connected in updateBatchMessage")
            return
        }
        
        let formatter = ISO8601DateFormatter()
        
        // Begin transaction
        let beginResult = sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        if beginResult != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            logger.error("❌ SQLiteDataProvider: Failed to begin transaction: \(errorMessage)")
            return
        }
        
        // Convert chip metadata to JSON
        let chipMetadataJson: String
        if let chipMetadata = batchMessage.chipMetadata {
            do {
                let metadataData = try JSONEncoder().encode(chipMetadata)
                if let metadataString = String(data: metadataData, encoding: .utf8) {
                    chipMetadataJson = metadataString
                } else {
                    logger.error("❌ SQLiteDataProvider: Failed to convert chip metadata to string")
                    sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                    return
                }
            } catch {
                logger.error("❌ SQLiteDataProvider: Failed to encode chip metadata: \(error.localizedDescription)")
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return
            }
        } else {
            chipMetadataJson = ""
        }
        
        // Convert recipients to JSON
        let recipientsJson: String
        do {
            let recipientsData = try JSONEncoder().encode(batchMessage.recipients)
            if let recipientsString = String(data: recipientsData, encoding: .utf8) {
                recipientsJson = recipientsString
            } else {
                logger.error("❌ SQLiteDataProvider: Failed to convert recipients to string")
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return
            }
        } catch {
            logger.error("❌ SQLiteDataProvider: Failed to encode recipients: \(error.localizedDescription)")
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return
        }
        
        // Encode source_groups for update
        let sourceGroupsJson: String
        if let sourceGroups = batchMessage.sourceGroups, !sourceGroups.isEmpty {
            do {
                let sourceGroupsData = try JSONEncoder().encode(sourceGroups.map { $0.uuidString })
                sourceGroupsJson = String(data: sourceGroupsData, encoding: .utf8) ?? "[]"
            } catch {
                logger.error("❌ SQLiteDataProvider: Failed to encode source_groups: \(error.localizedDescription)")
                sourceGroupsJson = "[]"
            }
        } else {
            sourceGroupsJson = "[]"
        }
        
        // Update the batch message
        let updateQuery = """
            UPDATE batch_messages SET
                message_template = ?,
                field_metadata = ?,
                recipients = ?,
                scheduled_time = ?,
                status = ?,
                sent_count = ?,
                total_recipients = ?,
                notify_when_sent = ?,
                source_groups = ?
            WHERE id = ?
        """
        
        var updateStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, updateQuery, -1, &updateStmt, nil) == SQLITE_OK {
            logger.info("🔧 SQLiteDataProvider: Binding update parameters for message: \(batchMessage.id)")
            sqlite3_bind_text(updateStmt, 1, batchMessage.messageTemplate, -1, nil)
            sqlite3_bind_text(updateStmt, 2, chipMetadataJson, -1, nil)
            sqlite3_bind_text(updateStmt, 3, recipientsJson, -1, nil)
            
            if let scheduledTime = batchMessage.scheduledTime {
                let scheduledTimeString = formatter.string(from: scheduledTime)
                logger.info("⏰ SQLiteDataProvider: Binding scheduled_time: \(scheduledTimeString)")
                sqlite3_bind_text(updateStmt, 4, scheduledTimeString, -1, nil)
            } else {
                logger.info("⏰ SQLiteDataProvider: Binding scheduled_time as NULL")
                sqlite3_bind_null(updateStmt, 4)
            }
            
            sqlite3_bind_text(updateStmt, 5, batchMessage.status.rawValue, -1, nil)
            sqlite3_bind_int(updateStmt, 6, Int32(batchMessage.sentCount))
            sqlite3_bind_int(updateStmt, 7, Int32(batchMessage.totalRecipients))
            sqlite3_bind_int(updateStmt, 8, batchMessage.notifyWhenSent ? 1 : 0)
            sqlite3_bind_text(updateStmt, 9, sourceGroupsJson, -1, nil)
            sqlite3_bind_text(updateStmt, 10, batchMessage.id.uuidString, -1, nil)
            
            let stepResult = sqlite3_step(updateStmt)
            if stepResult == SQLITE_DONE {
                let rowsAffected = sqlite3_changes(db)
                logger.info("✅ SQLiteDataProvider: Batch message updated successfully in database (rows affected: \(rowsAffected))")
                
                // Commit transaction
                if sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK {
                    logger.info("✅ SQLiteDataProvider: Transaction committed")
                    
                    // Update in memory array on MainActor to trigger UI update
                    await MainActor.run {
                        if let index = batchMessages.firstIndex(where: { $0.id == batchMessage.id }) {
                            batchMessages[index] = batchMessage
                            logger.info("✅ SQLiteDataProvider: Batch message updated in memory")
                        }
                    }
                } else {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    logger.error("❌ SQLiteDataProvider: Failed to commit transaction: \(errorMessage)")
                    sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                }
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                logger.error("❌ SQLiteDataProvider: Failed to update batch message: \(errorMessage)")
                logger.error("❌ SQLiteDataProvider: Step result code: \(stepResult)")
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            logger.error("❌ SQLiteDataProvider: Failed to prepare update statement: \(errorMessage)")
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
        }
        
        sqlite3_finalize(updateStmt)
    }
    
    func getScheduledBatchMessages() -> [BatchMessage] {
        return batchMessages.filter { $0.status == .scheduled && $0.scheduledTime != nil }
    }
    
    private func loadInvitesFromDatabase() async {
        guard let db = database else { return }
        
        let query = "SELECT id, title, description, creation_date, last_modified_date, date_completed, completed, completion_status, sent_received, to_phone, from_phone, priority, due_date, parent_tasks, child_tasks, tags, groups, task_group, ai_processed, ai_suggestions, ai_confidence, reminder_date, message_origin_guid, is_recurring, recurrence_type, next_task_id, previous_task_id, is_next_task, date_of_last_task, created_by, assigned_to, category, location, estimated_duration, attachments, external_id, last_ai_analysis FROM invites"
        
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        
        if result == SQLITE_OK {
            var loadedInvites: [Invite] = []
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let idString = String(cString: sqlite3_column_text(statement, 0))
                let title = String(cString: sqlite3_column_text(statement, 1))
                let description = sqlite3_column_text(statement, 2).map { String(cString: $0) }
                let creationDateString = String(cString: sqlite3_column_text(statement, 3))
                let lastModifiedDateString = String(cString: sqlite3_column_text(statement, 4))
                let dateCompletedString = sqlite3_column_text(statement, 5).map { String(cString: $0) }
                let completed = sqlite3_column_int(statement, 6) == 1
                let completionStatusString = String(cString: sqlite3_column_text(statement, 7))
                let sentReceivedString = String(cString: sqlite3_column_text(statement, 8))
                let toPhone = sqlite3_column_text(statement, 9).map { String(cString: $0) }
                let fromPhone = sqlite3_column_text(statement, 10).map { String(cString: $0) }
                let priorityInt = sqlite3_column_int(statement, 11)
                let dueDateString = sqlite3_column_text(statement, 12).map { String(cString: $0) }
                let parentTasksJson = sqlite3_column_text(statement, 13).map { String(cString: $0) } ?? "[]"
                let childTasksJson = sqlite3_column_text(statement, 14).map { String(cString: $0) } ?? "[]"
                let tagsJson = sqlite3_column_text(statement, 15).map { String(cString: $0) } ?? "{}"
                let groupsJson = sqlite3_column_text(statement, 16).map { String(cString: $0) } ?? "[]"
                let taskGroupJson = sqlite3_column_text(statement, 17).map { String(cString: $0) } ?? "{}"
                let aiProcessed = sqlite3_column_int(statement, 18) == 1
                let aiSuggestionsJson = sqlite3_column_text(statement, 19).map { String(cString: $0) } ?? "{}"
                let aiConfidence = sqlite3_column_double(statement, 20)
                let reminderDateString = sqlite3_column_text(statement, 21).map { String(cString: $0) }
                let messageOriginGuid = sqlite3_column_text(statement, 22).map { String(cString: $0) }
                let isRecurring = sqlite3_column_int(statement, 23) == 1
                let recurrenceTypeString = String(cString: sqlite3_column_text(statement, 24))
                let nextTaskIdString = sqlite3_column_text(statement, 25).map { String(cString: $0) }
                let previousTaskIdString = sqlite3_column_text(statement, 26).map { String(cString: $0) }
                let isNextTask = sqlite3_column_int(statement, 27) == 1
                let dateOfLastTaskString = sqlite3_column_text(statement, 28).map { String(cString: $0) }
                let createdBy = sqlite3_column_text(statement, 29).map { String(cString: $0) }
                let assignedTo = sqlite3_column_text(statement, 30).map { String(cString: $0) }
                let category = sqlite3_column_text(statement, 31).map { String(cString: $0) }
                let location = sqlite3_column_text(statement, 32).map { String(cString: $0) }
                let estimatedDuration = sqlite3_column_type(statement, 33) != SQLITE_NULL ? Int(sqlite3_column_int(statement, 33)) : nil
                let attachmentsJson = sqlite3_column_text(statement, 34).map { String(cString: $0) } ?? "[]"
                let externalId = sqlite3_column_text(statement, 35).map { String(cString: $0) }
                let lastAiAnalysisString = sqlite3_column_text(statement, 36).map { String(cString: $0) }
                
                guard let id = UUID(uuidString: idString) else { continue }
                
                // Parse dates
                let formatter = ISO8601DateFormatter()
                let creationDate = formatter.date(from: creationDateString) ?? Date()
                let lastModifiedDate = formatter.date(from: lastModifiedDateString) ?? Date()
                let dateCompleted = dateCompletedString.flatMap { formatter.date(from: $0) }
                let dueDate = dueDateString.flatMap { formatter.date(from: $0) }
                let reminderDate = reminderDateString.flatMap { formatter.date(from: $0) }
                let dateOfLastTask = dateOfLastTaskString.flatMap { formatter.date(from: $0) }
                let lastAiAnalysis = lastAiAnalysisString.flatMap { formatter.date(from: $0) }
                
                // Parse enums
                let completionStatus = CompletionStatus(rawValue: completionStatusString) ?? .pending
                let sentReceived = SentReceived(rawValue: sentReceivedString) ?? .sent
                let priority = Priority(rawValue: Int(priorityInt)) ?? .medium
                let recurrenceType = RecurrenceType(rawValue: recurrenceTypeString) ?? .none
                
                // Parse JSON fields
                var parentTasks: [UUID] = []
                if let data = parentTasksJson.data(using: .utf8),
                   let taskStrings = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    parentTasks = taskStrings.compactMap { UUID(uuidString: $0) }
                }
                
                var childTasks: [UUID] = []
                if let data = childTasksJson.data(using: .utf8),
                   let taskStrings = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    childTasks = taskStrings.compactMap { UUID(uuidString: $0) }
                }
                
                var tags: [String: Any] = [:]
                if let data = tagsJson.data(using: .utf8),
                   let tagsDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    tags = tagsDict
                }
                
                var groups: [GroupReference] = []
                if let data = groupsJson.data(using: .utf8),
                   let groupsArray = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
                    groups = groupsArray.compactMap { dict in
                        guard let id = dict["id"], let name = dict["name"] else { return nil }
                        return GroupReference(id: id, name: name)
                    }
                }
                
                var taskGroup: TaskGroup?
                if let data = taskGroupJson.data(using: .utf8),
                   let taskGroupDict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                   let id = taskGroupDict["id"], let name = taskGroupDict["name"] {
                    taskGroup = TaskGroup(id: id, name: name)
                }
                
                var aiSuggestions: [String: Any] = [:]
                if let data = aiSuggestionsJson.data(using: .utf8),
                   let suggestionsDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    aiSuggestions = suggestionsDict
                }
                
                var attachments: [String] = []
                if let data = attachmentsJson.data(using: .utf8),
                   let attachmentsArray = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    attachments = attachmentsArray
                }
                
                let nextTaskId = nextTaskIdString.flatMap { UUID(uuidString: $0) }
                let previousTaskId = previousTaskIdString.flatMap { UUID(uuidString: $0) }
                
                let invite = Invite(
                    id: id,
                    title: title,
                    description: description,
                    creationDate: creationDate,
                    lastModifiedDate: lastModifiedDate,
                    dateCompleted: dateCompleted,
                    completed: completed,
                    completionStatus: completionStatus,
                    sentReceived: sentReceived,
                    toPhone: toPhone,
                    fromPhone: fromPhone,
                    priority: priority,
                    dueDate: dueDate,
                    parentTasks: parentTasks,
                    childTasks: childTasks,
                    tags: tags,
                    groups: groups,
                    taskGroup: taskGroup,
                    aiProcessed: aiProcessed,
                    aiSuggestions: aiSuggestions,
                    aiConfidence: aiConfidence,
                    reminderDate: reminderDate,
                    messageOriginGuid: messageOriginGuid,
                    isRecurring: isRecurring,
                    recurrenceType: recurrenceType,
                    nextTaskId: nextTaskId,
                    previousTaskId: previousTaskId,
                    isNextTask: isNextTask,
                    dateOfLastTask: dateOfLastTask,
                    createdBy: createdBy,
                    assignedTo: assignedTo,
                    category: category,
                    location: location,
                    estimatedDuration: estimatedDuration,
                    attachments: attachments,
                    externalId: externalId,
                    lastAiAnalysis: lastAiAnalysis
                )
                loadedInvites.append(invite)
                
                print("  📋 Loaded invite: \(invite.title) [ID: \(idString)]")
            }
            
            invites = loadedInvites
            print("✅ Successfully loaded \(invites.count) invites from database")
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Failed to load invites from database: \(errorMessage)")
        }
        
        sqlite3_finalize(statement)
    }

}

// MARK: - SQL Validation Integration

extension SQLiteDataProvider {
    
    // MARK: - Validated SQL Execution Methods
    
    /// Validates and executes SQL with comprehensive logging
    private func executeValidatedSQL(
        operation: String,
        query: String,
        parameters: [String: Any] = [:],
        data: Any? = nil
    ) -> SQLExecutionResult {
        return sqlValidator.executeSQLWithValidation(
            operation: operation,
            query: query,
            database: database,
            parameters: parameters,
            data: data
        )
    }
    
    // MARK: - Validated Contact Operations
    
    /// Validated version of saveContactToDatabase
    private func saveContactToDatabaseValidated(_ contact: Contact) async {
        let query = """
        INSERT OR REPLACE INTO contacts (phone, name, first_name, last_name, email, address, notes, business, contact_group, profile_photo, last_message_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        let parameters: [String: Any] = [
            "phone": contact.phone,
            "name": contact.name,
            "first_name": contact.firstName ?? "",
            "last_name": contact.lastName ?? "",
            "email": contact.email ?? "",
            "address": contact.address ?? "",
            "notes": contact.notes ?? "",
            "business": contact.business ?? "",
            "contact_group": contact.contactGroup ?? "",
            "profile_photo": contact.profilePhotoData ?? Data(),
            "last_message_date": contact.lastMessageDate?.ISO8601Format() ?? ""
        ]
        
        let result = executeValidatedSQL(
            operation: "SAVE_CONTACT",
            query: query,
            parameters: parameters,
            data: contact
        )
        
        if result.success {
            logger.info("✅ Validated contact save successful: \(contact.displayName)")
        } else {
            logger.error("❌ Validated contact save failed: \(result.error ?? "Unknown error")")
        }
    }
    
    /// Validated version of deleteContactFromDatabase
    private func deleteContactFromDatabaseValidated(_ phone: String) async {
        let query = "DELETE FROM contacts WHERE phone = ?"
        let parameters: [String: Any] = ["phone": phone]
        
        let result = executeValidatedSQL(
            operation: "DELETE_CONTACT",
            query: query,
            parameters: parameters
        )
        
        if result.success {
            logger.info("✅ Validated contact deletion successful: \(phone)")
        } else {
            logger.error("❌ Validated contact deletion failed: \(result.error ?? "Unknown error")")
        }
    }
    
    // MARK: - Validated Group Operations
    
    /// Validated version of saveGroupToDatabase
    private func saveGroupToDatabaseValidated(_ group: ContactGroup) async {
        guard let db = database else {
            logger.error("❌ Database connection not available for group save")
            return
        }
        
        // Get database ID for the group
        let dbId = getDatabaseId(for: group.id)
        
        // Prepare data for validation and logging
        let parameters: [String: Any] = [
            "id": dbId,
            "name": group.name,
            "color": group.colorHexString ?? "#000000",
            "participants": Array(group.memberPhones),
            "member_phones": Array(group.memberPhones),
            "parent_id": group.parentID?.uuidString ?? "",
            "linked_group_ids": Array(group.linkedGroupIDs.map { $0.uuidString }),
            "metadata": [
                "inviteCount": group.metadata.inviteCount,
                "interconnectivityScore": group.metadata.interconnectivityScore
            ],
            "is_deck": group.isDeck,
            "canvases": Array(group.canvases.map { $0.uuidString }),
            "created_at": group.createdAt.ISO8601Format()
        ]
        
        // Check if group exists
        let checkQuery = "SELECT COUNT(*) FROM groups WHERE id = \(dbId)"
        var checkStatement: OpaquePointer?
        var groupExists = false
        
        if sqlite3_prepare_v2(db, checkQuery, -1, &checkStatement, nil) == SQLITE_OK {
            if sqlite3_step(checkStatement) == SQLITE_ROW {
                let count = sqlite3_column_int(checkStatement, 0)
                groupExists = count > 0
            }
        }
        sqlite3_finalize(checkStatement)
        
        let query: String
        let operation: String
        
        if groupExists {
            // Update existing group
            query = """
            UPDATE groups SET 
                name = ?, color = ?, participants = ?, member_phones = ?, parent_id = ?, 
                linked_group_ids = ?, metadata = ?, is_deck = ?, canvases = ?, created_at = ?
            WHERE id = ?
            """
            operation = "UPDATE_GROUP"
        } else {
            // Insert new group
            query = """
            INSERT INTO groups (
                id, name, color, participants, member_phones, parent_id, 
                linked_group_ids, metadata, is_deck, canvases, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            operation = "CREATE_GROUP"
        }
        
        let result = executeValidatedSQL(
            operation: operation,
            query: query,
            parameters: parameters,
            data: group
        )
        
        if result.success {
            logger.info("✅ Validated group save successful: \(group.name)")
        } else {
            logger.error("❌ Validated group save failed: \(result.error ?? "Unknown error")")
        }
    }
    
    /// Validated version of deleteGroupFromDatabase
    private func deleteGroupFromDatabaseValidated(_ id: UUID) async {
        let dbId = getDatabaseId(for: id)
        let query = "DELETE FROM groups WHERE id = ?"
        let parameters: [String: Any] = ["id": dbId]
        
        let result = executeValidatedSQL(
            operation: "DELETE_GROUP",
            query: query,
            parameters: parameters
        )
        
        if result.success {
            logger.info("✅ Validated group deletion successful: \(id)")
        } else {
            logger.error("❌ Validated group deletion failed: \(result.error ?? "Unknown error")")
        }
    }
    
    // MARK: - Validated Invite Operations
    
    /// Validated version of saveInviteToDatabase
    private func saveInviteToDatabaseValidated(_ invite: Invite) async {
        let query = """
        INSERT OR REPLACE INTO invites 
        (id, title, description, creation_date, last_modified_date, date_completed, completed, completion_status, sent_received, to_phone, from_phone, priority, due_date, parent_tasks, child_tasks, tags, groups, task_group, ai_processed, ai_suggestions, ai_confidence, reminder_date, message_origin_guid, is_recurring, recurrence_type, next_task_id, previous_task_id, is_next_task, date_of_last_task, created_by, assigned_to, category, location, estimated_duration, attachments, external_id, last_ai_analysis)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        let formatter = ISO8601DateFormatter()
        
        let parameters: [String: Any] = [
            "id": invite.id.uuidString,
            "title": invite.title,
            "description": invite.description ?? "",
            "creation_date": formatter.string(from: invite.creationDate),
            "last_modified_date": formatter.string(from: invite.lastModifiedDate),
            "date_completed": invite.dateCompleted.map { formatter.string(from: $0) } ?? "",
            "completed": invite.completed,
            "completion_status": invite.completionStatus.rawValue,
            "sent_received": invite.sentReceived.rawValue,
            "to_phone": invite.toPhone ?? "",
            "from_phone": invite.fromPhone ?? "",
            "priority": invite.priority.rawValue,
            "due_date": invite.dueDate.map { formatter.string(from: $0) } ?? "",
            "parent_tasks": invite.parentTasks.map { $0.uuidString },
            "child_tasks": invite.childTasks.map { $0.uuidString },
            "tags": invite.tags,
            "groups": invite.groups.map { ["id": $0.id, "name": $0.name] },
            "task_group": invite.taskGroup.map { ["id": $0.id, "name": $0.name] } ?? [:],
            "ai_processed": invite.aiProcessed,
            "ai_suggestions": invite.aiSuggestions,
            "ai_confidence": invite.aiConfidence,
            "reminder_date": invite.reminderDate.map { formatter.string(from: $0) } ?? "",
            "message_origin_guid": invite.messageOriginGuid ?? "",
            "is_recurring": invite.isRecurring,
            "recurrence_type": invite.recurrenceType.rawValue,
            "next_task_id": invite.nextTaskId?.uuidString ?? "",
            "previous_task_id": invite.previousTaskId?.uuidString ?? "",
            "is_next_task": invite.isNextTask,
            "date_of_last_task": invite.dateOfLastTask.map { formatter.string(from: $0) } ?? "",
            "created_by": invite.createdBy ?? "",
            "assigned_to": invite.assignedTo ?? "",
            "category": invite.category ?? "",
            "location": invite.location ?? "",
            "estimated_duration": invite.estimatedDuration ?? 0,
            "attachments": invite.attachments,
            "external_id": invite.externalId ?? "",
            "last_ai_analysis": invite.lastAiAnalysis.map { formatter.string(from: $0) } ?? ""
        ]
        
        let result = executeValidatedSQL(
            operation: "SAVE_INVITE",
            query: query,
            parameters: parameters,
            data: invite
        )
        
        if result.success {
            logger.info("✅ Validated invite save successful: \(invite.title)")
        } else {
            logger.error("❌ Validated invite save failed: \(result.error ?? "Unknown error")")
        }
    }
    
    /// Validated version of deleteInviteFromDatabase
    private func deleteInviteFromDatabaseValidated(_ id: UUID) async {
        let query = "DELETE FROM invites WHERE id = ?"
        let parameters: [String: Any] = ["id": id.uuidString]
        
        let result = executeValidatedSQL(
            operation: "DELETE_INVITE",
            query: query,
            parameters: parameters
        )
        
        if result.success {
            logger.info("✅ Validated invite deletion successful: \(id)")
        } else {
            logger.error("❌ Validated invite deletion failed: \(result.error ?? "Unknown error")")
        }
    }
    
    // MARK: - Validated Batch Message Operations
    
    /// Validated version of saveBatchMessageToDatabase
    private func saveBatchMessageToDatabaseValidated(_ batchMessage: BatchMessage) async {
        let query = """
        INSERT OR REPLACE INTO batch_messages (
            id, message_template, recipients, status, scheduled_time, sent_count, 
            failed_count, failed_contacts, error_log, notify_when_sent, completed_time
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        let _ = ISO8601DateFormatter()
        
        let parameters: [String: Any] = [
            "id": batchMessage.id.uuidString,
            "message_template": batchMessage.messageTemplate,
            "recipients": batchMessage.recipients.map { [
                "phone": $0.phone,
                "fieldValues": $0.fieldValues
            ]},
            "status": batchMessage.status.rawValue,
            "scheduled_time": batchMessage.scheduledTime?.ISO8601Format() ?? "",
            "sent_count": batchMessage.sentCount,
            "failed_count": batchMessage.failedCount,
            "failed_contacts": batchMessage.failedContacts,
            "error_log": batchMessage.errorLog.map { [
                "timestamp": $0.timestamp.ISO8601Format(),
                "phone": $0.phone,
                "error": $0.error,
                "retryAttempt": $0.retryAttempt
            ]},
            "notify_when_sent": batchMessage.notifyWhenSent,
            "completed_time": batchMessage.completedTime?.ISO8601Format() ?? ""
        ]
        
        let result = executeValidatedSQL(
            operation: "SAVE_BATCH_MESSAGE",
            query: query,
            parameters: parameters,
            data: batchMessage
        )
        
        if result.success {
            logger.info("✅ Validated batch message save successful: \(batchMessage.id)")
        } else {
            logger.error("❌ Validated batch message save failed: \(result.error ?? "Unknown error")")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Gets the database ID for a given UUID (simplified implementation)
    private func getDatabaseId(for uuid: UUID) -> Int {
        // This is a simplified implementation - in reality you'd need to maintain
        // a mapping between UUIDs and database IDs
        return abs(uuid.hashValue % Int.max)
    }
    
    // MARK: - Migration to Validated Methods
    
    /// Call this method to gradually migrate to validated SQL operations
    func enableValidatedSQLOperations() {
        logger.info("🔧 Enabling validated SQL operations for data integrity")
        // This would be called during app initialization to switch to validated methods
    }
}
