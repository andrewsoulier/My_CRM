# Database-First Implementation Guide

## Overview

This guide provides practical implementation patterns and examples for developing features following the database-centric architecture principles. All development must ensure that any change to data anywhere is always reflected in the database.

## Database Initialization Sequence

### First Run Setup

On first run, the application follows this initialization sequence:

1. **FirstRunSetup.run()** - Called by StartOrchestrator
   - Creates Application Support directory
   - Migrates old settings if needed
   - Ensures settings file exists
   - Calls `ensureDatabase()`

2. **FirstRunSetup.ensureDatabase()**
   - Creates database directory structure
   - Creates empty database file if it doesn't exist
   - Calls `CRMDatabase.shared.ensureSchema()`

3. **CRMDatabase.ensureSchema()**
   - Creates all required tables using `CREATE TABLE IF NOT EXISTS`:
     - `contacts` table (with all columns)
     - `groups` table (with all columns)
     - `invites` table (with all columns)
   - Safe to call multiple times (idempotent)
   - Logs success/failure for each table

4. **StartOrchestrator** continues with:
   - ContactsImporter (if enabled) - populates contacts from system address book
   - MessagesImporter (if enabled and Full Disk Access granted) - imports messages

### DAO Pattern: Self-Ensuring Schema

Each DAO (Data Access Object) ensures its own table exists before operations:

```swift
final class ContactsDAO {
    func ensureSchema(db: OpaquePointer?) {
        // CREATE TABLE IF NOT EXISTS contacts (...)
    }
    
    func upsert(...) {
        guard let db = try? CRMDatabase.shared.open() else { return }
        ensureSchema(db: db)  // Always ensure table exists
        // ... perform operation
    }
}
```

This pattern ensures:
- Tables are created even if initialization was interrupted
- Individual DAOs can be tested in isolation
- Defensive programming against missing tables
- Matches MessagesDAO pattern (established working pattern)

### Troubleshooting Empty Database

If tables aren't being created:

1. Check logs for `CRMDatabase.ensureSchema` messages
2. Verify `FirstRunSetup.ensureDatabase()` is being called
3. Check database file path in User_Settings.json
4. Verify write permissions on database directory
5. Look for SQLite error messages in logs

## Core Implementation Patterns

### 1. Database-First Service Layer

#### Base Database Service
```swift
protocol DatabaseService {
    func save<T: Codable>(_ data: T, to table: String) async throws
    func load<T: Codable>(_ type: T.Type, from table: String, where id: String) async throws -> T?
    func update<T: Codable>(_ data: T, in table: String) async throws
    func delete(from table: String, where id: String) async throws
    func observe<T: Codable>(_ type: T.Type, from table: String, callback: @escaping ([T]) -> Void)
}

class SQLiteDatabaseService: DatabaseService {
    private let database: SQLiteDatabase
    
    func save<T: Codable>(_ data: T, to table: String) async throws {
        let json = try JSONEncoder().encode(data)
        try await database.execute("INSERT OR REPLACE INTO \(table) (id, data) VALUES (?, ?)", 
                                 parameters: [data.id, String(data: json, encoding: .utf8)!])
    }
    
    func load<T: Codable>(_ type: T.Type, from table: String, where id: String) async throws -> T? {
        let result = try await database.query("SELECT data FROM \(table) WHERE id = ?", parameters: [id])
        guard let data = result.first?["data"] as? String else { return nil }
        return try JSONDecoder().decode(type, from: data.data(using: .utf8)!)
    }
    
    // ... other implementations
}
```

