import Foundation
import GRDB

// MARK: - Invite GRDB Extensions

extension Invite: FetchableRecord, PersistableRecord {
    /// Table name in the database
    static let databaseTableName = "invites"
    
    /// Column names for explicit queries
    enum Columns {
        static let id = Column("id")
        static let title = Column("title")
        static let description = Column("description")
        static let creationDate = Column("creation_date")
        static let lastModifiedDate = Column("last_modified_date")
        static let dateCompleted = Column("date_completed")
        static let completed = Column("completed")
        static let completionStatus = Column("completion_status")
        static let sentReceived = Column("sent_received")
        static let toPhone = Column("to_phone")
        static let fromPhone = Column("from_phone")
        static let priority = Column("priority")
        static let dueDate = Column("due_date")
        static let reminderDate = Column("reminder_date")
        static let messageOriginGuid = Column("message_origin_guid")
        static let isRecurring = Column("is_recurring")
        static let recurrenceType = Column("recurrence_type")
    }
    
    // MARK: - FetchableRecord
    
    /// Initialize from database row
    init(row: Row) throws {
        let idString: String = row["id"]
        guard let uuid = UUID(uuidString: idString) else {
            throw DatabaseError(message: "Invalid UUID for invite: \(idString)")
        }
        self.id = uuid
        
        self.title = row["title"]
        self.description = row["description"]
        
        // Parse dates
        let creationDateString: String = row["creation_date"]
        self.creationDate = ISO8601DateFormatter().date(from: creationDateString) ?? Date()
        
        let lastModifiedDateString: String = row["last_modified_date"]
        self.lastModifiedDate = ISO8601DateFormatter().date(from: lastModifiedDateString) ?? Date()
        
        if let dateCompletedString: String = row["date_completed"] {
            self.dateCompleted = ISO8601DateFormatter().date(from: dateCompletedString)
        } else {
            self.dateCompleted = nil
        }
        
        self.completed = row["completed"]
        
        // Parse completion status
        let statusString: String = row["completion_status"]
        self.completionStatus = CompletionStatus(rawValue: statusString) ?? .pending
        
        // Parse sent/received
        let sentReceivedString: String = row["sent_received"]
        self.sentReceived = SentReceived(rawValue: sentReceivedString) ?? .received
        
        self.toPhone = row["to_phone"]
        self.fromPhone = row["from_phone"]
        
        // Parse priority
        let priorityInt: Int = row["priority"]
        self.priority = Priority(rawValue: priorityInt) ?? .medium
        
        // Parse optional dates
        if let dueDateString: String = row["due_date"] {
            self.dueDate = ISO8601DateFormatter().date(from: dueDateString)
        } else {
            self.dueDate = nil
        }
        
        if let reminderDateString: String = row["reminder_date"] {
            self.reminderDate = ISO8601DateFormatter().date(from: reminderDateString)
        } else {
            self.reminderDate = nil
        }
        
        // Parse JSON arrays
        if let parentTasksJSON: String = row["parent_tasks"], !parentTasksJSON.isEmpty {
            if let data = parentTasksJSON.data(using: .utf8),
               let uuidStrings = try? JSONDecoder().decode([String].self, from: data) {
                self.parentTasks = uuidStrings.compactMap { UUID(uuidString: $0) }
            } else {
                self.parentTasks = []
            }
        } else {
            self.parentTasks = []
        }
        
        if let childTasksJSON: String = row["child_tasks"], !childTasksJSON.isEmpty {
            if let data = childTasksJSON.data(using: .utf8),
               let uuidStrings = try? JSONDecoder().decode([String].self, from: data) {
                self.childTasks = uuidStrings.compactMap { UUID(uuidString: $0) }
            } else {
                self.childTasks = []
            }
        } else {
            self.childTasks = []
        }
        
        // Parse tags (stored as JSON object)
        if let tagsJSON: String = row["tags"], !tagsJSON.isEmpty {
            if let data = tagsJSON.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.tags = dict
            } else {
                self.tags = [:]
            }
        } else {
            self.tags = [:]
        }
        
