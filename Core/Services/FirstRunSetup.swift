import Foundation
import SQLite3
import GRDB

enum FirstRunSetup {
    static func run() {
        ensureAppSupportDirectory()
        migrateOldSettings()
        ensureSettingsFile()
        ensureDatabase()
    }
    
    private static func migrateOldSettings() {
        SettingsMigration.migrateIfNeeded()
    }

    private static func ensureAppSupportDirectory() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let myCRM = appSupport.appendingPathComponent("My_CRM")
        do {
            try FileManager.default.createDirectory(at: myCRM, withIntermediateDirectories: true)
        } catch {
            print("❌ FirstRunSetup: Failed to create App Support directory: \(error)")
        }
    }

    private static func ensureSettingsFile() {
        _ = SettingsManager.shared // init will auto-create settings if missing
    }

    private static func ensureDatabase() {
        let settingsManager = SettingsManager.shared
        var databaseURL = URL(fileURLWithPath: settingsManager.settings.database.path)
        
        // Relocate the database if the configured path is in a cloud-synced or unsafe location
        databaseURL = relocateDatabaseIfNeeded(currentURL: databaseURL, settingsManager: settingsManager)
        
        do {
            try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            print("✅ FirstRunSetup: Database directory ready at: \(databaseURL.deletingLastPathComponent().path)")
        } catch {
            print("❌ FirstRunSetup: Failed to create DB directory: \(error)")
            print("📢 User will need to manually select database location in Settings")
            return
        }

        if !FileManager.default.fileExists(atPath: databaseURL.path) {
            print("📝 FirstRunSetup: Creating new database at: \(databaseURL.path)")
            createEmptyDatabase(at: databaseURL)
        } else {
            print("✅ FirstRunSetup: Existing database found at: \(databaseURL.path)")
        }

        runBootstrapMigrations(at: databaseURL)
    }
    
    private static func defaultDatabaseURL() -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/My_CRM/my_crm.db")
        }
        return appSupport.appendingPathComponent("My_CRM").appendingPathComponent("my_crm.db")
    }
    
    private static func relocateDatabaseIfNeeded(currentURL: URL, settingsManager: SettingsManager) -> URL {
        let targetURL = defaultDatabaseURL()
        
        if isLocationSafe(currentURL) {
            return currentURL
        }
        
        if currentURL == targetURL {
            return currentURL
        }
        
        print("⚠️ FirstRunSetup: Database path appears to be cloud-synced or unsafe (\(currentURL.path)). Relocating to Application Support…")
        
        do {
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            print("❌ FirstRunSetup: Failed to prepare destination directory: \(error)")
            return currentURL
        }
        
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: currentURL.path) {
            do {
                if fileManager.fileExists(atPath: targetURL.path) {
                    print("ℹ️ FirstRunSetup: Destination database already exists. Keeping existing file at \(targetURL.path)")
                } else {
                    try fileManager.moveItem(at: currentURL, to: targetURL)
                    try moveSidecarIfPresent(fromPath: currentURL.path + "-wal", toPath: targetURL.path + "-wal")
                    try moveSidecarIfPresent(fromPath: currentURL.path + "-shm", toPath: targetURL.path + "-shm")
                    print("✅ FirstRunSetup: Database moved to \(targetURL.path)")
                }
            } catch {
                print("❌ FirstRunSetup: Failed to move database to safe location: \(error)")
                print("💡 Please move the database manually to \(targetURL.path)")
                return currentURL
            }
        }
        
        settingsManager.updateDatabasePath(targetURL.path)
        return targetURL
    }
    
    private static func moveSidecarIfPresent(fromPath sourcePath: String, toPath destinationPath: String) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: sourcePath) && !fileManager.fileExists(atPath: destinationPath) {
            try fileManager.moveItem(atPath: sourcePath, toPath: destinationPath)
        }
    }
    
    private static func isLocationSafe(_ url: URL) -> Bool {
        let path = url.path
        if path.isEmpty { return false }
        
        // Avoid locations that are commonly cloud-synced
        if path.contains("Library/Mobile Documents") { return false }
        if path.contains("Dropbox") { return false }
        if path.contains("OneDrive") { return false }
        if path.contains("Google Drive") || path.contains("GoogleDrive") { return false }
        
        // Detect ubiquitous (iCloud) files
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]),
           values.isUbiquitousItem == true {
            return false
        }
        
        if let parentValues = try? url.deletingLastPathComponent().resourceValues(forKeys: [.isUbiquitousItemKey]),
           parentValues.isUbiquitousItem == true {
            return false
        }
        
        return true
    }
    
    private static func createEmptyDatabase(at url: URL) {
        var db: OpaquePointer?
        if sqlite3_open(url.path, &db) == SQLITE_OK {
            sqlite3_close(db)
            print("✅ FirstRunSetup: New database created successfully")
        } else {
            print("❌ FirstRunSetup: Failed to create database file")
        }
    }
    
    private static func runBootstrapMigrations(at url: URL) {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA journal_mode=WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        
        do {
            let dbQueue = try DatabaseQueue(path: url.path, configuration: configuration)
            defer { try? dbQueue.close() }
            
            var migrator = DatabaseMigrator()
            DatabaseMigrations.registerMigrations(on: &migrator)
            try migrator.migrate(dbQueue)
            print("✅ FirstRunSetup: Database migrations executed")
        } catch {
            print("❌ FirstRunSetup: Failed to run database migrations: \(error)")
        }
    }
}

