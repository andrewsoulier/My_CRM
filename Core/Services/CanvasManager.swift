import Foundation
import SQLite3

/// Manages canvas database operations - Pure Swift replacement for canvas_manager.py
final class CanvasManager {
    private let logger = LogManager.shared
    private let database = CRMDatabase.shared
    
    // MARK: - Canvas Operations
    
    /// Create a new canvas in the database
    func createCanvas(_ canvas: Canvas) -> Bool {
        guard let db = try? database.open() else {
            logger.error("❌ CanvasManager: Failed to open database")
            return false
        }
        defer { sqlite3_close(db) }
        
        ensureCanvasesTable(db: db)
        
        let elementsJSON = jsonString(from: canvas.elements.map { $0.toDatabaseFormat() })
        let stateJSON = jsonString(from: canvas.canvasState.toDatabaseFormat())
        let metadataJSON = jsonString(from: canvas.metadata)
        let elementCounts = calculateElementCounts(elements: canvas.elements)
        let elementCountsJSON = jsonString(from: elementCounts)
        
        let dateFormatter = ISO8601DateFormatter()
        let now = dateFormatter.string(from: Date())
        
        let sql = """
        INSERT OR REPLACE INTO canvases (
            canvas_id, canvas_name, canvas_elements, element_counts,
            date_created, date_updated, last_saved, canvas_type,
            canvas_state, metadata
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ CanvasManager: Failed to prepare create canvas statement")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, canvas.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, canvas.name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, elementsJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, elementCountsJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, now, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, now, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, now, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, canvas.canvasType.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 9, stateJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 10, metadataJSON, -1, SQLITE_TRANSIENT)
        
        let success = sqlite3_step(stmt) == SQLITE_DONE
        if success {
            logger.info("✅ CanvasManager: Created canvas: \(canvas.name) (ID: \(canvas.id))")
        } else {
            logger.error("❌ CanvasManager: Failed to create canvas: \(canvas.name)")
        }
        return success
    }
    
    /// Get a canvas by ID
    func getCanvas(id: String) -> Canvas? {
        guard let db = try? database.open() else {
            logger.error("❌ CanvasManager: Failed to open database")
            return nil
        }
        defer { sqlite3_close(db) }
        
        let sql = "SELECT * FROM canvases WHERE canvas_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ CanvasManager: Failed to prepare get canvas statement")
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return canvasFromRow(stmt)
        }
        
        return nil
    }
    
    /// Get all canvases, optionally filtered by type
    func getAllCanvases(type: CanvasType? = nil) -> [Canvas] {
        guard let db = try? database.open() else {
            logger.error("❌ CanvasManager: Failed to open database")
            return []
        }
        defer { sqlite3_close(db) }
        
        let sql: String
        if let type = type {
            sql = "SELECT * FROM canvases WHERE canvas_type = ? ORDER BY date_updated DESC"
        } else {
            sql = "SELECT * FROM canvases ORDER BY date_updated DESC"
        }
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ CanvasManager: Failed to prepare get all canvases statement")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        if let type = type {
            sqlite3_bind_text(stmt, 1, type.rawValue, -1, SQLITE_TRANSIENT)
        }
        
        var canvases: [Canvas] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let canvas = canvasFromRow(stmt) {
                canvases.append(canvas)
            }
        }
        
        return canvases
    }
    
    /// Update an existing canvas
    func updateCanvas(id: String, updates: [String: Any]) -> Bool {
        guard let db = try? database.open() else {
            logger.error("❌ CanvasManager: Failed to open database")
            return false
        }
        defer { sqlite3_close(db) }
        
        var setClauses: [String] = []
        var values: [String] = []
        
        let dateFormatter = ISO8601DateFormatter()
        let now = dateFormatter.string(from: Date())
        
        // Always update date_updated
        setClauses.append("date_updated = ?")
        values.append(now)
        
        if let name = updates["canvas_name"] as? String {
            setClauses.append("canvas_name = ?")
            values.append(name)
        }
        
        if let elements = updates["canvas_elements"] as? [[String: Any]] {
            let elementsJSON = jsonString(from: elements)
            setClauses.append("canvas_elements = ?")
            values.append(elementsJSON)
            
            // Recalculate element counts
            if let canvasElements = elements.compactMap({ CanvasElement.fromDatabaseFormat($0) }) as? [CanvasElement] {
                let elementCounts = calculateElementCounts(elements: canvasElements)
                let elementCountsJSON = jsonString(from: elementCounts)
                setClauses.append("element_counts = ?")
                values.append(elementCountsJSON)
            }
        }
        
        if let state = updates["canvas_state"] as? [String: Any] {
            let stateJSON = jsonString(from: state)
            setClauses.append("canvas_state = ?")
            values.append(stateJSON)
        }
        
        if let type = updates["canvas_type"] as? String {
            setClauses.append("canvas_type = ?")
            values.append(type)
        }
        
        if let metadata = updates["metadata"] as? [String: Any] {
            let metadataJSON = jsonString(from: metadata)
            setClauses.append("metadata = ?")
            values.append(metadataJSON)
        }
        
        // Update last_saved
        setClauses.append("last_saved = ?")
        values.append(now)
        
        let sql = "UPDATE canvases SET \(setClauses.joined(separator: ", ")) WHERE canvas_id = ?"
        values.append(id)
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ CanvasManager: Failed to prepare update canvas statement")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        
        for (index, value) in values.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }
        
        let success = sqlite3_step(stmt) == SQLITE_DONE
        if success {
            logger.info("✅ CanvasManager: Updated canvas: \(id)")
        } else {
            logger.error("❌ CanvasManager: Failed to update canvas: \(id)")
        }
        return success
    }
    
    /// Delete a canvas
    func deleteCanvas(id: String) -> Bool {
        guard let db = try? database.open() else {
            logger.error("❌ CanvasManager: Failed to open database")
            return false
        }
        defer { sqlite3_close(db) }
        
        let sql = "DELETE FROM canvases WHERE canvas_id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ CanvasManager: Failed to prepare delete canvas statement")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        
        let success = sqlite3_step(stmt) == SQLITE_DONE
        if success {
            logger.info("✅ CanvasManager: Deleted canvas: \(id)")
        } else {
            logger.error("❌ CanvasManager: Failed to delete canvas: \(id)")
        }
        return success
    }
    
    /// Search canvases by name
    func searchCanvases(query: String, type: CanvasType? = nil) -> [Canvas] {
        guard let db = try? database.open() else {
            logger.error("❌ CanvasManager: Failed to open database")
            return []
        }
        defer { sqlite3_close(db) }
        
        let sql: String
        if let type = type {
            sql = "SELECT * FROM canvases WHERE canvas_name LIKE ? AND canvas_type = ? ORDER BY date_updated DESC"
        } else {
            sql = "SELECT * FROM canvases WHERE canvas_name LIKE ? ORDER BY date_updated DESC"
        }
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ CanvasManager: Failed to prepare search canvases statement")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        let searchPattern = "%\(query)%"
        sqlite3_bind_text(stmt, 1, searchPattern, -1, SQLITE_TRANSIENT)
        if let type = type {
            sqlite3_bind_text(stmt, 2, type.rawValue, -1, SQLITE_TRANSIENT)
        }
        
        var canvases: [Canvas] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let canvas = canvasFromRow(stmt) {
                canvases.append(canvas)
            }
        }
        
        return canvases
    }
    
    // MARK: - Element Operations
    
    /// Add an element to a canvas
    func addElement(canvasId: String, element: CanvasElement) -> Bool {
        guard let canvas = getCanvas(id: canvasId) else {
            logger.error("❌ CanvasManager: Canvas not found: \(canvasId)")
            return false
        }
        
        var updatedElements = canvas.elements
        updatedElements.append(element)
        
        return updateCanvas(id: canvasId, updates: [
            "canvas_elements": updatedElements.map { $0.toDatabaseFormat() }
        ])
    }
    
    /// Update an element in a canvas
    func updateElement(canvasId: String, elementId: String, element: CanvasElement) -> Bool {
        guard let canvas = getCanvas(id: canvasId) else {
            logger.error("❌ CanvasManager: Canvas not found: \(canvasId)")
            return false
        }
        
        var updatedElements = canvas.elements
        if let index = updatedElements.firstIndex(where: { $0.id == elementId }) {
            updatedElements[index] = element
        } else {
            logger.error("❌ CanvasManager: Element not found: \(elementId)")
            return false
        }
        
        return updateCanvas(id: canvasId, updates: [
            "canvas_elements": updatedElements.map { $0.toDatabaseFormat() }
        ])
    }
    
    /// Remove an element from a canvas
    func removeElement(canvasId: String, elementId: String) -> Bool {
        guard let canvas = getCanvas(id: canvasId) else {
            logger.error("❌ CanvasManager: Canvas not found: \(canvasId)")
            return false
        }
        
        let updatedElements = canvas.elements.filter { $0.id != elementId }
        
        return updateCanvas(id: canvasId, updates: [
            "canvas_elements": updatedElements.map { $0.toDatabaseFormat() }
        ])
    }
    
    // MARK: - Helper Methods
    
    private func ensureCanvasesTable(db: OpaquePointer?) {
        let sql = """
        CREATE TABLE IF NOT EXISTS canvases (
            canvas_id TEXT PRIMARY KEY,
            canvas_name TEXT NOT NULL,
            canvas_elements TEXT NOT NULL DEFAULT '[]',
            element_counts TEXT NOT NULL DEFAULT '{}',
            date_created TEXT NOT NULL,
            date_updated TEXT NOT NULL,
            last_saved TEXT,
            canvas_type TEXT NOT NULL DEFAULT 'group_map',
            canvas_state TEXT DEFAULT '{}',
            metadata TEXT DEFAULT '{}'
        )
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        
        // Create indexes
        let indexes = [
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_canvases_id ON canvases(canvas_id)",
            "CREATE INDEX IF NOT EXISTS idx_canvases_name ON canvases(canvas_name)",
            "CREATE INDEX IF NOT EXISTS idx_canvases_type ON canvases(canvas_type)",
            "CREATE INDEX IF NOT EXISTS idx_canvases_created ON canvases(date_created)",
            "CREATE INDEX IF NOT EXISTS idx_canvases_updated ON canvases(date_updated)",
            "CREATE INDEX IF NOT EXISTS idx_canvases_type_updated ON canvases(canvas_type, date_updated)"
        ]
        
        for indexSQL in indexes {
            if sqlite3_prepare_v2(db, indexSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }
    
    private func canvasFromRow(_ stmt: OpaquePointer?) -> Canvas? {
        guard let stmt = stmt else { return nil }
        
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let name = String(cString: sqlite3_column_text(stmt, 1))
        
        let elementsData = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0).data(using: .utf8) }
        let elements: [CanvasElement]
        if let elementsData = elementsData,
           let elementsArray = try? JSONSerialization.jsonObject(with: elementsData) as? [[String: Any]] {
            elements = elementsArray.compactMap { CanvasElement.fromDatabaseFormat($0) }
        } else {
            elements = []
        }
        
        let dateCreated = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) }
        let dateUpdated = sqlite3_column_text(stmt, 5).flatMap { String(cString: $0) }
        let lastSaved = sqlite3_column_text(stmt, 6).flatMap { String(cString: $0) }
        
        let canvasTypeStr = String(cString: sqlite3_column_text(stmt, 7))
        let canvasType = CanvasType(rawValue: canvasTypeStr) ?? .groupMap
        
        let stateData = sqlite3_column_text(stmt, 8).flatMap { String(cString: $0).data(using: .utf8) }
        let canvasState: CanvasState
        if let stateData = stateData,
           let stateDict = try? JSONSerialization.jsonObject(with: stateData) as? [String: Any] {
            canvasState = CanvasState.fromDatabaseFormat(stateDict)
        } else {
            canvasState = CanvasState()
        }
        
        let metadataData = sqlite3_column_text(stmt, 9).flatMap { String(cString: $0).data(using: .utf8) }
        var metadata: [String: String] = [:]
        if let metadataData = metadataData,
           let metadataDict = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] {
            // Convert [String: Any] to [String: String]
            metadata = metadataDict.compactMapValues { String(describing: $0) }
        }
        
        let dateFormatter = ISO8601DateFormatter()
        
        var canvas = Canvas(
            id: id,
            name: name,
            elements: elements,
            canvasType: canvasType,
            canvasState: canvasState
        )
        
        if let dateCreatedStr = dateCreated,
           let date = dateFormatter.date(from: dateCreatedStr) {
            canvas.dateCreated = date
        }
        if let dateUpdatedStr = dateUpdated,
           let date = dateFormatter.date(from: dateUpdatedStr) {
            canvas.dateUpdated = date
        }
        if let lastSavedStr = lastSaved,
           let date = dateFormatter.date(from: lastSavedStr) {
            canvas.lastSaved = date
        }
        canvas.metadata = metadata
        
        return canvas
    }
    
    private func calculateElementCounts(elements: [CanvasElement]) -> [String: Int] {
        var counts = ["contacts": 0, "groups": 0, "custom": 0, "all": elements.count]
        
        for element in elements {
            switch element.elementType {
            case .contact:
                counts["contacts", default: 0] += 1
            case .group:
                counts["groups", default: 0] += 1
            case .custom:
                counts["custom", default: 0] += 1
            }
        }
        
        return counts
    }
    
    private func jsonString(from object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

