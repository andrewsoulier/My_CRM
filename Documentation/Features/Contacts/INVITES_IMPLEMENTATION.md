# Invites Implementation Documentation

## Overview

The Invites system is a comprehensive task and invitation management feature for the My CRM application. It allows users to manage invitations, actions, and to-do items sent or received through their contacts, with AI-powered analysis and smart features.

## Database Schema

### Invites Table

The `invites` table stores all invitation and task data with the following structure:

```sql
CREATE TABLE invites (
    id TEXT PRIMARY KEY,                    -- UUID string identifier
    title TEXT NOT NULL,                    -- Title or subject of the invitation/task
    description TEXT,                       -- Detailed description
    creation_date TEXT NOT NULL,            -- ISO 8601 timestamp of creation
    last_modified_date TEXT NOT NULL,       -- ISO 8601 timestamp of last modification
    date_completed TEXT,                    -- ISO 8601 timestamp when completed
    completed INTEGER DEFAULT 0,            -- Boolean flag (1=completed, 0=not completed)
    completion_status TEXT DEFAULT 'pending', -- Current status
    sent_received TEXT NOT NULL,            -- Direction: 'sent' or 'received'
    to_phone TEXT,                          -- Phone number of recipient
    from_phone TEXT,                        -- Phone number of sender
    priority INTEGER DEFAULT 1,             -- Priority level (1-5)
    due_date TEXT,                          -- ISO 8601 timestamp of due date
    parent_tasks TEXT DEFAULT '[]',         -- JSON array of parent task UUIDs
    child_tasks TEXT DEFAULT '[]',          -- JSON array of child task UUIDs
    tags TEXT DEFAULT '{}',                 -- JSON object with categorized tags
    groups TEXT DEFAULT '[]',               -- JSON array of group references
    task_group TEXT DEFAULT '{}',           -- JSON object with task group info
    ai_processed INTEGER DEFAULT 0,         -- Boolean flag for AI analysis
    ai_suggestions TEXT DEFAULT '{}',       -- JSON object with AI suggestions
    ai_confidence REAL DEFAULT 0.0,         -- AI confidence score (0.0-1.0)
    reminder_date TEXT,                     -- ISO 8601 timestamp for reminders
    message_origin_guid TEXT,               -- GUID of originating message
    is_recurring INTEGER DEFAULT 0,         -- Boolean flag for recurring tasks
    recurrence_type TEXT DEFAULT 'none',    -- Type of recurrence
    next_task_id TEXT,                      -- UUID of next occurrence
    previous_task_id TEXT,                  -- UUID of previous occurrence
    is_next_task INTEGER DEFAULT 0,         -- Boolean flag for next task in series
    date_of_last_task TEXT,                 -- ISO 8601 timestamp of last occurrence
    created_by TEXT,                        -- Creator identifier
    assigned_to TEXT,                       -- Assignee identifier
    category TEXT,                          -- Task category
    location TEXT,                          -- Physical or virtual location
    estimated_duration INTEGER,             -- Duration in minutes
    attachments TEXT DEFAULT '[]',          -- JSON array of file references
    external_id TEXT,                       -- External system reference
    last_ai_analysis TEXT                   -- ISO 8601 timestamp of last AI analysis
);
```

### Foreign Key Relationships

- `to_phone` → `contacts.phone`
- `from_phone` → `contacts.phone`
- `message_origin_guid` → `messages.guid`
- `next_task_id` → `invites.id` (self-reference)
- `previous_task_id` → `invites.id` (self-reference)

### Indexes

The following indexes are created for optimal performance:

- `idx_invites_id` (UNIQUE)
- `idx_invites_to_phone`
- `idx_invites_from_phone`
- `idx_invites_creation_date`
- `idx_invites_due_date`
- `idx_invites_completed`
- `idx_invites_priority`
- `idx_invites_sent_received`
- `idx_invites_message_origin`
- `idx_invites_recurring`
- `idx_invites_next_task`

## Data Models

### Invite Model

The `Invite` struct represents a single invitation or task with all associated metadata:

```swift
struct Invite: Identifiable, Codable, Equatable {
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
    var estimatedDuration: Int?
    var attachments: [String]
    var externalId: String?
    var lastAiAnalysis: Date?
}
```

### Supporting Types

#### CompletionStatus
```swift
enum CompletionStatus: String, CaseIterable, Codable {
    case pending = "pending"
    case inProgress = "in_progress"
    case completed = "completed"
    case cancelled = "cancelled"
    case deferred = "deferred"
    case expired = "expired"
}
```

