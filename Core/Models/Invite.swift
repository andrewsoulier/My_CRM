import Foundation
import SwiftUI

// MARK: - Invite Model

struct Invite: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String?
    var creationDate: Date
    var lastModifiedDate: Date
    var dateCompleted: Date?
    var completed: Bool
    var completionStatus: CompletionStatus
    var sentReceived: SentReceived
    var toPhone: String?
    var fromPhone: String?
    var priority: Priority
    var dueDate: Date?
    var parentTasks: [UUID]
    var childTasks: [UUID]
    var tags: [String: Any]
    var groups: [GroupReference]
    var taskGroup: TaskGroup?
    var aiProcessed: Bool
    var aiSuggestions: [String: Any]
    var aiConfidence: Double
    var reminderDate: Date?
    var messageOriginGuid: String?
    var isRecurring: Bool
    var recurrenceType: RecurrenceType
    var nextTaskId: UUID?
    var previousTaskId: UUID?
    var isNextTask: Bool
    var dateOfLastTask: Date?
    var createdBy: String?
    var assignedTo: String?
    var category: String?
    var location: String?
    var estimatedDuration: Int? // in minutes
    var attachments: [String]
    var externalId: String?
    var lastAiAnalysis: Date?
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        creationDate: Date = Date(),
        lastModifiedDate: Date = Date(),
        dateCompleted: Date? = nil,
        completed: Bool = false,
        completionStatus: CompletionStatus = .pending,
        sentReceived: SentReceived,
        toPhone: String? = nil,
        fromPhone: String? = nil,
        priority: Priority = .medium,
        dueDate: Date? = nil,
        parentTasks: [UUID] = [],
        childTasks: [UUID] = [],
        tags: [String: Any] = [:],
        groups: [GroupReference] = [],
        taskGroup: TaskGroup? = nil,
        aiProcessed: Bool = false,
        aiSuggestions: [String: Any] = [:],
        aiConfidence: Double = 0.0,
        reminderDate: Date? = nil,
        messageOriginGuid: String? = nil,
        isRecurring: Bool = false,
        recurrenceType: RecurrenceType = .none,
        nextTaskId: UUID? = nil,
        previousTaskId: UUID? = nil,
        isNextTask: Bool = false,
        dateOfLastTask: Date? = nil,
        createdBy: String? = nil,
        assignedTo: String? = nil,
        category: String? = nil,
        location: String? = nil,
        estimatedDuration: Int? = nil,
        attachments: [String] = [],
        externalId: String? = nil,
        lastAiAnalysis: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.creationDate = creationDate
        self.lastModifiedDate = lastModifiedDate
        self.dateCompleted = dateCompleted
        self.completed = completed
        self.completionStatus = completionStatus
        self.sentReceived = sentReceived
        self.toPhone = toPhone
        self.fromPhone = fromPhone
        self.priority = priority
        self.dueDate = dueDate
        self.parentTasks = parentTasks
        self.childTasks = childTasks
        self.tags = tags
        self.groups = groups
        self.taskGroup = taskGroup
        self.aiProcessed = aiProcessed
        self.aiSuggestions = aiSuggestions
        self.aiConfidence = aiConfidence
        self.reminderDate = reminderDate
        self.messageOriginGuid = messageOriginGuid
        self.isRecurring = isRecurring
        self.recurrenceType = recurrenceType
        self.nextTaskId = nextTaskId
        self.previousTaskId = previousTaskId
        self.isNextTask = isNextTask
        self.dateOfLastTask = dateOfLastTask
        self.createdBy = createdBy
        self.assignedTo = assignedTo
        self.category = category
        self.location = location
        self.estimatedDuration = estimatedDuration
        self.attachments = attachments
        self.externalId = externalId
        self.lastAiAnalysis = lastAiAnalysis
    }
}

// MARK: - Equatable Conformance