        // Parse groups array
        if let groupsJSON: String = row["groups"], !groupsJSON.isEmpty {
            if let data = groupsJSON.data(using: .utf8),
               let groups = try? JSONDecoder().decode([GroupReference].self, from: data) {
                self.groups = groups
            } else {
                self.groups = []
            }
        } else {
            self.groups = []
        }
        
        // Parse task group
        if let taskGroupJSON: String = row["task_group"], !taskGroupJSON.isEmpty {
            if let data = taskGroupJSON.data(using: .utf8),
               let taskGroup = try? JSONDecoder().decode(TaskGroup.self, from: data) {
                self.taskGroup = taskGroup
            } else {
                self.taskGroup = nil
            }
        } else {
            self.taskGroup = nil
        }
        
        self.aiProcessed = row["ai_processed"]
        
        // Parse AI suggestions
        if let aiSuggestionsJSON: String = row["ai_suggestions"], !aiSuggestionsJSON.isEmpty {
            if let data = aiSuggestionsJSON.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.aiSuggestions = dict
            } else {
                self.aiSuggestions = [:]
            }
        } else {
            self.aiSuggestions = [:]
        }
        
        self.aiConfidence = row["ai_confidence"]
        self.messageOriginGuid = row["message_origin_guid"]
        self.isRecurring = row["is_recurring"]
        
        // Parse recurrence type
        let recurrenceTypeString: String = row["recurrence_type"]
        self.recurrenceType = RecurrenceType(rawValue: recurrenceTypeString) ?? .none
        
        // Parse next/previous task IDs
        if let nextTaskIdString: String = row["next_task_id"] {
            self.nextTaskId = UUID(uuidString: nextTaskIdString)
        } else {
            self.nextTaskId = nil
        }
        
        if let previousTaskIdString: String = row["previous_task_id"] {
            self.previousTaskId = UUID(uuidString: previousTaskIdString)
        } else {
            self.previousTaskId = nil
        }
        
        self.isNextTask = row["is_next_task"]
        
        if let dateOfLastTaskString: String = row["date_of_last_task"] {
            self.dateOfLastTask = ISO8601DateFormatter().date(from: dateOfLastTaskString)
        } else {
            self.dateOfLastTask = nil
        }
        
        self.createdBy = row["created_by"]
        self.assignedTo = row["assigned_to"]
        self.category = row["category"]
        self.location = row["location"]
        self.estimatedDuration = row["estimated_duration"]
        
        // Parse attachments
        if let attachmentsJSON: String = row["attachments"], !attachmentsJSON.isEmpty {
            if let data = attachmentsJSON.data(using: .utf8),
               let attachments = try? JSONDecoder().decode([String].self, from: data) {
                self.attachments = attachments
            } else {
                self.attachments = []
            }
        } else {
            self.attachments = []
        }
        
        self.externalId = row["external_id"]
        
        if let lastAiAnalysisString: String = row["last_ai_analysis"] {
            self.lastAiAnalysis = ISO8601DateFormatter().date(from: lastAiAnalysisString)
        } else {
            self.lastAiAnalysis = nil
        }
    }
    
    // MARK: - PersistableRecord
    
    /// Encode to database
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["title"] = title
        container["description"] = description
        container["creation_date"] = ISO8601DateFormatter().string(from: creationDate)
        container["last_modified_date"] = ISO8601DateFormatter().string(from: lastModifiedDate)
        
        if let dateCompleted = dateCompleted {
            container["date_completed"] = ISO8601DateFormatter().string(from: dateCompleted)
        }
        
        container["completed"] = completed
        container["completion_status"] = completionStatus.rawValue
        container["sent_received"] = sentReceived.rawValue
        container["to_phone"] = toPhone
        container["from_phone"] = fromPhone
        container["priority"] = priority.rawValue
        
        if let dueDate = dueDate {
            container["due_date"] = ISO8601DateFormatter().string(from: dueDate)
        }
        
        if let reminderDate = reminderDate {
            container["reminder_date"] = ISO8601DateFormatter().string(from: reminderDate)
        }
        
        // Encode arrays as JSON
        let parentTasksStrings = parentTasks.map { $0.uuidString }
        let parentTasksData = try JSONEncoder().encode(parentTasksStrings)
        container["parent_tasks"] = String(data: parentTasksData, encoding: .utf8)
        
        let childTasksStrings = childTasks.map { $0.uuidString }
        let childTasksData = try JSONEncoder().encode(childTasksStrings)
        container["child_tasks"] = String(data: childTasksData, encoding: .utf8)
        
        // Encode tags as JSON
        if let tagsData = try? JSONSerialization.data(withJSONObject: tags) {
            container["tags"] = String(data: tagsData, encoding: .utf8)
        }
        
        // Encode groups
        let groupsData = try JSONEncoder().encode(groups)
        container["groups"] = String(data: groupsData, encoding: .utf8)
        
        // Encode task group
        if let taskGroup = taskGroup {
            let taskGroupData = try JSONEncoder().encode(taskGroup)
            container["task_group"] = String(data: taskGroupData, encoding: .utf8)
        }
        
        container["ai_processed"] = aiProcessed
        
        // Encode AI suggestions as JSON
        if let aiSuggestionsData = try? JSONSerialization.data(withJSONObject: aiSuggestions) {
            container["ai_suggestions"] = String(data: aiSuggestionsData, encoding: .utf8)
        }
        
        container["ai_confidence"] = aiConfidence
        container["message_origin_guid"] = messageOriginGuid
        container["is_recurring"] = isRecurring
        container["recurrence_type"] = recurrenceType.rawValue
        container["next_task_id"] = nextTaskId?.uuidString
        container["previous_task_id"] = previousTaskId?.uuidString
        container["is_next_task"] = isNextTask
        
        if let dateOfLastTask = dateOfLastTask {
            container["date_of_last_task"] = ISO8601DateFormatter().string(from: dateOfLastTask)
        }
        
        container["created_by"] = createdBy
        container["assigned_to"] = assignedTo
        container["category"] = category
        container["location"] = location
        container["estimated_duration"] = estimatedDuration
        
        // Encode attachments
        let attachmentsData = try JSONEncoder().encode(attachments)
        container["attachments"] = String(data: attachmentsData, encoding: .utf8)
        
        container["external_id"] = externalId
        
        if let lastAiAnalysis = lastAiAnalysis {
            container["last_ai_analysis"] = ISO8601DateFormatter().string(from: lastAiAnalysis)
        }
    }
}

