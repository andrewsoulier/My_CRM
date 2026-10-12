import Foundation
import GRDB

private let gridEditISOFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

extension GridEditLogEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "grid_edit_log"
    
    enum Columns {
        static let id = Column("id")
        static let sessionID = Column("session_id")
        static let entityType = Column("entity_type")
        static let recordID = Column("record_id")
        static let columnID = Column("column_id")
        static let previousValue = Column("previous_value")
        static let nextValue = Column("next_value")
        static let createdAt = Column("created_at")
        static let direction = Column("direction")
    }
    
    init(row: Row) throws {
        self.databaseId = row["id"]
        let sessionString: String = row["session_id"]
        guard let sessionUUID = UUID(uuidString: sessionString) else {
            throw DatabaseError(message: "Invalid grid edit session UUID: \(sessionString)")
        }
        self.sessionId = sessionUUID
        self.entityType = GridEntityType(rawValue: row["entity_type"] ?? "") ?? .contacts
        self.recordId = row["record_id"]
        self.columnId = row["column_id"]
        self.previousValue = row["previous_value"]
        self.nextValue = row["next_value"]
        
        if let createdAtString: String = row["created_at"],
           let createdAtDate = gridEditISOFormatter.date(from: createdAtString) {
            self.createdAt = createdAtDate
        } else {
            self.createdAt = Date()
        }
        
        self.direction = GridEditDirection(rawValue: row["direction"] ?? "") ?? .undo
    }
    
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = databaseId
        container["session_id"] = sessionId.uuidString
        container["entity_type"] = entityType.rawValue
        container["record_id"] = recordId
        container["column_id"] = columnId
        container["previous_value"] = previousValue
        container["next_value"] = nextValue
        container["created_at"] = gridEditISOFormatter.string(from: createdAt)
        container["direction"] = direction.rawValue
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        databaseId = inserted.rowID
    }
}