extension Invite: Equatable {
    static func == (lhs: Invite, rhs: Invite) -> Bool {
        return lhs.id == rhs.id &&
               lhs.title == rhs.title &&
               lhs.description == rhs.description &&
               lhs.creationDate == rhs.creationDate &&
               lhs.lastModifiedDate == rhs.lastModifiedDate &&
               lhs.dateCompleted == rhs.dateCompleted &&
               lhs.completed == rhs.completed &&
               lhs.completionStatus == rhs.completionStatus &&
               lhs.sentReceived == rhs.sentReceived &&
               lhs.toPhone == rhs.toPhone &&
               lhs.fromPhone == rhs.fromPhone &&
               lhs.priority == rhs.priority &&
               lhs.dueDate == rhs.dueDate &&
               lhs.parentTasks == rhs.parentTasks &&
               lhs.childTasks == rhs.childTasks &&
               lhs.groups == rhs.groups &&
               lhs.taskGroup == rhs.taskGroup &&
               lhs.aiProcessed == rhs.aiProcessed &&
               lhs.aiConfidence == rhs.aiConfidence &&
               lhs.reminderDate == rhs.reminderDate &&
               lhs.messageOriginGuid == rhs.messageOriginGuid &&
               lhs.isRecurring == rhs.isRecurring &&
               lhs.recurrenceType == rhs.recurrenceType &&
               lhs.nextTaskId == rhs.nextTaskId &&
               lhs.previousTaskId == rhs.previousTaskId &&
               lhs.isNextTask == rhs.isNextTask &&
               lhs.dateOfLastTask == rhs.dateOfLastTask &&
               lhs.createdBy == rhs.createdBy &&
               lhs.assignedTo == rhs.assignedTo &&
               lhs.category == rhs.category &&
               lhs.location == rhs.location &&
               lhs.estimatedDuration == rhs.estimatedDuration &&
               lhs.attachments == rhs.attachments &&
               lhs.externalId == rhs.externalId &&
               lhs.lastAiAnalysis == rhs.lastAiAnalysis
        // Note: tags and aiSuggestions are not compared as [String: Any] doesn't conform to Equatable
        // In practice, this should be sufficient for most use cases
    }
}

// MARK: - Supporting Types

enum CompletionStatus: String, CaseIterable, Codable {
    case pending = "pending"
    case inProgress = "in_progress"
    case completed = "completed"
    case cancelled = "cancelled"
    case deferred = "deferred"
    case expired = "expired"
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        case .deferred: return "Deferred"
        case .expired: return "Expired"
        }
    }
    
    var color: Color {
        switch self {
        case .pending: return .orange
        case .inProgress: return .blue
        case .completed: return .green
        case .cancelled: return .red
        case .deferred: return .gray
        case .expired: return .purple
        }
    }
}

enum SentReceived: String, CaseIterable, Codable {
    case sent = "sent"
    case received = "received"
    
    var displayName: String {
        switch self {
        case .sent: return "Sent"
        case .received: return "Received"
        }
    }
    
    var icon: String {
        switch self {
        case .sent: return "arrow.up.circle"
        case .received: return "arrow.down.circle"
        }
    }
}

enum Priority: Int, CaseIterable, Codable {
    case low = 1
    case medium = 2
    case high = 3
    case urgent = 4
    case critical = 5
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        case .critical: return "Critical"
        }
    }
    
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .urgent: return .red
        case .critical: return .purple
        }
    }
    
    var icon: String {
        switch self {
        case .low: return "1.circle"
        case .medium: return "2.circle"
        case .high: return "3.circle"
        case .urgent: return "4.circle"
        case .critical: return "5.circle"
        }
    }
}

enum RecurrenceType: String, CaseIterable, Codable {
    case none = "none"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case monthlyByWeek = "monthly-by-week"
    case yearly = "yearly"
    case yearlyByMonthWeek = "yearly-by-month-week"
    
    var displayName: String {
        switch self {
        case .none: return "No Recurrence"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .monthlyByWeek: return "Monthly by Week"
        case .yearly: return "Yearly"
        case .yearlyByMonthWeek: return "Yearly by Month/Week"
        }
    }
    
    var icon: String {
        switch self {
        case .none: return "circle"
        case .daily: return "calendar"
        case .weekly: return "calendar.badge.clock"
        case .monthly: return "calendar.badge.plus"
        case .monthlyByWeek: return "calendar.badge.exclamationmark"
        case .yearly: return "calendar.badge.checkmark"
        case .yearlyByMonthWeek: return "calendar.badge.minus"
        }
    }
}

