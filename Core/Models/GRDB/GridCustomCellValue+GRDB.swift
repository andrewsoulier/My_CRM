import Foundation
import GRDB

private let gridCellISOFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

extension GridCustomCellValue: FetchableRecord, PersistableRecord {
    static let databaseTableName = "grid_custom_cell_values"
    
    enum Columns {
        static let id = Column("id")
        static let columnUUID = Column("column_uuid")
        static let recordID = Column("record_id")
        static let entityType = Column("entity_type")
        static let value = Column("value")
        static let updatedAt = Column("updated_at")
    }
    
    init(row: Row) throws {
        self.databaseId = row["id"]
        let columnUUIDString: String = row["column_uuid"]
        guard let columnUUID = UUID(uuidString: columnUUIDString) else {
            throw DatabaseError(message: "Invalid grid custom cell column UUID: \(columnUUIDString)")
        }
        self.columnId = columnUUID
        self.recordId = row["record_id"]
        let entityTypeRaw: String = row["entity_type"]
        self.entityType = GridEntityType(rawValue: entityTypeRaw) ?? .contacts
        self.value = row["value"]
        
        if let updatedAtString: String = row["updated_at"],
           let updatedAt = gridCellISOFormatter.date(from: updatedAtString) {
            self.updatedAt = updatedAt
        } else {
            self.updatedAt = Date()
        }
    }
    
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = databaseId
        container["column_uuid"] = columnId.uuidString
        container["record_id"] = recordId
        container["entity_type"] = entityType.rawValue
        container["value"] = value
        container["updated_at"] = gridCellISOFormatter.string(from: updatedAt)
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        databaseId = inserted.rowID
    }
}

