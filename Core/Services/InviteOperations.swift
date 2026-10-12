import Foundation
import SQLite3

// MARK: - Invite CRUD Operations Extension for SQLiteDataProvider

extension SQLiteDataProvider {
    
    // MARK: - Invite CRUD Operations
    
    func fetchInvites(offset: Int, limit: Int, filter: InviteFilter) async throws -> [Invite] {
        var filteredInvites = invites
        
        // Apply search filter
        if !filter.searchTerm.isEmpty {
            filteredInvites = invites.filter { invite in
                invite.title.localizedCaseInsensitiveContains(filter.searchTerm) ||
                invite.description?.localizedCaseInsensitiveContains(filter.searchTerm) == true ||
                invite.toPhone?.localizedCaseInsensitiveContains(filter.searchTerm) == true ||
                invite.fromPhone?.localizedCaseInsensitiveContains(filter.searchTerm) == true
            }
        }
        
        // Apply status filter
        if let status = filter.status {
            filteredInvites = filteredInvites.filter { $0.completionStatus == status }
        }
        
        // Apply priority filter
        if let priority = filter.priority {
            filteredInvites = filteredInvites.filter { $0.priority == priority }
        }
        
        // Apply sent/received filter
        if let sentReceived = filter.sentReceived {
            filteredInvites = filteredInvites.filter { $0.sentReceived == sentReceived }
        }
        
        // Apply recurring filter
        if let isRecurring = filter.isRecurring {
            filteredInvites = filteredInvites.filter { $0.isRecurring == isRecurring }
        }
        
        // Apply due date range filter
        if let dateRange = filter.dueDateRange {
            filteredInvites = filteredInvites.filter { invite in
                guard let dueDate = invite.dueDate else { return false }
                return dateRange.contains(dueDate)
            }
        }
        
        // Apply contact filter
        if let contactPhone = filter.contactPhone {
            filteredInvites = filteredInvites.filter { invite in
                invite.toPhone == contactPhone || invite.fromPhone == contactPhone
            }
        }
        
        // Apply sorting
        switch filter.sortBy {
        case .title:
            filteredInvites.sort { $0.title < $1.title }
        case .dueDate:
            filteredInvites.sort { ($0.dueDate ?? Date.distantFuture) < ($1.dueDate ?? Date.distantFuture) }
        case .priority:
            filteredInvites.sort { $0.priority.rawValue > $1.priority.rawValue }
        case .creationDate:
            filteredInvites.sort { $0.creationDate > $1.creationDate }
        case .lastModified:
            filteredInvites.sort { $0.lastModifiedDate > $1.lastModifiedDate }
        case .status:
            filteredInvites.sort { $0.completionStatus.rawValue < $1.completionStatus.rawValue }
        }
        
        // Apply sort order
        if filter.sortOrder == .reverse {
            filteredInvites.reverse()
        }
        
        // Apply pagination
        let endIndex = min(offset + limit, filteredInvites.count)
        let startIndex = min(offset, filteredInvites.count)
        
        return Array(filteredInvites[startIndex..<endIndex])
    }
    
    func countInvites(filter: InviteFilter) async throws -> Int {
        var filteredInvites = invites
        
        // Apply same filters as fetchInvites but without pagination
        if !filter.searchTerm.isEmpty {
            filteredInvites = invites.filter { invite in
                invite.title.localizedCaseInsensitiveContains(filter.searchTerm) ||
                invite.description?.localizedCaseInsensitiveContains(filter.searchTerm) == true ||
                invite.toPhone?.localizedCaseInsensitiveContains(filter.searchTerm) == true ||
                invite.fromPhone?.localizedCaseInsensitiveContains(filter.searchTerm) == true
            }
        }
        
        if let status = filter.status {
            filteredInvites = filteredInvites.filter { $0.completionStatus == status }
        }
        
        if let priority = filter.priority {
            filteredInvites = filteredInvites.filter { $0.priority == priority }
        }
        
        if let sentReceived = filter.sentReceived {
            filteredInvites = filteredInvites.filter { $0.sentReceived == sentReceived }
        }
        
        if let isRecurring = filter.isRecurring {
            filteredInvites = filteredInvites.filter { $0.isRecurring == isRecurring }
        }
        
        if let dateRange = filter.dueDateRange {
            filteredInvites = filteredInvites.filter { invite in
                guard let dueDate = invite.dueDate else { return false }
                return dateRange.contains(dueDate)
            }
        }
        
        if let contactPhone = filter.contactPhone {
            filteredInvites = filteredInvites.filter { invite in
                invite.toPhone == contactPhone || invite.fromPhone == contactPhone
            }
        }
        
        return filteredInvites.count
    }
    