#### Priority
```swift
enum Priority: Int, CaseIterable, Codable {
    case low = 1
    case medium = 2
    case high = 3
    case urgent = 4
    case critical = 5
}
```

#### RecurrenceType
```swift
enum RecurrenceType: String, CaseIterable, Codable {
    case none = "none"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case monthlyByWeek = "monthly-by-week"
    case yearly = "yearly"
    case yearlyByMonthWeek = "yearly-by-month-week"
}
```

#### SentReceived
```swift
enum SentReceived: String, CaseIterable, Codable {
    case sent = "sent"
    case received = "received"
}
```

## API Operations

### DataProvider Protocol Extensions

The `DataProvider` protocol has been extended with the following invite operations:

```swift
// Basic CRUD operations
func fetchInvites(offset: Int, limit: Int, filter: InviteFilter) async throws -> [Invite]
func countInvites(filter: InviteFilter) async throws -> Int
func fetchInvite(by id: UUID) async throws -> Invite?
func getInvite(by id: UUID) -> Invite?
func createInvite(_ invite: Invite) async throws
func updateInvite(_ invite: Invite) async throws
func deleteInvite(_ id: UUID) async throws

// Status management
func markInviteComplete(_ id: UUID) async throws
func markInviteIncomplete(_ id: UUID) async throws

// Specialized queries
func fetchInvitesByContact(phone: String) async throws -> [Invite]
func fetchRecurringInvites() async throws -> [Invite]
func fetchOverdueInvites() async throws -> [Invite]
func fetchInvitesDueToday() async throws -> [Invite]
func fetchInvitesByMessage(guid: String) async throws -> [Invite]
```

### Filtering and Sorting

The `InviteFilter` struct provides comprehensive filtering options:

```swift
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
```

## AI Integration

### ChatGPT Integration

The invites system includes comprehensive AI integration powered by ChatGPT for:

1. **Message Analysis**: Automatically detect potential invitations in incoming messages
2. **Context Extraction**: Extract key information (title, due date, priority, contacts)
3. **Confidence Scoring**: Rate AI analysis confidence (0.0-1.0)
4. **Suggestion Generation**: Provide actionable suggestions for task management

### Connection Management

The AI integration is managed through a dedicated ChatGPT service:

- **Settings Integration**: "Log in to ChatGPT" button in settings page
- **Secure Storage**: API keys stored in macOS keychain using Python keyring
- **Connection Status**: Real-time connection status with visual indicators
- **Script-based**: Python script (`connectToChatGPT.py`) handles authentication

### AI Fields

- `ai_processed`: Boolean flag indicating if AI has analyzed the invite
- `ai_suggestions`: JSON object containing AI-generated suggestions
- `ai_confidence`: Confidence score for AI analysis (0.0-1.0)
- `last_ai_analysis`: Timestamp of last AI processing

### Smart Features

- **Auto-categorization**: Categorize invites based on content analysis
- **Priority suggestion**: Suggest priority levels based on urgency indicators
- **Due date inference**: Extract or suggest due dates from natural language
- **Contact matching**: Match phone numbers to existing contacts
- **Recurrence detection**: Identify recurring patterns in messages
- **Task suggestions**: Generate actionable next steps for tasks
- **Message parsing**: Analyze incoming messages for potential invites

### ChatGPT Service API

The `ChatGPTService` provides the following methods:

```swift
// Connection management
func connectToChatGPT() async
func disconnectFromChatGPT() async
func checkConnectionStatus() async

// AI analysis
func analyzeMessageForInvite(_ message: String, contactName: String?) async -> InviteAnalysis?
func generateTaskSuggestions(for invite: Invite) async -> [String]
func categorizeInvite(_ invite: Invite) async -> String?
func suggestPriority(for invite: Invite) async -> Priority?
```

### Python Script Features

The `connectToChatGPT.py` script provides:

- **Interactive Setup**: Guided API key and organization ID setup
- **Secure Storage**: Uses macOS keychain for credential storage
- **Connection Testing**: Validates API credentials before saving
- **Status Checking**: Verify current connection status
- **User Preferences**: Updates app preferences with connection status

## Recurring Tasks

### Recurrence Types

The system supports various recurrence patterns:

- `none`: No recurrence
- `daily`: Daily recurrence
- `weekly`: Weekly recurrence
- `monthly`: Monthly recurrence
- `monthly-by-week`: Monthly by week recurrence
- `yearly`: Yearly recurrence
- `yearly-by-month-week`: Yearly by month and week recurrence

### Task Chains

Recurring tasks are linked through:

