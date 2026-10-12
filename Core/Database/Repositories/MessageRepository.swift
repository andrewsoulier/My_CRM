import Foundation
import GRDB

/// Repository for Message database operations using GRDB
@MainActor
class MessageRepository {
    private let dbManager: GRDBDatabaseManager
    private let logger = LogManager.shared
    
    init(dbManager: GRDBDatabaseManager? = nil) {
        self.dbManager = dbManager ?? GRDBDatabaseManager.shared
    }
    
    // MARK: - Create
    
    /// Insert a new message
    func insert(_ message: Message) async throws {
        try await dbManager.write { db in
            try message.insert(db)
        }
        logger.info("✅ Inserted message: \(message.guid)")
    }
    
    /// Insert multiple messages in a transaction
    func insertAll(_ messages: [Message]) async throws {
        try await dbManager.transaction { db in
            for message in messages {
                try message.insert(db)
            }
            return ()
        }
        logger.info("✅ Inserted \(messages.count) messages")
    }
    
    /// Upsert message (insert or ignore if exists)
    func upsert(_ message: Message) async throws {
        try await dbManager.write { db in
            try message.save(db)
        }
    }
    
    // MARK: - Read
    
    /// Fetch message by GUID
    func fetchOne(guid: String) async throws -> Message? {
        return try await dbManager.read { db in
            try Message.fetchOne(db, guid: guid)
        }
    }
    
    /// Fetch messages for a contact
    func fetchAll(phoneNumber: String, limit: Int = 100) async throws -> [Message] {
        return try await dbManager.read { db in
            try Message.fetchAll(db, phoneNumber: phoneNumber, limit: limit)
        }
    }
    
    /// Fetch recent messages
    func fetchRecent(limit: Int = 50) async throws -> [Message] {
        return try await dbManager.read { db in
            try Message.fetchRecent(db, limit: limit)
        }
    }
    
    /// Fetch unread messages
    func fetchUnread() async throws -> [Message] {
        return try await dbManager.read { db in
            try Message.fetchUnread(db)
        }
    }
    
    /// Fetch messages in a chat
    func fetchAll(chatId: String, limit: Int = 100) async throws -> [Message] {
        return try await dbManager.read { db in
            try Message.fetchAll(db, chatId: chatId, limit: limit)
        }
    }
    
    /// Count messages for a contact
    func count(phoneNumber: String) async throws -> Int {
        return try await dbManager.read { db in
            try Message.count(db, phoneNumber: phoneNumber)
        }
    }
    
    /// Count total messages
    func count() async throws -> Int {
        return try await dbManager.read { db in
            try Message.fetchCount(db)
        }
    }
    
    /// Count unread messages
    func countUnread() async throws -> Int {
        return try await dbManager.read { db in
            try Message
                .filter(Column("is_from_me") == false)
                .filter(Column("is_read") == false)
                .fetchCount(db)
        }
    }
    
    // MARK: - Update
    
    /// Update an existing message
    func update(_ message: Message) async throws {
        try await dbManager.write { db in
            try message.update(db)
        }
        logger.info("✅ Updated message: \(message.guid)")
    }
    
    /// Mark message as read
    func markAsRead(guid: String) async throws {
        try await dbManager.write { db in
            try db.execute(
                sql: "UPDATE messages SET is_read = 1 WHERE guid = ?",
                arguments: [guid]
            )
        }
    }
    
    /// Mark all messages from contact as read
    func markAllAsRead(phoneNumber: String) async throws {
        try await dbManager.write { db in
            try db.execute(
                sql: "UPDATE messages SET is_read = 1 WHERE phone_number = ? AND is_from_me = 0",
                arguments: [phoneNumber]
            )
        }
        logger.info("✅ Marked all messages as read for: \(phoneNumber)")
    }
    
    // MARK: - Delete
    
    /// Delete message by GUID
    func delete(guid: String) async throws {
        let deleted = try await dbManager.write { db in
            try Message
                .filter(Column("guid") == guid)
                .deleteAll(db)
        }
        
        if deleted > 0 {
            logger.info("✅ Deleted message: \(guid)")
        } else {
            logger.warning("⚠️ Message not found for deletion: \(guid)")
        }
    }
    
    /// Delete a message
    func delete(_ message: Message) async throws {
        try await delete(guid: message.guid)
    }
    
    /// Delete all messages for a contact
    func deleteAll(phoneNumber: String) async throws {
        let deleted = try await dbManager.write { db in
            try Message
                .filter(Column("phone_number") == phoneNumber)
                .deleteAll(db)
        }
        logger.info("✅ Deleted \(deleted) messages for: \(phoneNumber)")
    }
    
    /// Delete messages older than specified date
    func deleteOlder(than date: Date) async throws {
        let timestamp = Int(date.timeIntervalSince1970)
        
        let deleted = try await dbManager.write { db in
            try Message
                .filter(Column("timestamp") < timestamp)
                .deleteAll(db)
        }
        logger.info("✅ Deleted \(deleted) messages older than \(date)")
    }
    
    // MARK: - Batch Operations
    
    /// Import messages from iMessage database
    func importMessages(_ messages: [Message]) async throws {
        let startTime = Date()
        
        try await dbManager.transaction { db in
            for message in messages {
                // Use insert or ignore to avoid duplicates
                try? message.insert(db)
            }
            return ()
        }
        
        let duration = Date().timeIntervalSince(startTime)
        logger.info("✅ Imported \(messages.count) messages in \(String(format: "%.2f", duration))s")
    }
    
    // MARK: - Observations
    
    /// Observe messages for a contact (reactive)
    func observe(phoneNumber: String, limit: Int = 100) -> AsyncThrowingStream<[Message], Error> {
        let observation = ValueObservation.tracking { db in
            try Message.fetchAll(db, phoneNumber: phoneNumber, limit: limit)
        }
        return dbManager.observe(observation)
    }
    
    /// Observe recent messages (reactive)
    func observeRecent(limit: Int = 50) -> AsyncThrowingStream<[Message], Error> {
        let observation = ValueObservation.tracking { db in
            try Message.fetchRecent(db, limit: limit)
        }
        return dbManager.observe(observation)
    }
    
    /// Observe unread messages (reactive)
    func observeUnread() -> AsyncThrowingStream<[Message], Error> {
        let observation = ValueObservation.tracking { db in
            try Message.fetchUnread(db)
        }
        return dbManager.observe(observation)
    }
    
    /// Observe unread count (reactive)
    func observeUnreadCount() -> AsyncThrowingStream<Int, Error> {
        let observation = ValueObservation.tracking { db in
            try Message
                .filter(Column("is_from_me") == false)
                .filter(Column("is_read") == false)
                .fetchCount(db)
        }
        return dbManager.observe(observation)
    }
}