#### Entity-Specific Services
```swift
class ContactDatabaseService: DatabaseService {
    private let databaseService: SQLiteDatabaseService
    
    func createContact(_ contact: Contact) async throws {
        // Validate contact data
        try validateContact(contact)
        
        // Save to database
        try await databaseService.save(contact, to: "contacts")
        
        // Log the operation
        try await logOperation("create_contact", contactId: contact.id)
    }
    
    func updateContact(_ contact: Contact) async throws {
        // Update in database
        try await databaseService.update(contact, in: "contacts")
        
        // Update related data (groups, canvases, etc.)
        try await updateRelatedData(for: contact)
        
        // Log the operation
        try await logOperation("update_contact", contactId: contact.id)
    }
    
    func deleteContact(id: String) async throws {
        // Check for dependencies
        let dependencies = try await checkDependencies(for: id)
        if !dependencies.isEmpty {
            throw DatabaseError.constraintViolation("Contact has dependencies: \(dependencies)")
        }
        
        // Delete from database
        try await databaseService.delete(from: "contacts", where: id)
        
        // Clean up related data
        try await cleanupRelatedData(for: id)
        
        // Log the operation
        try await logOperation("delete_contact", contactId: id)
    }
    
    private func validateContact(_ contact: Contact) throws {
        guard !contact.name.isEmpty else {
            throw DatabaseError.validationError("Contact name cannot be empty")
        }
        guard !contact.phone.isEmpty else {
            throw DatabaseError.validationError("Contact phone cannot be empty")
        }
    }
    
    private func updateRelatedData(for contact: Contact) async throws {
        // Update group memberships
        try await updateGroupMemberships(for: contact)
        
        // Update canvas elements
        try await updateCanvasElements(for: contact)
        
        // Update message statistics
        try await updateMessageStatistics(for: contact)
    }
}
```

#### Grid View Synchronization
- Group membership persistence updates the `contacts.groups` JSON column via `ContactRepository.updateGroups` so smart-chip columns always reflect database truth.
- `GroupRepository` automatically refreshes each affected contact when members change, when groups are deleted, or when group metadata (like the display name) is updated.
- `GridViewViewModel` batches grid edit failures and publishes a single Notification Center alert through `SystemNotificationDispatcher`, while marking invalid cells with `(!)` so users can quickly identify issues.

### 2. Stateless UI Components

#### Contact List View
```swift
struct ContactListView: View {
    @StateObject private var viewModel: ContactListViewModel
    @State private var searchText = ""
    
    var body: some View {
        VStack {
            SearchBar(text: $searchText)
                .onChange(of: searchText) { newValue in
                    Task {
                        await viewModel.searchContacts(query: newValue)
                    }
                }
            
            List(viewModel.contacts) { contact in
                ContactRowView(contact: contact)
                    .onTapGesture {
                        Task {
                            await viewModel.selectContact(contact)
                        }
                    }
            }
        }
        .task {
            await viewModel.loadContacts()
        }
    }
}

class ContactListViewModel: ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var selectedContact: Contact?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let contactService: ContactDatabaseService
    private let uiStateService: UIStateService
    
    init(contactService: ContactDatabaseService, uiStateService: UIStateService) {
        self.contactService = contactService
        self.uiStateService = uiStateService
    }
    
    func loadContacts() async {
        isLoading = true
        do {
            // Load from database
            let loadedContacts = try await contactService.getAllContacts()
            
            await MainActor.run {
                self.contacts = loadedContacts
                self.isLoading = false
            }
            
            // Persist UI state
            try await uiStateService.saveUIState("contact_list", state: ContactListState(contacts: loadedContacts))
            
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func searchContacts(query: String) async {
        do {
            // Search in database
            let results = try await contactService.searchContacts(query: query)
            
            await MainActor.run {
                self.contacts = results
            }
            
            // Persist search history
            try await uiStateService.saveSearchHistory(query: query, resultCount: results.count)
            
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    func selectContact(_ contact: Contact) async {
        await MainActor.run {
            self.selectedContact = contact
        }
        
        // Persist selection state
        try await uiStateService.saveUIState("selected_contact", state: SelectedContactState(contactId: contact.id))
    }
}
```

### 3. Real-time Database Synchronization

#### Database Observer
```swift
class DatabaseObserver {
    private let databaseService: SQLiteDatabaseService
    private var observers: [String: AnyCancellable] = [:]
    
    func observeTable<T: Codable>(_ table: String, type: T.Type, callback: @escaping ([T]) -> Void) {
        let timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                Task {
                    do {
                        let data = try await self.databaseService.loadAll(type, from: table)
                        await MainActor.run {
                            callback(data)
                        }
                    } catch {
                        print("Error observing table \(table): \(error)")
                    }
                }
            }
        
        observers[table] = timer
    }
    
    func observeRecord<T: Codable>(_ table: String, id: String, type: T.Type, callback: @escaping (T?) -> Void) {
        let timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                Task {
                    do {
                        let data = try await self.databaseService.load(type, from: table, where: id)
                        await MainActor.run {
                            callback(data)
                        }
                    } catch {
                        print("Error observing record \(id) in table \(table): \(error)")
                    }
                }
            }
        
        observers["\(table)_\(id)"] = timer
    }
    
    func stopObserving(_ key: String) {
        observers[key]?.cancel()
        observers.removeValue(forKey: key)
    }
}
```

