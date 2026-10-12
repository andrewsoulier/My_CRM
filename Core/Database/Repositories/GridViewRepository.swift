import Foundation
import GRDB

@MainActor
class GridViewRepository {
    private let dbManager: GRDBDatabaseManager
    private let logger = LogManager.shared
    
    init(dbManager: GRDBDatabaseManager? = nil) {
        self.dbManager = dbManager ?? GRDBDatabaseManager.shared
    }
    
    // MARK: - Views
    
    func fetchViews(entityType: GridEntityType, userId: String = "default") async throws -> [GridViewConfig] {
        try await dbManager.read { db in
            try GridViewConfig
                .filter(Column("entity_type") == entityType.rawValue && Column("user_id") == userId)
                .order(Column("name"))
                .fetchAll(db)
        }
    }
    
    func fetchView(uuid: UUID) async throws -> GridViewConfig? {
        try await dbManager.read { db in
            try GridViewConfig
                .filter(Column("uuid") == uuid.uuidString)
                .fetchOne(db)
        }
    }
    
    func upsert(view: GridViewConfig) async throws {
        try await dbManager.write { db in
            var mutable = view
            mutable.updatedAt = Date()
            if mutable.createdAt > mutable.updatedAt {
                mutable.createdAt = mutable.updatedAt
            }
            try mutable.save(db)
        }
        logger.info("✅ Upserted grid view \(view.name)")
    }
    
    func delete(viewUUID: UUID) async throws {
        let deleted = try await dbManager.write { db in
            try GridViewConfig
                .filter(Column("uuid") == viewUUID.uuidString)
                .deleteAll(db)
        }
        if deleted > 0 {
            logger.info("🗑️ Deleted grid view \(viewUUID)")
        } else {
            logger.warning("⚠️ Grid view not found for deletion \(viewUUID)")
        }
    }
    
    func observeViews(entityType: GridEntityType, userId: String = "default") -> AsyncThrowingStream<[GridViewConfig], Error> {
        let observation = ValueObservation.tracking { db in
            try GridViewConfig
                .filter(Column("entity_type") == entityType.rawValue && Column("user_id") == userId)
                .order(Column("name"))
                .fetchAll(db)
        }
        return dbManager.observe(observation)
    }
    
    // MARK: - Custom Columns
    
    func fetchCustomColumns(entityType: GridEntityType, userId: String = "default", viewUUID: UUID? = nil) async throws -> [GridCustomColumn] {
        try await dbManager.read { db in
            var request = GridCustomColumn
                .filter(Column("entity_type") == entityType.rawValue && Column("user_id") == userId)
                .order(Column("order_index"), Column("name"))
            
            if let viewUUID = viewUUID {
                request = request.filter(Column("view_uuid") == viewUUID.uuidString || Column("view_uuid") == nil)
            }
            
            return try request.fetchAll(db)
        }
    }
    
    func upsert(column: GridCustomColumn) async throws {
        try await dbManager.write { db in
            var mutable = column
            mutable.updatedAt = Date()
            if mutable.createdAt > mutable.updatedAt {
                mutable.createdAt = mutable.updatedAt
            }
            try mutable.save(db)
        }
        logger.info("✅ Upserted custom column \(column.name)")
    }
    
    func deleteColumn(uuid: UUID) async throws {
        let deleted = try await dbManager.write { db in
            try GridCustomColumn
                .filter(Column("uuid") == uuid.uuidString)
                .deleteAll(db)
        }
        if deleted > 0 {
            logger.info("🗑️ Deleted custom column \(uuid)")
        } else {
            logger.warning("⚠️ Custom column not found for deletion \(uuid)")
        }
    }
    
    func observeCustomColumns(entityType: GridEntityType, userId: String = "default") -> AsyncThrowingStream<[GridCustomColumn], Error> {
        let observation = ValueObservation.tracking { db in
            try GridCustomColumn
                .filter(Column("entity_type") == entityType.rawValue && Column("user_id") == userId)
                .order(Column("order_index"), Column("name"))
                .fetchAll(db)
        }
        return dbManager.observe(observation)
    }
    
    // MARK: - Custom Cell Values
    
    func fetchCellValues(forColumns columnUUIDs: [UUID], recordIds: [String]) async throws -> [GridCustomCellValue] {
        guard !columnUUIDs.isEmpty, !recordIds.isEmpty else { return [] }
        let columnStrings = columnUUIDs.map { $0.uuidString }
        return try await dbManager.read { db in
            try GridCustomCellValue
                .filter(columnStrings.contains(Column("column_uuid")) && recordIds.contains(Column("record_id")))
                .fetchAll(db)
        }
    }
    
    func upsert(cellValues: [GridCustomCellValue]) async throws {
        guard !cellValues.isEmpty else { return }
        try await dbManager.transaction { db in
            for var value in cellValues {
                value.updatedAt = Date()
                try value.save(db)
            }
            return ()
        }
    }
    
    func deleteCellValues(forColumn columnUUID: UUID, recordIds: [String]) async throws {
        guard !recordIds.isEmpty else { return }
        try await dbManager.write { db in
            try GridCustomCellValue
                .filter(Column("column_uuid") == columnUUID.uuidString && recordIds.contains(Column("record_id")))
                .deleteAll(db)
        }
    }
    
    // MARK: - Edit Log / Undo / Redo
    
    func appendEditLogEntry(_ entry: GridEditLogEntry) async throws {
        try await dbManager.write { db in
            // Clear redo stack when a new edit occurs
            try db.execute(
                sql: "DELETE FROM grid_edit_log WHERE session_id = ? AND direction = ?",
                arguments: [entry.sessionId.uuidString, GridEditDirection.redo.rawValue]
            )
            
            var mutable = entry
            mutable.createdAt = Date()
            try mutable.insert(db)
        }
    }
    
    func fetchEditLog(sessionId: UUID, direction: GridEditDirection, limit: Int = 100) async throws -> [GridEditLogEntry] {
        try await dbManager.read { db in
            try GridEditLogEntry
                .filter(Column("session_id") == sessionId.uuidString && Column("direction") == direction.rawValue)
                .order(Column("created_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    func removeEditLogEntry(id databaseId: Int64) async throws {
        _ = try await dbManager.write { db in
            try GridEditLogEntry
                .filter(Column("id") == databaseId)
                .deleteAll(db)
        }
    }
    
    func clearEditLog(sessionId: UUID) async throws {
        _ = try await dbManager.write { db in
            try GridEditLogEntry
                .filter(Column("session_id") == sessionId.uuidString)
                .deleteAll(db)
        }
    }
    
    func clearRedoStack(sessionId: UUID) async throws {
        try await dbManager.write { db in
            try db.execute(
                sql: "DELETE FROM grid_edit_log WHERE session_id = ? AND direction = ?",
                arguments: [sessionId.uuidString, GridEditDirection.redo.rawValue]
            )
        }
    }
    
    func updateEditLogDirection(databaseId: Int64, direction: GridEditDirection, previousValue: String?, nextValue: String?) async throws {
        try await dbManager.write { db in
            try db.execute(
                sql: """
                UPDATE grid_edit_log
                SET direction = ?, previous_value = ?, next_value = ?
                WHERE id = ?
                """,
                arguments: [direction.rawValue, previousValue, nextValue, databaseId]
            )
        }
    }
}

