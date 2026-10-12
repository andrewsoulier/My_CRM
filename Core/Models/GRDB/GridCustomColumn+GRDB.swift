import Foundation
import GRDB

private let gridColumnISOFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

extension GridCustomColumn: FetchableRecord, PersistableRecord {
    static let databaseTableName = "grid_custom_columns"
    
    enum Columns {
        static let id = Column("id")
        static let uuid = Column("uuid")
        static let viewUUID = Column("view_uuid")
        static let entityType = Column("entity_type")
        static let userID = Column("user_id")
        static let name = Column("name")
        static let dataType = Column("data_type")
        static let isVisible = Column("is_visible")
        static let orderIndex = Column("order_index")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }
    
    init(row: Row) throws {
        self.databaseId = row["id"]
        let uuidString: String = row["uuid"]
        guard let uuid = UUID(uuidString: uuidString) else {
            throw DatabaseError(message: "Invalid custom column UUID: \(uuidString)")
        }
        self.id = uuid
        
        if let viewUUIDString: String = row["view_uuid"], !viewUUIDString.isEmpty {
            self.viewId = UUID(uuidString: viewUUIDString)
        } else {
            self.viewId = nil
        }
        
        let entityTypeRaw: String = row["entity_type"]
        self.entityType = GridEntityType(rawValue: entityTypeRaw) ?? .contacts
        self.userId = row["user_id"] ?? "default"
        self.name = row["name"]
        self.dataType = GridColumnDataType(rawValue: row["data_type"] ?? "") ?? .text
        self.isVisible = row["is_visible"] ?? true
        if let indexValue: Int = row["order_index"] {
            self.orderIndex = indexValue
        } else {
            self.orderIndex = nil
        }
        
        if let createdAtString: String = row["created_at"],
           let created = gridColumnISOFormatter.date(from: createdAtString) {
            self.createdAt = created
        } else {
            self.createdAt = Date()
        }
        
        if let updatedAtString: String = row["updated_at"],
           let updated = gridColumnISOFormatter.date(from: updatedAtString) {
            self.updatedAt = updated
        } else {
            self.updatedAt = Date()
        }
    }
    
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = databaseId
        container["uuid"] = id.uuidString
        container["view_uuid"] = viewId?.uuidString
        container["entity_type"] = entityType.rawValue
        container["user_id"] = userId
        container["name"] = name
        container["data_type"] = dataType.rawValue
        container["is_visible"] = isVisible
        container["order_index"] = orderIndex
        container["created_at"] = gridColumnISOFormatter.string(from: createdAt)
        container["updated_at"] = gridColumnISOFormatter.string(from: updatedAt)
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        databaseId = inserted.rowID
    }
}

