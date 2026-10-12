import Foundation
import GRDB
import SwiftUI

// MARK: - ContactGroup GRDB Extensions

extension ContactGroup: FetchableRecord, PersistableRecord {
    /// Table name in the database
    static let databaseTableName = "groups"
    
    /// Column names for explicit queries
    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let color = Column("color")
        static let createdAt = Column("created_at")
        static let parentID = Column("parent_id")
        static let memberPhones = Column("member_phones")
        static let linkedGroupIDs = Column("linked_group_ids")
        static let metadata = Column("metadata")
        static let isDeck = Column("is_deck")
        static let canvases = Column("canvases")
        static let tags = Column("tags")
        static let childGroupIDs = Column("child_group_ids")
        static let parentGroupIDs = Column("parent_group_ids")
        static let size = Column("size")
        static let macOSGroupID = Column("macos_group_id")
    }
    
    // MARK: - FetchableRecord
    
    /// Initialize from database row
    init(row: Row) throws {
        // Parse UUID from TEXT column
        // Handle both UUID format and integer IDs (legacy format)
        let idString: String = row["id"]
        
        let uuid: UUID
        if let parsedUUID = UUID(uuidString: idString) {
            // Already a valid UUID
            uuid = parsedUUID
        } else if let integerId = Int(idString) {
            // Convert integer ID to UUID format: 00000000-0000-0000-0000-%012d
            let uuidString = String(format: "00000000-0000-0000-0000-%012d", integerId)
            guard let convertedUUID = UUID(uuidString: uuidString) else {
                throw DatabaseError(message: "Failed to convert integer ID to UUID: \(idString)")
            }
            uuid = convertedUUID
        } else {
            throw DatabaseError(message: "Invalid group ID format (not UUID or integer): \(idString)")
        }
        
        self.id = uuid
        
        self.name = row["name"]
        
        // Parse color from hex string
        let colorHex: String = row["color"]
        self.color = Color(hex: colorHex) ?? .blue
        self.colorHexString = colorHex
        
        // Parse date
        let createdAtString: String = row["created_at"]
        self.createdAt = ISO8601DateFormatter().date(from: createdAtString) ?? Date()
        
        // Parse parent ID if exists
        if let parentIDString: String = row["parent_id"], !parentIDString.isEmpty {
            self.parentID = UUID(uuidString: parentIDString)
        } else {
            self.parentID = nil
        }
        
        // Parse JSON arrays
        if let memberPhonesJSON: String = row["member_phones"], !memberPhonesJSON.isEmpty {
            if let data = memberPhonesJSON.data(using: .utf8),
               let phones = try? JSONDecoder().decode([String].self, from: data) {
                self.memberPhones = Set(phones)
            } else {
                self.memberPhones = []
            }
        } else {
            self.memberPhones = []
        }
        
        if let linkedGroupIDsJSON: String = row["linked_group_ids"], !linkedGroupIDsJSON.isEmpty {
            if let data = linkedGroupIDsJSON.data(using: .utf8),
               let ids = try? JSONDecoder().decode([String].self, from: data) {
                self.linkedGroupIDs = Set(ids.compactMap { UUID(uuidString: $0) })
            } else {
                self.linkedGroupIDs = []
            }
        } else {
            self.linkedGroupIDs = []
        }
        
        // Parse metadata JSON
        if let metadataJSON: String = row["metadata"], !metadataJSON.isEmpty {
            if let data = metadataJSON.data(using: .utf8),
               let metadata = try? JSONDecoder().decode(GroupMetadata.self, from: data) {
                self.metadata = metadata
            } else {
                self.metadata = GroupMetadata()
            }
        } else {
            self.metadata = GroupMetadata()
        }
        
        self.isDeck = row["is_deck"]
        
        // Parse canvases JSON
        if let canvasesJSON: String = row["canvases"], !canvasesJSON.isEmpty {
            if let data = canvasesJSON.data(using: .utf8),
               let canvasIDs = try? JSONDecoder().decode([String].self, from: data) {
                self.canvases = Set(canvasIDs.compactMap { UUID(uuidString: $0) })
            } else {
                self.canvases = []
            }
        } else {
            self.canvases = []
        }
        
        if let tagsJSON: String = row["tags"], !tagsJSON.isEmpty,
           let data = tagsJSON.data(using: .utf8),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            self.tags = Set(ids.compactMap { UUID(uuidString: $0) })
        } else {
            self.tags = []
        }
        
        if let childrenJSON: String = row["child_group_ids"], !childrenJSON.isEmpty,
           let data = childrenJSON.data(using: .utf8),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            self.childGroupIDs = Set(ids.compactMap { UUID(uuidString: $0) })
        } else {
            self.childGroupIDs = []
        }
        
        if let parentsJSON: String = row["parent_group_ids"], !parentsJSON.isEmpty,
           let data = parentsJSON.data(using: .utf8),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            self.parentGroupIDs = Set(ids.compactMap { UUID(uuidString: $0) })
        } else {
            self.parentGroupIDs = []
        }
        
        if let sizeValue: Int = row["size"] {
            self.cachedSize = sizeValue
        } else {
            self.cachedSize = memberPhones.count
        }
        
        // Parse macOSGroupID if exists
        if let macOSGroupIDString: String = row["macos_group_id"], !macOSGroupIDString.isEmpty {
            self.macOSGroupID = macOSGroupIDString
        } else {
            self.macOSGroupID = nil
        }
        
        self.databaseId = nil // This would need to come from a separate query if needed
    }
    
    // MARK: - PersistableRecord
    
    /// Encode to database
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["name"] = name
        container["color"] = colorHexString ?? color.toHexString()
        container["created_at"] = ISO8601DateFormatter().string(from: createdAt)
        container["parent_id"] = parentID?.uuidString
        
        // Encode member phones as JSON array
        let memberPhonesData = try JSONEncoder().encode(Array(memberPhones))
        container["member_phones"] = String(data: memberPhonesData, encoding: .utf8)
        
        // Encode linked group IDs as JSON array
        let linkedGroupIDsStrings = linkedGroupIDs.map { $0.uuidString }
        let linkedGroupIDsData = try JSONEncoder().encode(linkedGroupIDsStrings)
        container["linked_group_ids"] = String(data: linkedGroupIDsData, encoding: .utf8)
        
        // Encode metadata as JSON
        let metadataData = try JSONEncoder().encode(metadata)
        container["metadata"] = String(data: metadataData, encoding: .utf8)
        
        container["is_deck"] = isDeck
        
        // Encode canvases as JSON array
        let canvasesStrings = canvases.map { $0.uuidString }
        let canvasesData = try JSONEncoder().encode(canvasesStrings)
        container["canvases"] = String(data: canvasesData, encoding: .utf8)
        
        let tagStrings = tags.map { $0.uuidString }
        let tagsData = try JSONEncoder().encode(tagStrings)
        container["tags"] = String(data: tagsData, encoding: .utf8)
        
        let childStrings = childGroupIDs.map { $0.uuidString }
        let childData = try JSONEncoder().encode(childStrings)
        container["child_group_ids"] = String(data: childData, encoding: .utf8)
        
        let parentStrings = parentGroupIDs.map { $0.uuidString }
        let parentData = try JSONEncoder().encode(parentStrings)
        container["parent_group_ids"] = String(data: parentData, encoding: .utf8)
        container["size"] = cachedSize
        container["macos_group_id"] = macOSGroupID
    }
}

