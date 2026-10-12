import Foundation
import Darwin
import SQLite3

/// Group participant structure matching database format
struct GroupParticipant: Codable {
    var id: String  // phone number
    var name: String
    var UUID: String
    var Source: [ParticipantSource]?
    
    struct ParticipantSource: Codable {
        var `Type`: String  // Backticks escape reserved word
        var UUID: String
    }
}

/// Manages group database operations - Pure Swift replacement for Python group operations
final class GroupManager {
    private let logger = LogManager.shared
    private let database = CRMDatabase.shared
    
    // MARK: - Group CRUD Operations
    
    /// Create a new group and return its database ID
    func createGroup(name: String, color: String, participants: [GroupParticipant] = [], canvases: [String] = []) -> Int? {
        guard let db = try? database.open() else {
            logger.error("❌ GroupManager: Failed to open database")
            return nil
        }
        defer { sqlite3_close(db) }
        
        ensureGroupsTable(db: db)
        
        let dateFormatter = ISO8601DateFormatter()
        let now = dateFormatter.string(from: Date())
        
        let participantsJSON = jsonString(from: participants.map { try? $0.asDictionary() } .compactMap { $0 })
        let canvasesJSON = jsonString(from: canvases)
        
        let sql = """
        INSERT INTO groups (name, color, created_at, participants, canvases, id)
        VALUES (?, ?, ?, ?, ?, NULL)
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ GroupManager: Failed to prepare create group statement")
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, color, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, now, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, participantsJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, canvasesJSON, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_DONE {
            let groupId = Int(sqlite3_last_insert_rowid(db))
            logger.info("✅ GroupManager: Created group: \(name) with ID: \(groupId)")
            return groupId
        } else {
            logger.error("❌ GroupManager: Failed to create group: \(name)")
            return nil
        }
    }
    
    /// Get a group by ID
    func getGroup(id: String) -> [String: Any]? {
        guard let db = try? database.open() else {
            logger.error("❌ GroupManager: Failed to open database")
            return nil
        }
        defer { sqlite3_close(db) }
        
        let sql = """
        SELECT id, name, color, created_at, parent_id, member_phones,
               linked_group_ids, metadata, is_deck, participants, canvases,
               size, tags, child_group_ids, parent_group_ids
        FROM groups WHERE id = ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ GroupManager: Failed to prepare get group statement")
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return groupFromRow(stmt)
        }
        