#### Synchronized View Model
```swift
class SynchronizedContactViewModel: ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var isLoading = false
    
    private let contactService: ContactDatabaseService
    private let databaseObserver: DatabaseObserver
    
    init(contactService: ContactDatabaseService, databaseObserver: DatabaseObserver) {
        self.contactService = contactService
        self.databaseObserver = databaseObserver
        
        // Start observing database changes
        databaseObserver.observeTable("contacts", type: Contact.self) { [weak self] contacts in
            self?.contacts = contacts
        }
    }
    
    func createContact(_ contact: Contact) async {
        do {
            try await contactService.createContact(contact)
            // Database observer will automatically update the UI
        } catch {
            // Handle error
            print("Error creating contact: \(error)")
        }
    }
    
    func updateContact(_ contact: Contact) async {
        do {
            try await contactService.updateContact(contact)
            // Database observer will automatically update the UI
        } catch {
            // Handle error
            print("Error updating contact: \(error)")
        }
    }
}
```

### 4. UI State Persistence

#### UI State Service
```swift
struct UIState: Codable {
    let componentName: String
    let stateData: [String: AnyCodable]
    let timestamp: Date
    let userId: String
}

class UIStateService {
    private let databaseService: SQLiteDatabaseService
    
    func saveUIState(_ componentName: String, state: Codable) async throws {
        let uiState = UIState(
            componentName: componentName,
            stateData: try encodeToAnyCodable(state),
            timestamp: Date(),
            userId: "default"
        )
        
        try await databaseService.save(uiState, to: "ui_state")
    }
    
    func loadUIState<T: Codable>(_ componentName: String, type: T.Type) async throws -> T? {
        let states = try await databaseService.loadAll(UIState.self, from: "ui_state")
        let latestState = states
            .filter { $0.componentName == componentName }
            .sorted { $0.timestamp > $1.timestamp }
            .first
        
        guard let state = latestState else { return nil }
        
        return try decodeFromAnyCodable(state.stateData, type: type)
    }
    
    private func encodeToAnyCodable(_ value: Codable) throws -> [String: AnyCodable] {
        let data = try JSONEncoder().encode(value)
        let dictionary = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return dictionary.mapValues { AnyCodable($0) }
    }
    
    private func decodeFromAnyCodable<T: Codable>(_ dictionary: [String: AnyCodable], type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dictionary.mapValues { $0.value })
        return try JSONDecoder().decode(type, from: data)
    }
}
```

#### Persistent UI Component
```swift
struct PersistentContactListView: View {
    @StateObject private var viewModel: ContactListViewModel
    @State private var searchText = ""
    @State private var isExpanded = true
    
    var body: some View {
        VStack {
            if isExpanded {
                SearchBar(text: $searchText)
                List(viewModel.contacts) { contact in
                    ContactRowView(contact: contact)
                }
            }
        }
        .task {
            await viewModel.loadContacts()
            await loadUIState()
        }
        .onChange(of: searchText) { newValue in
            Task {
                await viewModel.searchContacts(query: newValue)
                await saveUIState()
            }
        }
        .onChange(of: isExpanded) { newValue in
            Task {
                await saveUIState()
            }
        }
    }
    
    private func loadUIState() async {
        do {
            let state = try await viewModel.uiStateService.loadUIState("contact_list", type: ContactListUIState.self)
            if let state = state {
                await MainActor.run {
                    self.searchText = state.searchText
                    self.isExpanded = state.isExpanded
                }
            }
        } catch {
            print("Error loading UI state: \(error)")
        }
    }
    
    private func saveUIState() async {
        do {
            let state = ContactListUIState(
                searchText: searchText,
                isExpanded: isExpanded,
                selectedContactId: viewModel.selectedContact?.id
            )
            try await viewModel.uiStateService.saveUIState("contact_list", state: state)
        } catch {
            print("Error saving UI state: \(error)")
        }
    }
}
```

### 5. Error Handling and Recovery

