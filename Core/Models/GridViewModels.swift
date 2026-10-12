import Foundation

enum GridEntityType: String, Codable, CaseIterable {
    case contacts
    case groups
}

enum GridColumnDataType: String, Codable, CaseIterable {
    case text
    case number
    case date
    case phone
    case email
    case smartchip
}

struct GridSortDescriptor: Codable, Hashable {
    enum Direction: String, Codable {
        case ascending
        case descending
    }
    
    var columnId: String
    var direction: Direction
}

struct GridViewConfig: Identifiable, Codable {
    var id: UUID
    var databaseId: Int64?
    var name: String
    var entityType: GridEntityType
    var userId: String
    var visibleColumns: [String]
    var frozenColumns: [String]
    var columnOrder: [String]
    var sortModel: [GridSortDescriptor]
    var filterModel: [String: AnyCodable] // Legacy format - kept for backward compatibility
    var filterModelData: Data? // New FilterModel stored as JSON data
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        databaseId: Int64? = nil,
        name: String,
        entityType: GridEntityType,
        userId: String = "default",
        visibleColumns: [String] = [],
        frozenColumns: [String] = [],
        columnOrder: [String] = [],
        sortModel: [GridSortDescriptor] = [],
        filterModel: [String: AnyCodable] = [:],
        filterModelData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.databaseId = databaseId
        self.name = name
        self.entityType = entityType
        self.userId = userId
        self.visibleColumns = visibleColumns
        self.frozenColumns = frozenColumns
        self.columnOrder = columnOrder
        self.sortModel = sortModel
        self.filterModel = filterModel
        self.filterModelData = filterModelData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Filter Model Helpers
    
    /// Get the FilterModel (new format) - migrates from old format if needed
    var advancedFilterModel: FilterModel {
        // Try to decode from new format first
        if let data = filterModelData,
           let decoded = try? JSONDecoder().decode(FilterModel.self, from: data) {
            return decoded
        }
        
        // Fall back to migrating from old format
        if !filterModel.isEmpty {
            return FilterModel.fromLegacyDictionary(filterModel, entityType: entityType)
        }
        
        // Return empty filter model
        return FilterModel(entityType: entityType)
    }
    
    /// Set the FilterModel (new format)
    mutating func setAdvancedFilterModel(_ model: FilterModel) {
        // Encode to JSON data
        if let encoded = try? JSONEncoder().encode(model) {
            filterModelData = encoded
            // Clear old format
            filterModel = [:]
        }
    }
}

struct GridCustomColumn: Identifiable, Hashable, Codable {
    var id: UUID
    var databaseId: Int64?
    var viewId: UUID?
    var entityType: GridEntityType
    var userId: String
    var name: String
    var dataType: GridColumnDataType
    var isVisible: Bool
    var orderIndex: Int?
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        databaseId: Int64? = nil,
        viewId: UUID? = nil,
        entityType: GridEntityType,
        userId: String = "default",
        name: String,
        dataType: GridColumnDataType = .text,
        isVisible: Bool = true,
        orderIndex: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.databaseId = databaseId
        self.viewId = viewId
        self.entityType = entityType
        self.userId = userId
        self.name = name
        self.dataType = dataType
        self.isVisible = isVisible
        self.orderIndex = orderIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct GridCustomCellValue: Identifiable, Hashable, Codable {
    var databaseId: Int64?
    var columnId: UUID
    var recordId: String
    var entityType: GridEntityType
    var value: String?
    var updatedAt: Date
    
    var id: String {
        "\(columnId.uuidString)-\(recordId)"
    }
    
    init(
        databaseId: Int64? = nil,
        columnId: UUID,
        recordId: String,
        entityType: GridEntityType,
        value: String?,
        updatedAt: Date = Date()
    ) {
        self.databaseId = databaseId
        self.columnId = columnId
        self.recordId = recordId
        self.entityType = entityType
        self.value = value
        self.updatedAt = updatedAt
    }
}

enum GridEditDirection: String, Codable {
    case undo
    case redo
}

struct GridEditLogEntry: Identifiable, Hashable, Codable {
    var databaseId: Int64?
    var sessionId: UUID
    var entityType: GridEntityType
    var recordId: String
    var columnId: String
    var previousValue: String?
    var nextValue: String?
    var createdAt: Date
    var direction: GridEditDirection
    
    var id: String {
        if let databaseId = databaseId {
            return "grid-edit-\(databaseId)"
        }
        return "grid-edit-\(sessionId.uuidString)-\(columnId)-\(recordId)-\(createdAt.timeIntervalSince1970)"
    }
    
    init(
        databaseId: Int64? = nil,
        sessionId: UUID,
        entityType: GridEntityType,
        recordId: String,
        columnId: String,
        previousValue: String?,
        nextValue: String?,
        createdAt: Date = Date(),
        direction: GridEditDirection
    ) {
        self.databaseId = databaseId
        self.sessionId = sessionId
        self.entityType = entityType
        self.recordId = recordId
        self.columnId = columnId
        self.previousValue = previousValue
        self.nextValue = nextValue
        self.createdAt = createdAt
        self.direction = direction
    }
}