// MARK: - Query Helpers

extension ContactGroup {
    /// Find group by ID
    static func fetchOne(_ db: Database, id: UUID) throws -> ContactGroup? {
        return try ContactGroup
            .filter(Column("id") == id.uuidString)
            .fetchOne(db)
    }
    
    /// Fetch all root groups (no parent)
    static func fetchRootGroups(_ db: Database) throws -> [ContactGroup] {
        return try ContactGroup
            .filter(Column("parent_id") == nil || Column("parent_id") == "")
            .order(Column("name"))
            .fetchAll(db)
    }
    
    /// Fetch child groups of a parent
    static func fetchChildren(_ db: Database, parentID: UUID) throws -> [ContactGroup] {
        return try ContactGroup
            .filter(Column("parent_id") == parentID.uuidString)
            .order(Column("name"))
            .fetchAll(db)
    }
    
    /// Fetch all decks
    static func fetchDecks(_ db: Database) throws -> [ContactGroup] {
        return try ContactGroup
            .filter(Column("is_deck") == true)
            .order(Column("name"))
            .fetchAll(db)
    }
    
    /// Fetch groups containing a specific phone number
    static func fetchContaining(_ db: Database, phone: String) throws -> [ContactGroup] {
        return try ContactGroup
            .filter(Column("member_phones").like("%\(phone)%"))
            .fetchAll(db)
    }
    
    /// Search groups by name
    static func search(_ db: Database, query: String) throws -> [ContactGroup] {
        let pattern = "%\(query)%"
        return try ContactGroup
            .filter(Column("name").like(pattern))
            .order(Column("name"))
            .fetchAll(db)
    }
}