#### Database Error Handling
```swift
enum DatabaseError: Error, LocalizedError {
    case connectionFailed
    case writeFailed
    case readFailed
    case constraintViolation(String)
    case validationError(String)
    case transactionFailed
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Database connection failed"
        case .writeFailed:
            return "Failed to write to database"
        case .readFailed:
            return "Failed to read from database"
        case .constraintViolation(let message):
            return "Database constraint violation: \(message)"
        case .validationError(let message):
            return "Validation error: \(message)"
        case .transactionFailed:
            return "Database transaction failed"
        }
    }
}

class DatabaseErrorHandler {
    func handleError(_ error: DatabaseError) -> RecoveryAction {
        switch error {
        case .connectionFailed:
            return .retryWithBackoff(maxAttempts: 3)
        case .writeFailed:
            return .retryOnce
        case .constraintViolation:
            return .showErrorToUser
        case .validationError:
            return .showErrorToUser
        case .transactionFailed:
            return .rollbackAndRetry
        default:
            return .showErrorToUser
        }
    }
    
    func retryOperation<T>(_ operation: () async throws -> T, maxAttempts: Int = 3) async -> T? {
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                if attempt == maxAttempts {
                    print("Operation failed after \(maxAttempts) attempts: \(error)")
                    return nil
                }
                
                // Exponential backoff
                let delay = pow(2.0, Double(attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        return nil
    }
}
```

### 6. Testing Database-First Components

#### Database Integration Tests
```swift
class ContactDatabaseServiceTests: XCTestCase {
    var databaseService: ContactDatabaseService!
    var testDatabase: SQLiteDatabase!
    
    override func setUp() async throws {
        testDatabase = try SQLiteDatabase(path: ":memory:")
        databaseService = ContactDatabaseService(database: testDatabase)
        
        // Create test schema
        try await testDatabase.execute("""
            CREATE TABLE contacts (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                phone TEXT NOT NULL,
                email TEXT
            )
        """)
    }
    
    func testCreateContact() async throws {
        // Given
        let contact = Contact(id: "1", name: "John Doe", phone: "123-456-7890", email: "john@example.com")
        
        // When
        try await databaseService.createContact(contact)
        
        // Then
        let savedContact = try await databaseService.loadContact(id: "1")
        XCTAssertEqual(savedContact?.name, "John Doe")
        XCTAssertEqual(savedContact?.phone, "123-456-7890")
    }
    
    func testUpdateContact() async throws {
        // Given
        let contact = Contact(id: "1", name: "John Doe", phone: "123-456-7890", email: "john@example.com")
        try await databaseService.createContact(contact)
        
        // When
        let updatedContact = Contact(id: "1", name: "John Smith", phone: "123-456-7890", email: "johnsmith@example.com")
        try await databaseService.updateContact(updatedContact)
        
        // Then
        let savedContact = try await databaseService.loadContact(id: "1")
        XCTAssertEqual(savedContact?.name, "John Smith")
        XCTAssertEqual(savedContact?.email, "johnsmith@example.com")
    }
    
    func testDeleteContact() async throws {
        // Given
        let contact = Contact(id: "1", name: "John Doe", phone: "123-456-7890", email: "john@example.com")
        try await databaseService.createContact(contact)
        
        // When
        try await databaseService.deleteContact(id: "1")
        
        // Then
        let savedContact = try await databaseService.loadContact(id: "1")
        XCTAssertNil(savedContact)
    }
}
```

#### UI Component Tests
```swift
class ContactListViewTests: XCTestCase {
    func testContactListReflectsDatabaseState() async throws {
        // Given
        let mockDatabaseService = MockContactDatabaseService()
        let mockUIStateService = MockUIStateService()
        let viewModel = ContactListViewModel(
            contactService: mockDatabaseService,
            uiStateService: mockUIStateService
        )
        
        // When
        await viewModel.loadContacts()
        
        // Then
        XCTAssertEqual(viewModel.contacts.count, 2)
        XCTAssertEqual(viewModel.contacts[0].name, "John Doe")
        XCTAssertEqual(viewModel.contacts[1].name, "Jane Smith")
    }
    
    func testSearchPersistsToDatabase() async throws {
        // Given
        let mockDatabaseService = MockContactDatabaseService()
        let mockUIStateService = MockUIStateService()
        let viewModel = ContactListViewModel(
            contactService: mockDatabaseService,
            uiStateService: mockUIStateService
        )
        
        // When
        await viewModel.searchContacts(query: "John")
        
        // Then
        XCTAssertTrue(mockUIStateService.saveSearchHistoryCalled)
        XCTAssertEqual(mockUIStateService.lastSearchQuery, "John")
    }
}
```

## Implementation Checklist

### Before Starting Development
- [ ] Design database schema for the feature
- [ ] Update `database_requirements.json` with new tables/columns
- [ ] Create database migration scripts if needed
- [ ] Plan error handling and recovery strategies

