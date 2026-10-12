import Foundation

struct BatchMessage: Identifiable, Codable {
    let id: UUID
    let messageTemplate: String
    let chipMetadata: ChipMetadata? // Enhanced chip metadata (v2.0)
    let recipients: [BatchRecipient]
    let scheduledTime: Date?
    let createdTime: Date
    var status: BatchMessageStatus
    let totalRecipients: Int
    var sentCount: Int
    var failedCount: Int
    var failedContacts: [String: String] // phone -> error message
    var completedTime: Date?
    let notifyWhenSent: Bool
    var errorLog: [BatchError]
    let sourceGroups: [UUID]? // Track which groups were originally selected
    
    init(
        messageTemplate: String,
        chipMetadata: ChipMetadata? = nil,
        recipients: [BatchRecipient],
        scheduledTime: Date? = nil,
        notifyWhenSent: Bool = false,
        sourceGroups: [UUID]? = nil
    ) {
        self.id = UUID()
        self.messageTemplate = messageTemplate
        self.chipMetadata = chipMetadata
        self.recipients = recipients
        self.scheduledTime = scheduledTime
        self.createdTime = Date()
        self.status = scheduledTime == nil ? .pending : .scheduled
        self.totalRecipients = recipients.count
        self.sentCount = 0
        self.failedCount = 0
        self.failedContacts = [:]
        self.completedTime = nil
        self.notifyWhenSent = notifyWhenSent
        self.errorLog = []
        self.sourceGroups = sourceGroups
    }
    
    // Database-aware initializer that preserves all values from database
    init(
        id: UUID,
        messageTemplate: String,
        chipMetadata: ChipMetadata?,
        recipients: [BatchRecipient],
        scheduledTime: Date?,
        createdTime: Date,
        status: BatchMessageStatus,
        totalRecipients: Int,
        sentCount: Int,
        failedCount: Int,
        failedContacts: [String: String],
        completedTime: Date?,
        notifyWhenSent: Bool,
        errorLog: [BatchError],
        sourceGroups: [UUID]? = nil
    ) {
        self.id = id  // Use provided ID, not generate new one
        self.messageTemplate = messageTemplate
        self.chipMetadata = chipMetadata
        self.recipients = recipients
        self.scheduledTime = scheduledTime
        self.createdTime = createdTime
        self.status = status
        self.totalRecipients = totalRecipients
        self.sentCount = sentCount
        self.failedCount = failedCount
        self.failedContacts = failedContacts
        self.completedTime = completedTime
        self.notifyWhenSent = notifyWhenSent
        self.errorLog = errorLog
        self.sourceGroups = sourceGroups
    }
}

struct BatchRecipient: Codable {
    let phone: String
    let name: String
    let email: String?
    let fieldValues: [String: String] // field name -> value for @field replacement
    let sourceGroupId: UUID? // Track which group this recipient came from
}

enum BatchMessageStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case scheduled = "scheduled" 
    case sending = "sending"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .scheduled: return "Scheduled"
        case .sending: return "Sending"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

struct BatchError: Codable {
    let timestamp: Date
    let phone: String
    let error: String
    let retryAttempt: Int
}