struct GroupReference: Codable, Equatable {
    let id: String
    let name: String
    
    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

struct TaskGroup: Codable, Equatable {
    let id: String
    let name: String
    
    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Custom Codable Implementation for Dictionary Fields

extension Invite {
    private enum CodingKeys: String, CodingKey {
        case id, title, description, creationDate, lastModifiedDate, dateCompleted, completed
        case completionStatus, sentReceived, toPhone, fromPhone, priority, dueDate
        case parentTasks, childTasks, groups, taskGroup, aiProcessed, aiConfidence
        case reminderDate, messageOriginGuid, isRecurring, recurrenceType
        case nextTaskId, previousTaskId, isNextTask, dateOfLastTask, createdBy, assignedTo
        case category, location, estimatedDuration, attachments, externalId, lastAiAnalysis
        case tags, aiSuggestions
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        creationDate = try container.decode(Date.self, forKey: .creationDate)
        lastModifiedDate = try container.decode(Date.self, forKey: .lastModifiedDate)
        dateCompleted = try container.decodeIfPresent(Date.self, forKey: .dateCompleted)
        completed = try container.decode(Bool.self, forKey: .completed)
        completionStatus = try container.decode(CompletionStatus.self, forKey: .completionStatus)
        sentReceived = try container.decode(SentReceived.self, forKey: .sentReceived)
        toPhone = try container.decodeIfPresent(String.self, forKey: .toPhone)
        fromPhone = try container.decodeIfPresent(String.self, forKey: .fromPhone)
        priority = try container.decode(Priority.self, forKey: .priority)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        parentTasks = try container.decode([UUID].self, forKey: .parentTasks)
        childTasks = try container.decode([UUID].self, forKey: .childTasks)
        groups = try container.decode([GroupReference].self, forKey: .groups)
        taskGroup = try container.decodeIfPresent(TaskGroup.self, forKey: .taskGroup)
        aiProcessed = try container.decode(Bool.self, forKey: .aiProcessed)
        aiConfidence = try container.decode(Double.self, forKey: .aiConfidence)
        reminderDate = try container.decodeIfPresent(Date.self, forKey: .reminderDate)
        messageOriginGuid = try container.decodeIfPresent(String.self, forKey: .messageOriginGuid)
        isRecurring = try container.decode(Bool.self, forKey: .isRecurring)
        recurrenceType = try container.decode(RecurrenceType.self, forKey: .recurrenceType)
        nextTaskId = try container.decodeIfPresent(UUID.self, forKey: .nextTaskId)
        previousTaskId = try container.decodeIfPresent(UUID.self, forKey: .previousTaskId)
        isNextTask = try container.decode(Bool.self, forKey: .isNextTask)
        dateOfLastTask = try container.decodeIfPresent(Date.self, forKey: .dateOfLastTask)
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        assignedTo = try container.decodeIfPresent(String.self, forKey: .assignedTo)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        estimatedDuration = try container.decodeIfPresent(Int.self, forKey: .estimatedDuration)
        attachments = try container.decode([String].self, forKey: .attachments)
        externalId = try container.decodeIfPresent(String.self, forKey: .externalId)
        lastAiAnalysis = try container.decodeIfPresent(Date.self, forKey: .lastAiAnalysis)
        
        // Decode JSON fields
        if let tagsData = try container.decodeIfPresent(Data.self, forKey: .tags),
           let tagsDict = try? JSONSerialization.jsonObject(with: tagsData) as? [String: Any] {
            tags = tagsDict
        } else {
            tags = [:]
        }
        