// MARK: - Query Helpers

extension Invite {
    /// Find invite by ID
    static func fetchOne(_ db: Database, id: UUID) throws -> Invite? {
        return try Invite
            .filter(Column("id") == id.uuidString)
            .fetchOne(db)
    }
    
    /// Fetch all pending invites
    static func fetchPending(_ db: Database) throws -> [Invite] {
        return try Invite
            .filter(Column("completed") == false)
            .order(Column("priority").desc, Column("due_date").asc)
            .fetchAll(db)
    }
    
    /// Fetch invites by priority
    static func fetch(_ db: Database, priority: Priority) throws -> [Invite] {
        return try Invite
            .filter(Column("priority") == priority.rawValue)
            .order(Column("due_date").asc)
            .fetchAll(db)
    }
    
    /// Fetch invites due today
    static func fetchDueToday(_ db: Database) throws -> [Invite] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        let todayString = ISO8601DateFormatter().string(from: today)
        let tomorrowString = ISO8601DateFormatter().string(from: tomorrow)
        
        return try Invite
            .filter(Column("completed") == false)
            .filter(Column("due_date") >= todayString && Column("due_date") < tomorrowString)
            .order(Column("priority").desc)
            .fetchAll(db)
    }
    
    /// Fetch overdue invites
    static func fetchOverdue(_ db: Database) throws -> [Invite] {
        let now = ISO8601DateFormatter().string(from: Date())
        
        return try Invite
            .filter(Column("completed") == false)
            .filter(Column("due_date") < now)
            .order(Column("priority").desc, Column("due_date").asc)
            .fetchAll(db)
    }
}