    func fetchInvite(by id: UUID) async throws -> Invite? {
        return invites.first { $0.id == id }
    }
    
    nonisolated func getInvite(by id: UUID) -> Invite? {
        return MainActor.assumeIsolated {
            invites.first { $0.id == id }
        }
    }
    
    func createInvite(_ invite: Invite) async throws {
        invites.append(invite)
        await saveInviteToDatabase(invite)
    }
    
    func updateInvite(_ invite: Invite) async throws {
        if let index = invites.firstIndex(where: { $0.id == invite.id }) {
            invites[index] = invite
            await saveInviteToDatabase(invite)
        } else {
            throw DataProviderError.inviteNotFound
        }
    }
    
    func deleteInvite(_ id: UUID) async throws {
        invites.removeAll { $0.id == id }
        await deleteInviteFromDatabase(id)
    }
    
    func markInviteComplete(_ id: UUID) async throws {
        if let index = invites.firstIndex(where: { $0.id == id }) {
            invites[index].completed = true
            invites[index].completionStatus = .completed
            invites[index].dateCompleted = Date()
            invites[index].lastModifiedDate = Date()
            await saveInviteToDatabase(invites[index])
        } else {
            throw DataProviderError.inviteNotFound
        }
    }
    
    func markInviteIncomplete(_ id: UUID) async throws {
        if let index = invites.firstIndex(where: { $0.id == id }) {
            invites[index].completed = false
            invites[index].completionStatus = .pending
            invites[index].dateCompleted = nil
            invites[index].lastModifiedDate = Date()
            await saveInviteToDatabase(invites[index])
        } else {
            throw DataProviderError.inviteNotFound
        }
    }
    
    func fetchInvitesByContact(phone: String) async throws -> [Invite] {
        return invites.filter { invite in
            invite.toPhone == phone || invite.fromPhone == phone
        }
    }
    
    func fetchRecurringInvites() async throws -> [Invite] {
        return invites.filter { $0.isRecurring }
    }
    
    func fetchOverdueInvites() async throws -> [Invite] {
        return invites.filter { $0.isOverdue }
    }
    
    func fetchInvitesDueToday() async throws -> [Invite] {
        return invites.filter { $0.isDueToday }
    }
    
    func fetchInvitesByMessage(guid: String) async throws -> [Invite] {
        return invites.filter { $0.messageOriginGuid == guid }
    }
    
    // MARK: - Database Write Operations for Invites
    
