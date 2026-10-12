import Foundation
import GRDB

private let gridISOFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

extension GridViewConfig: FetchableRecord, PersistableRecord {
    static let databaseTableName = "grid_views"
    
    enum Columns {
        static let id = Column("id")
        static let uuid = Column("uuid")
        static let name = Column("name")
        static let entityType = Column("entity_type")
        static let userId = Column("user_id")
        static let visibleColumns = Column("visible_columns")
        static let frozenColumns = Column("frozen_columns")
        static let columnOrder = Column("column_order")
        static let sortModel = Column("sort_model")
        static let filterModel = Column("filter_model")
        static let filterModelData = Column("filter_model_data")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }
    
    init(row: Row) throws {
        self.databaseId = row["id"]
        let uuidString: String = row["uuid"]
        guard let uuid = UUID(uuidString: uuidString) else {
            throw DatabaseError(message: "Invalid grid view UUID: \(uuidString)")
        }
        self.id = uuid
        self.name = row["name"]
        let entityTypeRaw: String = row["entity_type"]
        self.entityType = GridEntityType(rawValue: entityTypeRaw) ?? .contacts
        self.userId = row["user_id"] ?? "default"
        if let value: String = row["visible_columns"] {
            self.visibleColumns = GridViewConfig.decodeStringArray(value) ?? []
        } else {
            self.visibleColumns = []
        }
        
        if let value: String = row["frozen_columns"] {
            self.frozenColumns = GridViewConfig.decodeStringArray(value) ?? []
        } else {
            self.frozenColumns = []
        }
        
        if let value: String = row["column_order"] {
            self.columnOrder = GridViewConfig.decodeStringArray(value) ?? []
        } else {
            self.columnOrder = []
        }
        
        if let value: String = row["sort_model"] {
            self.sortModel = GridViewConfig.decodeSortDescriptors(value) ?? []
        } else {
            self.sortModel = []
        }
        
        if let value: String = row["filter_model"] {
            self.filterModel = GridViewConfig.decodeFilterModel(value) ?? [:]
        } else {
            self.filterModel = [:]
        }
        
        // Handle new filterModelData field (optional - for backward compatibility)
        if let data: Data = row["filter_model_data"] {
            self.filterModelData = data
        } else {
            self.filterModelData = nil
        }
        
        if let createdAtString: String = row["created_at"], let date = gridISOFormatter.date(from: createdAtString) {
            self.createdAt = date
        } else {
            self.createdAt = Date()
        }
        
        if let updatedAtString: String = row["updated_at"], let date = gridISOFormatter.date(from: updatedAtString) {
            self.updatedAt = date
        } else {
            self.updatedAt = Date()
        }
    }
    
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = databaseId
        container["uuid"] = id.uuidString
        container["name"] = name
        container["entity_type"] = entityType.rawValue
        container["user_id"] = userId
        container["visible_columns"] = GridViewConfig.encodeStringArray(visibleColumns)
        container["frozen_columns"] = GridViewConfig.encodeStringArray(frozenColumns)
        container["column_order"] = GridViewConfig.encodeStringArray(columnOrder)
        container["sort_model"] = GridViewConfig.encodeSortDescriptors(sortModel)
        container["filter_model"] = GridViewConfig.encodeFilterModel(filterModel)
        container["filter_model_data"] = filterModelData
        container["created_at"] = gridISOFormatter.string(from: createdAt)
        container["updated_at"] = gridISOFormatter.string(from: updatedAt)
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        databaseId = inserted.rowID
    }
    
    private static func decodeStringArray(_ value: String) -> [String]? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }
    
    private static func encodeStringArray(_ array: [String]) -> String? {
        guard let data = try? JSONEncoder().encode(array) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    private static func decodeSortDescriptors(_ value: String) -> [GridSortDescriptor]? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([GridSortDescriptor].self, from: data)
    }
    
    private static func encodeSortDescriptors(_ value: [GridSortDescriptor]) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    private static func decodeFilterModel(_ value: String) -> [String: AnyCodable]? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: AnyCodable].self, from: data)
    }
    
    private static func encodeFilterModel(_ value: [String: AnyCodable]) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

