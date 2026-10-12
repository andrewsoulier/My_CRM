import Foundation
import GRDB

// MARK: - Message GRDB Extensions

extension Message: FetchableRecord, PersistableRecord {
    /// Table name in the database
    static let databaseTableName = "messages"
    
    /// Column names for explicit queries
    enum Columns {
        static let guid = Column("guid")
        static let rowid = Column("rowid")
        static let body = Column("body")
        static let phoneNumber = Column("phone_number")
        static let isFromMe = Column("is_from_me")
        static let cacheRoomname = Column("cache_roomname")
        static let groupChatName = Column("group_chat_name")
        static let timestamp = Column("timestamp")
        static let service = Column("service")
        static let account = Column("account")
        static let chatId = Column("chat_id")
        static let attributedBody = Column("attributedBody")
        static let subject = Column("subject")
        static let country = Column("country")
        static let error = Column("error")
        static let dateRead = Column("date_read")
        static let dateDelivered = Column("date_delivered")
        static let isSent = Column("is_sent")
        static let isRead = Column("is_read")
        static let hasAttachments = Column("has_attachments")
        static let contactId = Column("contact_id")
        static let messageType = Column("message_type")
        static let isFirstMessage = Column("is_first_message")
        static let isLastMessage = Column("is_last_message")
        static let isNew = Column("is_new")
        static let source = Column("source")
    }
    
    // MARK: - FetchableRecord
    
    /// Initialize from database row
    init(row: Row) throws {
        self.guid = row["guid"]
        self.rowid = row["rowid"]
        self.body = row["body"]
        self.phoneNumber = row["phone_number"]
        self.isFromMe = row["is_from_me"]
        self.cacheRoomname = row["cache_roomname"]
        self.groupChatName = row["group_chat_name"]
        self.timestamp = row["timestamp"]
        self.service = row["service"]
        self.account = row["account"]
        self.chatId = row["chat_id"]
        self.attributedBody = row["attributedBody"]
        self.subject = row["subject"]
        self.country = row["country"]
        self.error = row["error"]
        self.dateRead = row["date_read"]
        self.dateDelivered = row["date_delivered"]
        self.isSent = row["is_sent"]
        self.isRead = row["is_read"]
        self.hasAttachments = row["has_attachments"]
        self.contactId = row["contact_id"]
        self.messageType = row["message_type"]
        self.isFirstMessage = row["is_first_message"]
        self.isLastMessage = row["is_last_message"]
        self.isNew = row["is_new"]
        self.source = row["source"]
    }
    
    // MARK: - PersistableRecord
    
    /// Encode to database
    func encode(to container: inout PersistenceContainer) throws {
        container["guid"] = guid
        container["rowid"] = rowid
        container["body"] = body
        container["phone_number"] = phoneNumber
        container["is_from_me"] = isFromMe
        container["cache_roomname"] = cacheRoomname
        container["group_chat_name"] = groupChatName
        container["timestamp"] = timestamp
        container["service"] = service
        container["account"] = account
        container["chat_id"] = chatId
        container["attributedBody"] = attributedBody
        container["subject"] = subject
        container["country"] = country
        container["error"] = error
        container["date_read"] = dateRead
        container["date_delivered"] = dateDelivered
        container["is_sent"] = isSent
        container["is_read"] = isRead
        container["has_attachments"] = hasAttachments
        container["contact_id"] = contactId
        container["message_type"] = messageType
        container["is_first_message"] = isFirstMessage
        container["is_last_message"] = isLastMessage
        container["is_new"] = isNew
        container["source"] = source
    }
}

// MARK: - Query Helpers

extension Message {
    /// Find message by GUID
    static func fetchOne(_ db: Database, guid: String) throws -> Message? {
        return try Message
            .filter(Column("guid") == guid)
            .fetchOne(db)
    }
    
    /// Fetch messages for a specific contact
    static func fetchAll(_ db: Database, phoneNumber: String, limit: Int = 100) throws -> [Message] {
        return try Message
            .filter(Column("phone_number") == phoneNumber)
            .order(Column("timestamp").desc)
            .limit(limit)
            .fetchAll(db)
    }
    
    /// Fetch recent messages
    static func fetchRecent(_ db: Database, limit: Int = 50) throws -> [Message] {
        return try Message
            .order(Column("timestamp").desc)
            .limit(limit)
            .fetchAll(db)
    }
    
    /// Fetch unread messages
    static func fetchUnread(_ db: Database) throws -> [Message] {
        return try Message
            .filter(Column("is_from_me") == false)
            .filter(Column("is_read") == false)
            .order(Column("timestamp").desc)
            .fetchAll(db)
    }
    
    /// Fetch messages in a specific chat
    static func fetchAll(_ db: Database, chatId: String, limit: Int = 100) throws -> [Message] {
        return try Message
            .filter(Column("chat_id") == chatId)
            .order(Column("timestamp").desc)
            .limit(limit)
            .fetchAll(db)
    }
    
    /// Count messages for a contact
    static func count(_ db: Database, phoneNumber: String) throws -> Int {
        return try Message
            .filter(Column("phone_number") == phoneNumber)
            .fetchCount(db)
    }
}