        return nil
    }
    
    /// Get a group by name
    func getGroupByName(name: String) -> [String: Any]? {
        guard let db = try? database.open() else {
            logger.error("❌ GroupManager: Failed to open database")
            return nil
        }
        defer { sqlite3_close(db) }
        
        let sql = """
        SELECT id, name, color, created_at, parent_id, member_phones,
               linked_group_ids, metadata, is_deck, participants, canvases,
               size, tags, child_group_ids, parent_group_ids
        FROM groups WHERE name = ?
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ GroupManager: Failed to prepare get group by name statement")
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return groupFromRow(stmt)
        }
        
        return nil
    }
    
    /// Get all groups
    func getAllGroups() -> [[String: Any]] {
        guard let db = try? database.open() else {
            logger.error("❌ GroupManager: Failed to open database")
            return []
        }
        defer { sqlite3_close(db) }
        
        let sql = """
        SELECT id, name, color, created_at, parent_id, member_phones,
               linked_group_ids, metadata, is_deck, participants, canvases,
               size, tags, child_group_ids, parent_group_ids
        FROM groups
        ORDER BY created_at DESC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ GroupManager: Failed to prepare get all groups statement")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        
        var groups: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let group = groupFromRow(stmt) {
                groups.append(group)
            }
        }
        
        return groups
    }
    
    /// Update a group
    func updateGroup(id: String, updates: [String: Any]) -> Bool {
        guard let db = try? database.open() else {
            logger.error("❌ GroupManager: Failed to open database")
            return false
        }
        defer { sqlite3_close(db) }
        
        guard !updates.isEmpty else { return true }
        
        var setClauses: [String] = []
        var values: [String] = []
        
        let jsonKeys = ["participants", "canvases", "member_phones", "linked_group_ids", "metadata", "tags", "child_group_ids", "parent_group_ids"]
        
        for (key, value) in updates {
            setClauses.append("\(key) = ?")
            
            if jsonKeys.contains(key) {
                // Convert to JSON string
                if let jsonValue = value as? [Any] {
                    values.append(jsonString(from: jsonValue))
                } else if let jsonValue = value as? [String: Any] {
                    values.append(jsonString(from: jsonValue))
                } else {
                    values.append(jsonString(from: value))
                }
            } else {
                values.append(String(describing: value))
            }
        }
        
        values.append(id)
        
        let sql = "UPDATE groups SET \(setClauses.joined(separator: ", ")) WHERE id = ?"
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ GroupManager: Failed to prepare update group statement")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        
        for (index, value) in values.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }
        
        let success = sqlite3_step(stmt) == SQLITE_DONE
        if success {
            logger.info("✅ GroupManager: Updated group: \(id)")
        } else {
            logger.error("❌ GroupManager: Failed to update group: \(id)")
        }
        return success
    }
    
    /// Delete a group
    func deleteGroup(id: String) -> Bool {
        guard let db = try? database.open() else {
            logger.error("❌ GroupManager: Failed to open database")
            return false
        }
        defer { sqlite3_close(db) }
        
        let sql = "DELETE FROM groups WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ GroupManager: Failed to prepare delete group statement")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        
        let success = sqlite3_step(stmt) == SQLITE_DONE
        if success {
            logger.info("✅ GroupManager: Deleted group: \(id)")
        } else {
            logger.error("❌ GroupManager: Failed to delete group: \(id)")
        }
        return success
    }
    
    // MARK: - Group Membership Operations
    
    /// Update group membership for a contact (add or remove)
    func updateGroupMembership(contactId: Int, groupId: Int, operation: String) -> Bool {
        guard let db = try? database.open() else {
            logger.error("❌ GroupManager: Failed to open database")
            return false
        }
        defer { sqlite3_close(db) }
        
        // This function is more complex - it needs to be implemented based on actual usage
        // For now, return true and log a warning
        logger.warning("⚠️ GroupManager: updateGroupMembership called but not fully implemented")
        return true
    }
    
    /// Update group participants - MERGES new participants with existing ones using source-based tracking
    func updateGroupParticipants(groupId: String, participants: [GroupParticipant]) -> Bool {
        guard let db = try? database.open() else {
            logger.error("❌ GroupManager: Failed to open database")
            return false
        }
        defer { sqlite3_close(db) }
        
        // Get existing participants
        guard let groupIdInt = Int(groupId) else {
            logger.error("❌ GroupManager: Invalid group ID: \(groupId)")
            return false
        }
        
        let sql = "SELECT participants FROM groups WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ GroupManager: Failed to prepare get participants statement")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(groupIdInt))
        
        var existingParticipants: [GroupParticipant] = []
        if sqlite3_step(stmt) == SQLITE_ROW,
           let participantsStr = sqlite3_column_text(stmt, 0) {
            let participantsJSON = String(cString: participantsStr)
            if let data = participantsJSON.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([GroupParticipant].self, from: data) {
                existingParticipants = decoded
            }
        }
        
        // Merge participants by ID
        var participantsDict: [String: GroupParticipant] = [:]
        for participant in existingParticipants {
            participantsDict[participant.id] = participant
        }
        
        // Merge new participants with existing ones
        for newParticipant in participants {
            if var existing = participantsDict[newParticipant.id] {
                // Merge sources
                var existingSources = existing.Source ?? []
                let newSources = newParticipant.Source ?? []
                
                for newSource in newSources {
                    let sourceExists = existingSources.contains { source in
                        source.Type == newSource.Type && source.UUID == newSource.UUID
                    }
                    if !sourceExists {
                        existingSources.append(newSource)
                        logger.info("✅ GroupManager: Added source \(newSource.Type):\(newSource.UUID) to participant \(newParticipant.id)")
                    }
                }
                
                existing.Source = existingSources
                existing.name = newParticipant.name
                existing.UUID = newParticipant.UUID
                participantsDict[newParticipant.id] = existing
            } else {
                participantsDict[newParticipant.id] = newParticipant
                logger.info("✅ GroupManager: Added new participant \(newParticipant.id) to group \(groupId)")
            }
        }
        
        let updatedParticipants = Array(participantsDict.values)
        let newSize = updatedParticipants.count
        
        let dateFormatter = ISO8601DateFormatter()
        let now = dateFormatter.string(from: Date())
        
        let participantsJSON = jsonString(from: updatedParticipants.map { try? $0.asDictionary() }.compactMap { $0 })
        
        let updateSQL = "UPDATE groups SET participants = ?, size = ?, time_last_updated = ? WHERE id = ?"
        var updateStmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil)
        guard prepareResult == SQLITE_OK else {
            let diagnostics = sqliteDiagnostics(
                db: db,
                context: "updateGroupParticipants.prepare",
                sqliteRC: prepareResult
            )
            logger.error("❌ GroupManager: Failed to prepare update participants statement (\(diagnostics))")
            return false
        }
        defer { sqlite3_finalize(updateStmt) }
        
        sqlite3_bind_text(updateStmt, 1, participantsJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(updateStmt, 2, Int32(newSize))
        sqlite3_bind_text(updateStmt, 3, now, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(updateStmt, 4, Int32(groupIdInt))
        
        let stepResult = sqlite3_step(updateStmt)
        let success = stepResult == SQLITE_DONE
        if success {
            logger.info("✅ GroupManager: Updated group participants: group \(groupId) now has \(newSize) participants")
        } else {
            let diagnostics = sqliteDiagnostics(
                db: db,
                context: "updateGroupParticipants.step",
                sqliteRC: stepResult
            )
            logger.error("❌ GroupManager: Failed to update group participants (\(diagnostics))")
        }
        return success
    }
    
    /// Remove specific sources from participants - removes participant if no sources remain
    func removeGroupParticipantSource(groupId: String, participantsToRemove: [GroupParticipant]) -> Bool {
        guard let db = try? database.open() else {
            logger.error("❌ GroupManager: Failed to open database")
            return false
        }
        defer { sqlite3_close(db) }
        
        guard let groupIdInt = Int(groupId) else {
            logger.error("❌ GroupManager: Invalid group ID: \(groupId)")
            return false
        }
        
        // Get existing participants
        let sql = "SELECT participants FROM groups WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ GroupManager: Failed to prepare get participants statement")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int(stmt, 1, Int32(groupIdInt))
        
        var existingParticipants: [GroupParticipant] = []
        if sqlite3_step(stmt) == SQLITE_ROW,
           let participantsStr = sqlite3_column_text(stmt, 0) {
            let participantsJSON = String(cString: participantsStr)
            if let data = participantsJSON.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([GroupParticipant].self, from: data) {
                existingParticipants = decoded
            }
        }
        
        // Build dict by participant ID
        var participantsDict: [String: GroupParticipant] = [:]
        for participant in existingParticipants {
            participantsDict[participant.id] = participant
        }
        
        // Remove specified sources
        for removalData in participantsToRemove {
            if var existing = participantsDict[removalData.id] {
                var existingSources = existing.Source ?? []
                let sourcesToRemove = removalData.Source ?? []
                
                // Filter out sources that should be removed
                existingSources = existingSources.filter { existingSource in
                    !sourcesToRemove.contains { removeSource in
                        existingSource.Type == removeSource.Type && existingSource.UUID == removeSource.UUID
                    }
                }
                
                if existingSources.isEmpty {
                    // No sources remaining, remove participant entirely
                    participantsDict.removeValue(forKey: removalData.id)
                    logger.info("✅ GroupManager: Removed participant \(removalData.id) from group \(groupId) (no sources remaining)")
                } else {
                    existing.Source = existingSources
                    participantsDict[removalData.id] = existing
                    logger.info("✅ GroupManager: Updated participant \(removalData.id) with \(existingSources.count) remaining sources")
                }
            }
        }
        
        let updatedParticipants = Array(participantsDict.values)
        let newSize = updatedParticipants.count
        
        let dateFormatter = ISO8601DateFormatter()
        let now = dateFormatter.string(from: Date())
        
        let participantsJSON = jsonString(from: updatedParticipants.map { try? $0.asDictionary() }.compactMap { $0 })
        
        let updateSQL = "UPDATE groups SET participants = ?, size = ?, time_last_updated = ? WHERE id = ?"
        var updateStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else {
            logger.error("❌ GroupManager: Failed to prepare remove sources statement")
            return false
        }
        defer { sqlite3_finalize(updateStmt) }
        
        sqlite3_bind_text(updateStmt, 1, participantsJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(updateStmt, 2, Int32(newSize))
        sqlite3_bind_text(updateStmt, 3, now, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(updateStmt, 4, Int32(groupIdInt))
        
        let success = sqlite3_step(updateStmt) == SQLITE_DONE
        if success {
            logger.info("✅ GroupManager: Removed sources from group participants: group \(groupId) now has \(newSize) participants")
        } else {
            logger.error("❌ GroupManager: Failed to remove participant sources")
        }
        return success
    }
    
    // MARK: - Canvas Association Operations
    
    /// Add a group to a canvas
    func addGroupToCanvas(groupId: String, canvasId: String) -> Bool {
        guard let group = getGroup(id: groupId) else {
            logger.error("❌ GroupManager: Group not found: \(groupId)")
            return false
        }
        
        var canvases = (group["canvases"] as? [String]) ?? []
        if !canvases.contains(canvasId) {
            canvases.append(canvasId)
            return updateGroup(id: groupId, updates: ["canvases": canvases])
        }
        
        return true
    }
    
    /// Remove a group from a canvas
    func removeGroupFromCanvas(groupId: String, canvasId: String) -> Bool {
        guard let group = getGroup(id: groupId) else {
            logger.error("❌ GroupManager: Group not found: \(groupId)")
            return false
        }
        
        var canvases = (group["canvases"] as? [String]) ?? []
        canvases.removeAll { $0 == canvasId }
        return updateGroup(id: groupId, updates: ["canvases": canvases])
    }
    
    // MARK: - Utility Operations
    
    /// Get the next available group name (Group 1, Group 2, etc.) - reuses missing numbers
    func getNextGroupName() -> String {
        guard let db = try? database.open() else {
            logger.error("❌ GroupManager: Failed to open database")
            return "Group 1"
        }
        defer { sqlite3_close(db) }
        
        let sql = "SELECT name FROM groups WHERE name LIKE 'Group %' ORDER BY name"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ GroupManager: Failed to prepare get next group name statement")
            return "Group 1"
        }
        defer { sqlite3_finalize(stmt) }
        
        var existingNumbers: [Int] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let nameStr = sqlite3_column_text(stmt, 0) {
                let name = String(cString: nameStr)
                if let number = Int(name.replacingOccurrences(of: "Group ", with: "")) {
                    existingNumbers.append(number)
                }
            }
        }
        
        guard !existingNumbers.isEmpty else {
            return "Group 1"
        }
        
        existingNumbers.sort()
        var expectedNumber = 1
        
        for existingNumber in existingNumbers {
            if existingNumber == expectedNumber {
                expectedNumber += 1
            } else if existingNumber > expectedNumber {
                break
            }
        }
        
        return "Group \(expectedNumber)"
    }
    
    /// Verify a contact exists (used when adding contacts to canvas)
    func verifyContactExists(contactId: String) -> Bool {
        guard let db = try? database.open() else {
            logger.error("❌ GroupManager: Failed to open database")
            return false
        }
        defer { sqlite3_close(db) }
        
        let sql = "SELECT id FROM contacts WHERE phone = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("❌ GroupManager: Failed to prepare verify contact statement")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, contactId, -1, SQLITE_TRANSIENT)
        
        return sqlite3_step(stmt) == SQLITE_ROW
    }
    
    // MARK: - Helper Methods
    
    private func ensureGroupsTable(db: OpaquePointer?) {
        // CRITICAL: Schema must match SQLiteDataProvider.swift
        // id is TEXT (stores string representation of integers) not INTEGER
        // This allows UUID-based identification while maintaining integer database IDs
        let sql = """
        CREATE TABLE IF NOT EXISTS groups (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            color TEXT NOT NULL,
            created_at TEXT NOT NULL,
            parent_id TEXT,
            member_phones TEXT DEFAULT '[]',
            linked_group_ids TEXT,
            metadata TEXT,
            is_deck INTEGER DEFAULT 0,
            participants TEXT DEFAULT '[]',
            canvases TEXT DEFAULT '[]',
            size INTEGER DEFAULT 0,
            tags TEXT DEFAULT '[]',
            child_group_ids TEXT DEFAULT '[]',
            parent_group_ids TEXT DEFAULT '[]'
        )
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_DONE {
                print("✅ GroupManager: Groups table ensured")
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                print("❌ GroupManager: Failed to create groups table: \(errorMessage)")
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ GroupManager: Failed to prepare CREATE TABLE: \(errorMessage)")
        }
        sqlite3_finalize(stmt)
    }
    
    private func groupFromRow(_ stmt: OpaquePointer?) -> [String: Any]? {
        guard let stmt = stmt else { return nil }
        
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let name = String(cString: sqlite3_column_text(stmt, 1))
        let color = String(cString: sqlite3_column_text(stmt, 2))
        let createdAt = String(cString: sqlite3_column_text(stmt, 3))
        
        let parentId = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) }
        
        let memberPhones: [String]
        if let memberPhonesStr = sqlite3_column_text(stmt, 5),
           let data = String(cString: memberPhonesStr).data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            memberPhones = decoded
        } else {
            memberPhones = []
        }
        
        let linkedGroupIds: [String]
        if let linkedGroupIdsStr = sqlite3_column_text(stmt, 6),
           let data = String(cString: linkedGroupIdsStr).data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            linkedGroupIds = decoded
        } else {
            linkedGroupIds = []
        }
        
        let metadata: [String: Any]
        if let metadataStr = sqlite3_column_text(stmt, 7),
           let data = String(cString: metadataStr).data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            metadata = decoded
        } else {
            metadata = [:]
        }
        
        let isDeck = sqlite3_column_int(stmt, 8) == 1
        
        let participants: [[String: Any]]
        if let participantsStr = sqlite3_column_text(stmt, 9),
           let data = String(cString: participantsStr).data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            participants = decoded
        } else {
            participants = []
        }
        
        let canvases: [String]
        if let canvasesStr = sqlite3_column_text(stmt, 10),
           let data = String(cString: canvasesStr).data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            canvases = decoded
        } else {
            canvases = []
        }
        
        let size = Int(sqlite3_column_int(stmt, 11))
        
        let tags: [String]
        if let tagsStr = sqlite3_column_text(stmt, 12),
           let data = String(cString: tagsStr).data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            tags = decoded
        } else {
            tags = []
        }
        
        let childGroups: [String]
        if let childrenStr = sqlite3_column_text(stmt, 13),
           let data = String(cString: childrenStr).data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            childGroups = decoded
        } else {
            childGroups = []
        }
        
        let parentGroups: [String]
        if let parentsStr = sqlite3_column_text(stmt, 14),
           let data = String(cString: parentsStr).data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            parentGroups = decoded
        } else {
            parentGroups = []
        }
        
        return [
            "id": id,
            "name": name,
            "color": color,
            "created_at": createdAt,
            "parent_id": parentId as Any,
            "member_phones": memberPhones,
            "linked_group_ids": linkedGroupIds,
            "metadata": metadata,
            "is_deck": isDeck,
            "participants": participants,
            "canvases": canvases,
            "size": size,
            "tags": tags,
            "child_group_ids": childGroups,
            "parent_group_ids": parentGroups
        ]
    }
    
    // MARK: - Diagnostics
    
    private func sqliteDiagnostics(db: OpaquePointer?, context: String, sqliteRC: Int32? = nil) -> String {
        let databasePath = SettingsManager.shared.settings.database.path
        var components: [String] = ["context=\(context)", "path=\(databasePath)"]
        
        if let rc = sqliteRC {
            components.append("rc=\(rc)")
        }
        
        if let db = db {
            let extendedCode = sqlite3_extended_errcode(db)
            let message = String(cString: sqlite3_errmsg(db))
            components.append("extended=\(extendedCode)")
            components.append("message=\(message)")
        } else {
            components.append("message=database nil")
        }
        
        let errnoCode = errno
        components.append("errno=\(errnoCode)")
        if let posixCode = POSIXErrorCode(rawValue: errnoCode) {
            components.append("errnoSymbol=\(posixCode)")
        }
        
        components.append(contentsOf: fileDiagnostics(for: databasePath))
        return components.joined(separator: ", ")
    }
    
    private func fileDiagnostics(for databasePath: String) -> [String] {
        var details: [String] = []
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: databasePath) {
            if let attributes = try? fileManager.attributesOfItem(atPath: databasePath) {
                if let size = attributes[.size] as? NSNumber {
                    details.append("dbBytes=\(size.int64Value)")
                }
                if let permissions = attributes[.posixPermissions] as? NSNumber {
                    details.append(String(format: "dbPerms=%o", permissions.intValue))
                }
                if let owner = attributes[.ownerAccountName] as? String {
                    details.append("dbOwner=\(owner)")
                }
            }
        } else {
            details.append("dbExists=false")
        }
        
        let walPath = databasePath + "-wal"
        if fileManager.fileExists(atPath: walPath) {
            if let attributes = try? fileManager.attributesOfItem(atPath: walPath),
               let size = attributes[.size] as? NSNumber {
                details.append("walBytes=\(size.int64Value)")
            }
        } else {
            details.append("walMissing=true")
        }
        
        let shmPath = databasePath + "-shm"
        if fileManager.fileExists(atPath: shmPath) {
            if let attributes = try? fileManager.attributesOfItem(atPath: shmPath),
               let size = attributes[.size] as? NSNumber {
                details.append("shmBytes=\(size.int64Value)")
            }
        } else {
            details.append("shmMissing=true")
        }
        
        let databaseURL = URL(fileURLWithPath: databasePath)
        let resourceKeys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
            .volumeLocalizedNameKey
        ]
        if let resourceValues = try? databaseURL.resourceValues(forKeys: resourceKeys) {
            if let available = resourceValues.volumeAvailableCapacityForImportantUsage {
                details.append("volumeAvailableMB=\(available / 1_048_576)")
            }
            if let total = resourceValues.volumeTotalCapacity {
                details.append("volumeTotalMB=\(total / 1_048_576)")
            }
            if let volumeName = resourceValues.volumeLocalizedName {
                details.append("volume=\"\(volumeName)\"")
            }
        }
        
        return details
    }
    
    private func jsonString(from object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}

// MARK: - Encodable Extension for GroupParticipant

extension Encodable {
    func asDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let dictionary = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] else {
            throw NSError(domain: "EncodingError", code: 1, userInfo: nil)
        }
        return dictionary
    }
}