        if let aiSuggestionsData = try container.decodeIfPresent(Data.self, forKey: .aiSuggestions),
           let aiSuggestionsDict = try? JSONSerialization.jsonObject(with: aiSuggestionsData) as? [String: Any] {
            aiSuggestions = aiSuggestionsDict
        } else {
            aiSuggestions = [:]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(creationDate, forKey: .creationDate)
        try container.encode(lastModifiedDate, forKey: .lastModifiedDate)
        try container.encodeIfPresent(dateCompleted, forKey: .dateCompleted)
        try container.encode(completed, forKey: .completed)
        try container.encode(completionStatus, forKey: .completionStatus)
        try container.encode(sentReceived, forKey: .sentReceived)
        try container.encodeIfPresent(toPhone, forKey: .toPhone)
        try container.encodeIfPresent(fromPhone, forKey: .fromPhone)
        try container.encode(priority, forKey: .priority)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encode(parentTasks, forKey: .parentTasks)
        try container.encode(childTasks, forKey: .childTasks)
        try container.encode(groups, forKey: .groups)
        try container.encodeIfPresent(taskGroup, forKey: .taskGroup)
        try container.encode(aiProcessed, forKey: .aiProcessed)
        try container.encode(aiConfidence, forKey: .aiConfidence)
        try container.encodeIfPresent(reminderDate, forKey: .reminderDate)
        try container.encodeIfPresent(messageOriginGuid, forKey: .messageOriginGuid)
        try container.encode(isRecurring, forKey: .isRecurring)
        try container.encode(recurrenceType, forKey: .recurrenceType)
        try container.encodeIfPresent(nextTaskId, forKey: .nextTaskId)
        try container.encodeIfPresent(previousTaskId, forKey: .previousTaskId)
        try container.encode(isNextTask, forKey: .isNextTask)
        try container.encodeIfPresent(dateOfLastTask, forKey: .dateOfLastTask)
        try container.encodeIfPresent(createdBy, forKey: .createdBy)
        try container.encodeIfPresent(assignedTo, forKey: .assignedTo)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(estimatedDuration, forKey: .estimatedDuration)
        try container.encode(attachments, forKey: .attachments)
        try container.encodeIfPresent(externalId, forKey: .externalId)
        try container.encodeIfPresent(lastAiAnalysis, forKey: .lastAiAnalysis)
        
        // Encode JSON fields
        if let tagsData = try? JSONSerialization.data(withJSONObject: tags) {
            try container.encode(tagsData, forKey: .tags)
        }
        
        if let aiSuggestionsData = try? JSONSerialization.data(withJSONObject: aiSuggestions) {
            try container.encode(aiSuggestionsData, forKey: .aiSuggestions)
        }
    }
}

// MARK: - Computed Properties

extension Invite {
    var isOverdue: Bool {
        guard let dueDate = dueDate, !completed else { return false }
        return dueDate < Date()
    }
    
    var daysUntilDue: Int? {
        guard let dueDate = dueDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let due = calendar.startOfDay(for: dueDate)
        return calendar.dateComponents([.day], from: today, to: due).day
    }
    
    var isDueToday: Bool {
        guard let dueDate = dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }
    
    var isDueTomorrow: Bool {
        guard let dueDate = dueDate else { return false }
        return Calendar.current.isDateInTomorrow(dueDate)
    }
    
    var hasReminder: Bool {
        return reminderDate != nil
    }
    
    var isReminderOverdue: Bool {
        guard let reminderDate = reminderDate else { return false }
        return reminderDate < Date() && !completed
    }
    
    var displayTitle: String {
        return title.isEmpty ? "Untitled Invite" : title
    }
    
    var shortDescription: String {
        guard let description = description, !description.isEmpty else {
            return "No description"
        }
        return description.count > 100 ? String(description.prefix(100)) + "..." : description
    }
}

// MARK: - Filter Support

struct InviteFilter {
    var searchTerm: String = ""
    var status: CompletionStatus?
    var priority: Priority?
    var sentReceived: SentReceived?
    var isRecurring: Bool?
    var dueDateRange: DateInterval?
    var contactPhone: String?
    var sortBy: InviteSortOption = .dueDate
    var sortOrder: SortOrder = .forward
}

enum InviteSortOption: String, CaseIterable {
    case title = "title"
    case dueDate = "due_date"
    case priority = "priority"
    case creationDate = "creation_date"
    case lastModified = "last_modified"
    case status = "status"
    
    var displayName: String {
        switch self {
        case .title: return "Title"
        case .dueDate: return "Due Date"
        case .priority: return "Priority"
        case .creationDate: return "Created"
        case .lastModified: return "Modified"
        case .status: return "Status"
        }
    }
}

enum SortOrder: String, CaseIterable {
    case forward = "asc"
    case reverse = "desc"
    
    var displayName: String {
        switch self {
        case .forward: return "Ascending"
        case .reverse: return "Descending"
        }
    }
}