- `next_task_id`: Links to the next occurrence in the series
- `previous_task_id`: Links to the previous occurrence in the series
- `is_next_task`: Boolean flag indicating if this is the next task in the series
- `date_of_last_task`: Timestamp of when the last occurrence was completed

## Task Hierarchies

### Parent-Child Relationships

Tasks can be organized in hierarchies using:

- `parent_tasks`: JSON array of parent task UUIDs
- `child_tasks`: JSON array of child task UUIDs

This allows for complex task breakdown and project management.

## Database Views

### Predefined Views

The system includes several useful database views:

1. **invite_summary**: Invites with contact information and completion status
2. **pending_invites**: All pending invites ordered by priority and due date
3. **recurring_invites**: Recurring invites with their next occurrence information

## Triggers

### Automatic Updates

Database triggers automatically handle:

1. **Completion Date**: Set completion date when invite is marked as completed
2. **Modified Date**: Update last_modified_date on any invite update

## Performance Considerations

### Optimization Strategies

1. **Indexing**: Comprehensive indexes on frequently queried columns
2. **JSON Storage**: Efficient storage of complex metadata structures
3. **Virtual Lists**: UI uses virtualized lists for large datasets
4. **Debounced Updates**: UI changes are debounced to reduce database writes
5. **Batch Operations**: Multiple operations are batched for efficiency

### Caching

- AI analysis results are cached to avoid repeated processing
- Contact lookups are optimized with phone number indexing
- Task hierarchies use JSON for flexible parent-child relationships

## Security and Data Integrity

### Constraints

- Invite IDs must be valid UUIDs
- Phone number references must exist in contacts table
- Message origin GUIDs must exist in messages table
- Recurring task references must be valid invite UUIDs
- Priority levels must be between 1 and 5
- AI confidence scores must be between 0.0 and 1.0
- Sent/received field must be either 'sent' or 'received'

### Foreign Key Relationships

All foreign key relationships use appropriate cascade rules:
- `ON DELETE SET NULL` for optional references
- `ON UPDATE CASCADE` for maintaining referential integrity

## Migration and Backup

### Migration Notes

- Invites table uses UUIDs for primary keys to support distributed systems
- Recurring tasks use self-referencing foreign keys for task chains
- AI analysis data is stored as JSON for flexible schema evolution
- Task hierarchies are stored as JSON arrays for efficient querying

### Backup Recommendations

- Invites data should be backed up with full JSON field integrity
- AI analysis results should be preserved in backups for continuity
- Recurring task chains should be validated after restore operations

## Future Enhancements

### Planned Features

1. **Calendar Integration**: Export invites to external calendar systems
2. **Notification System**: Push notifications for reminders and due dates
3. **Collaboration**: Multi-user task assignment and collaboration
4. **Analytics**: Task completion analytics and productivity insights
5. **Templates**: Reusable task templates for common workflows
6. **Integration APIs**: REST APIs for third-party integrations

### AI Improvements

1. **Learning System**: Learn from user corrections and preferences
2. **Pattern Recognition**: Improve suggestions based on user behavior
3. **Context Awareness**: Consider user's communication patterns and preferences
4. **Natural Language Processing**: Enhanced message parsing and understanding

## Usage Examples

### Creating an Invite

```swift
let invite = Invite(
    title: "Team Meeting",
    description: "Weekly team standup meeting",
    sentReceived: .sent,
    toPhone: "+1234567890",
    priority: .high,
    dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
    category: "meeting",
    location: "Conference Room A"
)

try await dataProvider.createInvite(invite)
```

### Filtering Invites

```swift
let filter = InviteFilter(
    searchTerm: "meeting",
    status: .pending,
    priority: .high,
    sortBy: .dueDate,
    sortOrder: .forward
)

let invites = try await dataProvider.fetchInvites(offset: 0, limit: 20, filter: filter)
```

### Marking Complete

```swift
try await dataProvider.markInviteComplete(inviteId)
```

## Troubleshooting

### Common Issues

1. **Database Connection**: Ensure SQLite database is properly connected
2. **Foreign Key Constraints**: Verify referenced contacts and messages exist
3. **JSON Parsing**: Check JSON field formats for tags, groups, and AI suggestions
4. **Date Formatting**: Ensure all dates use ISO 8601 format
5. **UUID Validation**: Verify all UUID fields contain valid UUID strings

### Debug Information

The system provides comprehensive logging for:
- Database operations
- AI analysis results
- Task creation and updates
- Error conditions and recovery

## Conclusion

The Invites system provides a comprehensive solution for managing invitations, tasks, and to-do items within the My CRM application. With AI-powered analysis, flexible task hierarchies, and robust recurring task support, it offers a powerful foundation for personal and professional task management.