### During Development
- [ ] Implement database service layer first
- [ ] Create data models with proper Codable conformance
- [ ] Implement UI components as stateless database views
- [ ] Add real-time database synchronization
- [ ] Implement UI state persistence
- [ ] Add comprehensive error handling

### After Development
- [ ] Write database integration tests
- [ ] Write UI component tests
- [ ] Test database recovery scenarios
- [ ] Verify all user interactions persist to database
- [ ] Test with different database states
- [ ] Update documentation

## Common Pitfalls to Avoid

### 1. Local State Without Database Persistence
```swift
// ❌ Wrong - Local state not persisted
@State private var selectedContacts: Set<String> = []

// ✅ Correct - State persisted to database
@StateObject private var selectionManager: SelectionManager
```

### 2. UI Updates Without Database Changes
```swift
// ❌ Wrong - UI update without database persistence
func updateContactName(_ name: String) {
    contact.name = name
    // Missing database update
}

// ✅ Correct - Database update first
func updateContactName(_ name: String) async {
    contact.name = name
    try await contactService.updateContact(contact)
}
```

### 3. Missing Error Handling
```swift
// ❌ Wrong - No error handling
func createContact(_ contact: Contact) {
    contactService.createContact(contact)
}

// ✅ Correct - Proper error handling
func createContact(_ contact: Contact) async {
    do {
        try await contactService.createContact(contact)
    } catch {
        await MainActor.run {
            self.errorMessage = error.localizedDescription
        }
    }
}
```

## UI Data Synchronization

### Centralized Refresh Function

The `SQLiteDataProvider` includes a centralized `refreshUIData()` function that ensures all UI components stay synchronized with the database:

```swift
/// Refreshes all UI data by reloading contacts and groups from the database
/// This ensures all UI components display the current database state
func refreshUIData() async {
    logger.info("🔄 Refreshing UI data from database...")
    
    // Reload contacts from database
    await loadContactsFromDatabase()
    
    // Reload groups from database
    await loadGroupsFromDatabase()
    
    // Trigger SwiftUI updates via @Published properties
    objectWillChange.send()
    
    logger.info("✅ UI data refreshed - Contacts: \(contacts.count), Groups: \(groups.count)")
}
```

### Automatic UI Updates

All database modification methods automatically call `refreshUIData()` after saving changes:

**Contact Operations:**
- `updateContact(_:)` - Updates contact and refreshes UI
- `deleteContact(_:)` - Deletes contact and refreshes UI

**Group Operations:**
- `createGroup(_:)` - Creates group with proper UUID from database ID and refreshes UI
- `updateGroup(_:)` - Updates group and refreshes UI
- `deleteGroup(_:)` - Deletes group and refreshes UI
- `deleteGroup(_:fromCanvas:)` - Removes group from canvas and refreshes UI
- `updateGroupMembers(groupId:members:)` - Updates group members and refreshes UI
- `add(phones:to:)` - Adds members to group and refreshes UI

**UUID Generation:**
- Groups created via `createGroup()` use `saveGroupToDatabaseAndGetId()` which inserts into the database first
- The auto-incremented database ID is used to generate a deterministic UUID: `00000000-0000-0000-0000-%012d`
- This ensures proper bidirectional mapping between database IDs and UUIDs

### How It Works

1. **Database Write**: Any modification method saves changes to the database
2. **Refresh Call**: Method calls `await refreshUIData()`
3. **Data Reload**: `refreshUIData()` reloads contacts and groups from database
4. **SwiftUI Update**: `@Published` properties trigger UI updates automatically
5. **All Views Update**: Contact nav bar, group nav bar, contacts toolbar, and groups toolbar all reflect the new state

### Benefits

- **Single Source of Truth**: Database is always the authoritative source
- **No Missed Updates**: Every database change triggers a UI refresh
- **Consistent State**: All UI components show the same data
- **Simple Implementation**: One function handles all refresh logic
- **Prevents Stale Data**: UI can never show outdated information

## Conclusion

Following this implementation guide ensures that all features maintain the database-centric architecture principles. Every user interaction is immediately persisted to the database, UI components reflect database state, and the application can work with any database containing the proper schema.

The centralized `refreshUIData()` function ensures that all UI components always display the current database state, eliminating synchronization issues and providing a consistent user experience.

Remember: **Database First, UI Second** - Always design and implement the database layer before creating UI components.
