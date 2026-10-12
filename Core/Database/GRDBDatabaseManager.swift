import Foundation
import GRDB

/// Centralized database manager using GRDB for improved concurrency and performance
@MainActor
class GRDBDatabaseManager {
    static let shared = GRDBDatabaseManager()
    
    private var dbPool: DatabasePool?
    private let logger = LogManager.shared
    
    /// Current database path
    private(set) var currentDatabasePath: String?
    
    /// Check if database is connected
    var isConnected: Bool {
        return dbPool != nil
    }
    
    private init() {}
    
    // MARK: - Database Setup
    
    /// Open or create database at specified path
    func connect(to path: String) async throws {
        logger.info("📊 GRDBDatabaseManager: Connecting to database at: \(path)")
        
        // Close existing connection if any
        if dbPool != nil {
            try await disconnect()
        }
        
        // Ensure directory exists
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            logger.info("✅ Created database directory: \(directory.path)")
        }
        
        // Configure database pool
        var configuration = Configuration()
        configuration.busyMode = .timeout(30.0)  // Set busy timeout (30 seconds)
        configuration.prepareDatabase { db in
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            
            // Set synchronous mode to NORMAL for better performance with WAL
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        
        // Create database pool with connection pooling
        // - Multiple concurrent readers (default: 5)
        // - Single writer queue
        // - Automatic WAL mode for best concurrency
        do {
            let pool = try DatabasePool(path: path, configuration: configuration)
            self.dbPool = pool
            self.currentDatabasePath = path
            
            logger.info("✅ GRDBDatabaseManager: Successfully connected to database")
            logger.info("📊 Database using WAL mode for optimal concurrency")
            
            // Run migrations
            try await runMigrations()
            
            NotificationCenter.default.post(
                name: .grdbDatabaseDidConnect,
                object: self,
                userInfo: ["path": path]
            )
            
        } catch {
            logger.error("❌ GRDBDatabaseManager: Failed to connect: \(error.localizedDescription)")
            throw DatabaseError(message: "Failed to connect to database: \(error.localizedDescription)")
        }
    }
    
    /// Disconnect from database
    func disconnect() async throws {
        guard let pool = dbPool else { return }
        let previousPath = currentDatabasePath
        
        logger.info("🔌 GRDBDatabaseManager: Disconnecting from database")
        
        // Checkpoint WAL to ensure all changes are written
        try await pool.write { db in
            try db.checkpoint(.passive)
        }
        
        dbPool = nil
        currentDatabasePath = nil
        
        logger.info("✅ GRDBDatabaseManager: Disconnected from database")
        
        NotificationCenter.default.post(
            name: .grdbDatabaseDidDisconnect,
            object: self,
            userInfo: ["path": previousPath as Any]
        )
    }
    
    // MARK: - Database Access
    
    /// Read from database (concurrent reads allowed)
    func read<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        guard let pool = dbPool else {
            throw DatabaseError(message: "Database not connected")
        }
        
        return try await pool.read { db in
            try block(db)
        }
    }
    
    /// Write to database (serialized writes)
    func write<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        guard let pool = dbPool else {
            throw DatabaseError(message: "Database not connected")
        }
        
        return try await pool.write { db in
            try block(db)
        }
    }
    
    /// Write to database without returning value
    func write(_ block: @escaping (Database) throws -> Void) async throws {
        guard let pool = dbPool else {
            throw DatabaseError(message: "Database not connected")
        }
        
        try await pool.write { db in
            try block(db)
        }
    }
    
    /// Execute multiple operations in a transaction
    /// Automatically rolls back if any operation fails
    func transaction<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        guard let pool = dbPool else {
            throw DatabaseError(message: "Database not connected")
        }
        
        return try await pool.write { db in
            var result: T!
            try db.inTransaction {
                result = try block(db)
                return .commit
            }
            return result
        }
    }
    
    // MARK: - Migrations
    
    private func runMigrations() async throws {
        guard let pool = dbPool else {
            throw DatabaseError(message: "Database not connected")
        }
        
        logger.info("🔄 Running database migrations...")
        
        var migrator = DatabaseMigrator()
        
        // Register all migrations
        DatabaseMigrations.registerMigrations(on: &migrator)
        
        // Run migrations (migrator.migrate needs a DatabaseWriter, not Database)
        try migrator.migrate(pool)
        
        logger.info("✅ Database migrations completed")
    }
    
    // MARK: - Utility Methods
    
    /// Check database integrity
    func checkIntegrity() async throws -> Bool {
        return try await read { db in
            let result = try String.fetchOne(db, sql: "PRAGMA integrity_check")
            return result == "ok"
        }
    }
    
    /// Get database file size
    func getDatabaseSize() -> Int64? {
        guard let path = currentDatabasePath else { return nil }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return attributes[.size] as? Int64
        } catch {
            logger.error("❌ Failed to get database size: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Vacuum database (compress and optimize)
    func vacuum() async throws {
        try await write { db in
            try db.execute(sql: "VACUUM")
        }
        logger.info("✅ Database vacuumed successfully")
    }
    
    /// Checkpoint WAL file
    func checkpoint() async throws {
        try await write { db in
            try db.checkpoint(.passive)
        }
        logger.info("✅ WAL checkpoint completed")
    }
    
    /// Get database statistics
    func getStatistics() async throws -> DatabaseStatistics {
        return try await read { [self] db in
            let contactCount = try Contact.fetchCount(db)
            let groupCount = try ContactGroup.fetchCount(db)
            let inviteCount = try Invite.fetchCount(db)
            let messageCount = try Message.fetchCount(db)
            
            return DatabaseStatistics(
                contactCount: contactCount,
                groupCount: groupCount,
                inviteCount: inviteCount,
                messageCount: messageCount,
                databaseSize: self.getDatabaseSize() ?? 0
            )
        }
    }
}

// MARK: - Supporting Types

struct DatabaseError: Error, LocalizedError {
    let message: String
    
    var errorDescription: String? {
        return message
    }
}

struct DatabaseStatistics {
    let contactCount: Int
    let groupCount: Int
    let inviteCount: Int
    let messageCount: Int
    let databaseSize: Int64
    
    var databaseSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: databaseSize)
    }
}

// MARK: - Value Observation Support

extension GRDBDatabaseManager {
    /// Create a value observation for reactive queries
    /// This automatically updates when the database changes
    func observe<Reducer: ValueReducer>(_ observation: ValueObservation<Reducer>) -> AsyncThrowingStream<Reducer.Value, Error> {
        guard let pool = dbPool else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: DatabaseError(message: "Database not connected"))
            }
        }
        
        return AsyncThrowingStream { continuation in
            let cancellable = observation.start(
                in: pool,
                scheduling: .immediate,
                onError: { error in
                    continuation.finish(throwing: error)
                },
                onChange: { value in
                    continuation.yield(value)
                }
            )
            
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}

// MARK: - Connection Notifications

extension Notification.Name {
    static let grdbDatabaseDidConnect = Notification.Name("GRDBDatabaseManagerDidConnect")
    static let grdbDatabaseDidDisconnect = Notification.Name("GRDBDatabaseManagerDidDisconnect")
}

