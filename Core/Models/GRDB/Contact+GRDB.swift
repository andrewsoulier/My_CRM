import Foundation
import GRDB

// MARK: - Contact GRDB Extensions

extension Contact: FetchableRecord, PersistableRecord {
    /// Table name in the database
    static let databaseTableName = "contacts"
    
    private static let persistenceFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    /// Column names for explicit queries
    enum Columns {
        static let id = Column("id")
        static let phone = Column("phone")
        static let name = Column("name")
        static let firstName = Column("first_name")
        static let lastName = Column("last_name")
        static let email = Column("email")
        static let address = Column("address")
        static let notes = Column("notes")
        static let nickname = Column("nickname")
        static let creationDate = Column("creation_date")
        static let business = Column("business")
        static let contactGroup = Column("contact_group")
        static let birthday = Column("birthday")
        static let appleContactID = Column("apple_contact_id")
        static let profilePhoto = Column("profile_photo")
        static let lastMessageDate = Column("last_message_date")
        static let lastMessageSentDate = Column("last_message_sent_date")
        static let lastMessageReceivedDate = Column("last_message_received_date")
        static let tagIDs = Column("tag_ids")
        static let relationshipIDs = Column("relationship_ids")
        static let totalMessages = Column("total_messages")
        static let messagesSent = Column("messages_sent")
        static let messagesReceived = Column("messages_received")
        static let sentLastMessage = Column("sent_last_message")
    }
    
    // MARK: - FetchableRecord
    
    /// Initialize from database row
    init(row: Row) throws {
        // Database uses integer ID, but we generate UUID for Swift model
        self.id = UUID()
        self.databaseId = row["id"]
        
        // Required fields - provide defaults if missing
        self.phone = row["phone"] ?? ""
        self.name = row["name"] ?? ""
        
        // Optional fields - use optional accessor
        self.firstName = row["first_name"]
        self.lastName = row["last_name"]
        self.email = row["email"]
        self.address = row["address"]
        self.notes = row["notes"]
        
        // Handle nickname - may not exist in older databases
        if row.hasColumn("nickname") {
            self.nickname = row["nickname"]
        } else {
            self.nickname = nil
        }
        
        // Handle date conversions
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let dateString: String = row["creation_date"] {
            self.creationDate = isoFormatter.date(from: dateString) ?? Date()
        } else {
            self.creationDate = Date()
        }
        
        self.business = row["business"]
        self.contactGroup = row["contact_group"]
        
        if let birthdayString: String = row["birthday"] {
            self.birthday = isoFormatter.date(from: birthdayString)
        } else {
            self.birthday = nil
        }
        
        self.appleContactID = row["apple_contact_id"]
        self.profilePhotoData = row["profile_photo"]
        
        if let lastMessageString: String = row["last_message_date"] {
            self.lastMessageDate = isoFormatter.date(from: lastMessageString)
        } else {
            self.lastMessageDate = nil
        }
        
        // Handle last_message_sent_date - may not exist in older databases
        if row.hasColumn("last_message_sent_date"), let sentString: String = row["last_message_sent_date"] {
            self.lastMessageSentDate = isoFormatter.date(from: sentString)
        } else {
            self.lastMessageSentDate = nil
        }
        
        // Handle last_message_received_date - may not exist in older databases
        if row.hasColumn("last_message_received_date"), let receivedString: String = row["last_message_received_date"] {
            self.lastMessageReceivedDate = isoFormatter.date(from: receivedString)
        } else {
            self.lastMessageReceivedDate = nil
        }
        
        // Handle tag_ids - may not exist in older databases
        if row.hasColumn("tag_ids"), let tagsJSON: String = row["tag_ids"],
           let data = tagsJSON.data(using: .utf8),
           let identifiers = try? JSONDecoder().decode([String].self, from: data) {
            self.tagIDs = identifiers.compactMap { UUID(uuidString: $0) }
        } else {
            self.tagIDs = []
        }
        
        // Handle relationship_ids - may not exist in older databases
        if row.hasColumn("relationship_ids"), let relationshipsJSON: String = row["relationship_ids"],
           let data = relationshipsJSON.data(using: .utf8),
           let identifiers = try? JSONDecoder().decode([String].self, from: data) {
            self.relationshipIDs = identifiers.compactMap { UUID(uuidString: $0) }
        } else {
            self.relationshipIDs = []
        }
        
        self.totalMessages = row["total_messages"] ?? 0
        self.messagesSentCount = row["messages_sent"] ?? 0
        self.messagesReceivedCount = row["messages_received"] ?? 0
        self.sentLastMessage = (row["sent_last_message"] ?? 0) != 0
    }
    