    private func saveInviteToDatabase(_ invite: Invite) async {
        guard let db = database else { return }
        
        let query = """
        INSERT OR REPLACE INTO invites 
        (id, title, description, creation_date, last_modified_date, date_completed, completed, completion_status, sent_received, to_phone, from_phone, priority, due_date, parent_tasks, child_tasks, tags, groups, task_group, ai_processed, ai_suggestions, ai_confidence, reminder_date, message_origin_guid, is_recurring, recurrence_type, next_task_id, previous_task_id, is_next_task, date_of_last_task, created_by, assigned_to, category, location, estimated_duration, attachments, external_id, last_ai_analysis)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            let formatter = ISO8601DateFormatter()
            
            sqlite3_bind_text(statement, 1, invite.id.uuidString, -1, nil)
            sqlite3_bind_text(statement, 2, invite.title, -1, nil)
            sqlite3_bind_text(statement, 3, invite.description, -1, nil)
            sqlite3_bind_text(statement, 4, formatter.string(from: invite.creationDate), -1, nil)
            sqlite3_bind_text(statement, 5, formatter.string(from: invite.lastModifiedDate), -1, nil)
            sqlite3_bind_text(statement, 6, invite.dateCompleted.map { formatter.string(from: $0) }, -1, nil)
            sqlite3_bind_int(statement, 7, invite.completed ? 1 : 0)
            sqlite3_bind_text(statement, 8, invite.completionStatus.rawValue, -1, nil)
            sqlite3_bind_text(statement, 9, invite.sentReceived.rawValue, -1, nil)
            sqlite3_bind_text(statement, 10, invite.toPhone, -1, nil)
            sqlite3_bind_text(statement, 11, invite.fromPhone, -1, nil)
            sqlite3_bind_int(statement, 12, Int32(invite.priority.rawValue))
            sqlite3_bind_text(statement, 13, invite.dueDate.map { formatter.string(from: $0) }, -1, nil)
            
            // Convert arrays to JSON
            let parentTasksJson = try? JSONSerialization.data(withJSONObject: invite.parentTasks.map { $0.uuidString })
            let parentTasksString = parentTasksJson.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            sqlite3_bind_text(statement, 14, parentTasksString, -1, nil)
            
            let childTasksJson = try? JSONSerialization.data(withJSONObject: invite.childTasks.map { $0.uuidString })
            let childTasksString = childTasksJson.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            sqlite3_bind_text(statement, 15, childTasksString, -1, nil)
            
            let tagsJson = try? JSONSerialization.data(withJSONObject: invite.tags)
            let tagsString = tagsJson.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            sqlite3_bind_text(statement, 16, tagsString, -1, nil)
            
            let groupsJson = try? JSONSerialization.data(withJSONObject: invite.groups.map { ["id": $0.id, "name": $0.name] })
            let groupsString = groupsJson.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            sqlite3_bind_text(statement, 17, groupsString, -1, nil)
            
            let taskGroupJson = try? JSONSerialization.data(withJSONObject: invite.taskGroup.map { ["id": $0.id, "name": $0.name] } ?? [:])
            let taskGroupString = taskGroupJson.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            sqlite3_bind_text(statement, 18, taskGroupString, -1, nil)
            
            sqlite3_bind_int(statement, 19, invite.aiProcessed ? 1 : 0)
            
            let aiSuggestionsJson = try? JSONSerialization.data(withJSONObject: invite.aiSuggestions)
            let aiSuggestionsString = aiSuggestionsJson.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            sqlite3_bind_text(statement, 20, aiSuggestionsString, -1, nil)
            
            sqlite3_bind_double(statement, 21, invite.aiConfidence)
            sqlite3_bind_text(statement, 22, invite.reminderDate.map { formatter.string(from: $0) }, -1, nil)
            sqlite3_bind_text(statement, 23, invite.messageOriginGuid, -1, nil)
            sqlite3_bind_int(statement, 24, invite.isRecurring ? 1 : 0)
            sqlite3_bind_text(statement, 25, invite.recurrenceType.rawValue, -1, nil)
            sqlite3_bind_text(statement, 26, invite.nextTaskId?.uuidString, -1, nil)
            sqlite3_bind_text(statement, 27, invite.previousTaskId?.uuidString, -1, nil)
            sqlite3_bind_int(statement, 28, invite.isNextTask ? 1 : 0)
            sqlite3_bind_text(statement, 29, invite.dateOfLastTask.map { formatter.string(from: $0) }, -1, nil)
            sqlite3_bind_text(statement, 30, invite.createdBy, -1, nil)
            sqlite3_bind_text(statement, 31, invite.assignedTo, -1, nil)
            sqlite3_bind_text(statement, 32, invite.category, -1, nil)
            sqlite3_bind_text(statement, 33, invite.location, -1, nil)
            
            if let duration = invite.estimatedDuration {
                sqlite3_bind_int(statement, 34, Int32(duration))
            } else {
                sqlite3_bind_null(statement, 34)
            }
            
            let attachmentsJson = try? JSONSerialization.data(withJSONObject: invite.attachments)
            let attachmentsString = attachmentsJson.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            sqlite3_bind_text(statement, 35, attachmentsString, -1, nil)
            
            sqlite3_bind_text(statement, 36, invite.externalId, -1, nil)
            sqlite3_bind_text(statement, 37, invite.lastAiAnalysis.map { formatter.string(from: $0) }, -1, nil)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                print("❌ Failed to save invite to database")
            }
        }
        
        sqlite3_finalize(statement)
    }
    
    private func deleteInviteFromDatabase(_ id: UUID) async {
        guard let db = database else { return }
        
        let query = "DELETE FROM invites WHERE id = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id.uuidString, -1, nil)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                print("❌ Failed to delete invite from database")
            }
        }
        
        sqlite3_finalize(statement)
    }
}
