import Foundation
import GRDB

extension Relationship: FetchableRecord, PersistableRecord {
    static let databaseTableName = "relationships"
    
    enum Columns {
        static let id = Column("id")
        static let uuid = Column("uuid")
        static let name = Column("name")
        static let color = Column("color")
        static let description = Column("description")
        static let linkedContacts = Column("linked_contacts")
        static let linkedGroups = Column("linked_groups")
    }
    
    init(row: Row) throws {
        self.databaseId = row["id"]
        let uuidString: String = row["uuid"]
        guard let uuid = UUID(uuidString: uuidString) else {
            throw DatabaseError(message: "Invalid relationship UUID: \(uuidString)")
        }
        self.id = uuid
        self.name = row["name"]
        self.colorHex = row["color"]
        self.description = row["description"]
        
        if let contactsJSON: String = row["linked_contacts"],
           let data = contactsJSON.data(using: .utf8),
           let identifiers = try? JSONDecoder().decode([Int64].self, from: data) {
            self.linkedContactIDs = identifiers
        } else {
            self.linkedContactIDs = []
        }
        
        if let groupsJSON: String = row["linked_groups"],
           let data = groupsJSON.data(using: .utf8),
           let identifiers = try? JSONDecoder().decode([String].self, from: data) {
            self.linkedGroupIDs = identifiers.compactMap { UUID(uuidString: $0) }
        } else {
            self.linkedGroupIDs = []
        }
    }
    
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = databaseId
        container["uuid"] = id.uuidString
        container["name"] = name
        container["color"] = colorHex
        container["description"] = description
        
        if let data = try? JSONEncoder().encode(linkedContactIDs) {
            container["linked_contacts"] = String(data: data, encoding: .utf8)
        }
        
        let groupStrings = linkedGroupIDs.map { $0.uuidString }
        if let data = try? JSONEncoder().encode(groupStrings) {
            container["linked_groups"] = String(data: data, encoding: .utf8)
        }
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        databaseId = inserted.rowID
    }
    
    static func fetchOne(_ db: Database, uuid: UUID) throws -> Relationship? {
        try Relationship
            .filter(Column("uuid") == uuid.uuidString)
            .fetchOne(db)
    }
}