    // MARK: - PersistableRecord
    
    /// Encode to database
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = databaseId
        container["phone"] = phone
        container["name"] = name
        container["first_name"] = firstName
        container["last_name"] = lastName
        container["email"] = email
        container["address"] = address
        container["notes"] = notes
        
        // Auto-populate nickname with firstName if nickname is empty
        let finalNickname: String?
        if let nickname = nickname, !nickname.isEmpty {
            finalNickname = nickname
        } else if let firstName = firstName, !firstName.isEmpty {
            finalNickname = firstName
        } else {
            finalNickname = nil
        }
        container["nickname"] = finalNickname
        
        // Convert dates to ISO8601 strings for database
        if let creationDate = creationDate {
            container["creation_date"] = Contact.persistenceFormatter.string(from: creationDate)
        }
        
        container["business"] = business
        container["contact_group"] = contactGroup
        
        if let birthday = birthday {
            container["birthday"] = Contact.persistenceFormatter.string(from: birthday)
        }
        
        container["apple_contact_id"] = appleContactID
        container["profile_photo"] = profilePhotoData
        
        if let lastMessageDate = lastMessageDate {
            container["last_message_date"] = Contact.persistenceFormatter.string(from: lastMessageDate)
        }
        if let lastMessageSentDate = lastMessageSentDate {
            container["last_message_sent_date"] = Contact.persistenceFormatter.string(from: lastMessageSentDate)
        }
        if let lastMessageReceivedDate = lastMessageReceivedDate {
            container["last_message_received_date"] = Contact.persistenceFormatter.string(from: lastMessageReceivedDate)
        }
        
        if let tagData = try? JSONEncoder().encode(tagIDs.map { $0.uuidString }) {
            container["tag_ids"] = String(data: tagData, encoding: .utf8)
        }
        
        if let relationshipData = try? JSONEncoder().encode(relationshipIDs.map { $0.uuidString }) {
            container["relationship_ids"] = String(data: relationshipData, encoding: .utf8)
        }
        
        container["total_messages"] = totalMessages
        container["messages_sent"] = messagesSentCount
        container["messages_received"] = messagesReceivedCount
        container["sent_last_message"] = sentLastMessage ? 1 : 0
    }
    
    /// Use phone as primary key (unique identifier)
    func didInsert(_ inserted: InsertionSuccess) {
        // Contact doesn't use autoincrement ID in Swift model
        // Phone is the business key
    }
}

// MARK: - Query Helpers

extension Contact {
    /// Find contact by phone number
    static func fetchOne(_ db: Database, phone: String) throws -> Contact? {
        return try Contact
            .filter(Column("phone") == phone)
            .fetchOne(db)
    }
    
    /// Find contacts by business
    static func fetchAll(_ db: Database, business: String) throws -> [Contact] {
        return try Contact
            .filter(Column("business") == business)
            .order(Column("name"))
            .fetchAll(db)
    }
    
    /// Find contacts with recent messages
    static func fetchRecent(_ db: Database, limit: Int = 50) throws -> [Contact] {
        return try Contact
            .filter(Column("last_message_date") != nil)
            .order(Column("last_message_date").desc)
            .limit(limit)
            .fetchAll(db)
    }
    
    /// Search contacts by name or phone
    static func search(_ db: Database, query: String) throws -> [Contact] {
        let pattern = "%\(query)%"
        return try Contact
            .filter(
                Column("name").like(pattern) ||
                Column("phone").like(pattern) ||
                Column("email").like(pattern) ||
                Column("business").like(pattern)
            )
            .order(Column("name"))
            .fetchAll(db)
    }
}

