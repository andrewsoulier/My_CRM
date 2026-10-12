import Foundation
import SwiftUI
import GRDB

/// GRDB-based data provider with improved concurrency and performance
@MainActor
class GRDBDataProvider: DataProvider, ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var groups: [ContactGroup] = []
    @Published var invites: [Invite] = []
    @Published var tags: [Tag] = []
    @Published var relationships: [Relationship] = []
    
    private let dbManager = GRDBDatabaseManager.shared
    private let contactRepo: ContactRepository
    private let groupRepo: GroupRepository
    private let inviteRepo: InviteRepository
    private let messageRepo: MessageRepository
    private let tagRepo: TagRepository
    private let relationshipRepo: RelationshipRepository
    private let logger = LogManager.shared
    
    init() {
        self.contactRepo = ContactRepository(dbManager: dbManager)
        self.groupRepo = GroupRepository(dbManager: dbManager)
        self.inviteRepo = InviteRepository(dbManager: dbManager)
        self.messageRepo = MessageRepository(dbManager: dbManager)
        self.tagRepo = TagRepository(dbManager: dbManager)
        self.relationshipRepo = RelationshipRepository(dbManager: dbManager)
        
        logger.info("🚀 GRDBDataProvider initialized")
    }
    
    // MARK: - Database Connection
    
    func connectToDatabase(path: String) async throws {
        try await dbManager.connect(to: path)
        
        // Load initial data
        await refreshAll()
        
        // Start observing database changes
        startObservations()
        
        logger.info("✅ GRDBDataProvider connected to database")
    }
    
    func isConnected() -> Bool {
        return dbManager.isConnected
    }
    
    func closeConnection() async throws {
        try await dbManager.disconnect()
        logger.info("✅ GRDBDataProvider disconnected")
    }
    
    // MARK: - Refresh Data
    
    private func refreshAll() async {
        await refreshContacts()
        await refreshGroups()
        await refreshInvites()
        await refreshTags()
        await refreshRelationships()
    }
    
    private func refreshContacts() async {
        do {
            contacts = try await contactRepo.fetchAll()
            logger.info("🔄 Loaded \(contacts.count) contacts")
        } catch {
            logger.error("❌ Failed to load contacts: \(error.localizedDescription)")
        }
    }
    
    private func refreshGroups() async {
        do {
            groups = try await groupRepo.fetchAll()
            logger.info("🔄 Loaded \(groups.count) groups")
        } catch {
            logger.error("❌ Failed to load groups: \(error.localizedDescription)")
        }
    }
    
    private func refreshInvites() async {
        do {
            invites = try await inviteRepo.fetchAll()
            logger.info("🔄 Loaded \(invites.count) invites")
        } catch {
            logger.error("❌ Failed to load invites: \(error.localizedDescription)")
        }
    }
    
    private func refreshTags() async {
        do {
            tags = try await tagRepo.fetchAll()
            logger.info("🔄 Loaded \(tags.count) tags")
        } catch {
            logger.error("❌ Failed to load tags: \(error.localizedDescription)")
        }
    }
    
    private func refreshRelationships() async {
        do {
            relationships = try await relationshipRepo.fetchAll()
            logger.info("🔄 Loaded \(relationships.count) relationships")
        } catch {
            logger.error("❌ Failed to load relationships: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Contact Operations
    
    func fetchContacts(offset: Int, limit: Int, filter: ContactFilter) async throws -> [Contact] {
        if filter.searchTerm.isEmpty {
            return try await contactRepo.fetch(limit: limit, offset: offset)
        } else {
            let allResults = try await contactRepo.search(query: filter.searchTerm)
            let start = min(offset, allResults.count)
            let end = min(offset + limit, allResults.count)
            return Array(allResults[start..<end])
        }
    }
    
    func countContacts(filter: ContactFilter) async throws -> Int {
        if filter.searchTerm.isEmpty {
            return try await contactRepo.count()
        } else {
            let results = try await contactRepo.search(query: filter.searchTerm)
            return results.count
        }
    }
    
    func fetchContact(by phone: String) async throws -> Contact? {
        return try await contactRepo.fetchOne(phone: phone)
    }
    
    func getContact(by phone: String) -> Contact? {
        return contacts.first { $0.phone == phone }
    }
    
    func createContact(_ contact: Contact) async throws {
        try await contactRepo.insert(contact)
        await refreshContacts()
    }
    
    func updateContact(_ contact: Contact) async throws {
        try await contactRepo.upsert(contact)
        await refreshContacts()
    }
    
    func deleteContact(_ phone: String) async throws {
        try await contactRepo.delete(phone: phone)
        await refreshContacts()
    }
    
    // MARK: - Group Operations
    
    func fetchGroups() async throws -> [ContactGroup] {
        return try await groupRepo.fetchAll()
    }
    
    func createGroup(_ group: ContactGroup) async throws {
        try await groupRepo.insert(group)
        await refreshGroups()
    }
    
    func updateGroup(_ group: ContactGroup) async throws {
        try await groupRepo.update(group)
        await refreshGroups()
    }
    
    func deleteGroup(_ id: UUID) async throws {
        try await groupRepo.delete(id: id)
        await refreshGroups()
    }
    
    func deleteGroup(_ id: UUID, fromCanvas canvasId: UUID) async throws {
        // Remove group from canvas
        try await dbManager.write { db in
            guard var group = try ContactGroup.fetchOne(db, id: id) else {
                throw DataProviderError.groupNotFound
            }
            
            group.canvases.remove(canvasId)
            
            // If no canvases left, delete the group entirely
            if group.canvases.isEmpty {
                try group.delete(db)
            } else {
                try group.update(db)
            }
        }
        
        await refreshGroups()
    }
    
    func add(phones: [String], to groupID: UUID) async throws {
        for phone in phones {
            try await groupRepo.addMember(groupID: groupID, phone: phone)
        }
        await refreshGroups()
    }
    
    func addContactWithSource(contactPhone: String, contactName: String, contactUUID: String, to groupID: UUID, sourceType: String, sourceUUID: String) async throws {
        // First ensure contact exists
        if try await contactRepo.fetchOne(phone: contactPhone) == nil {
            let newContact = Contact(
                phone: contactPhone,
                name: contactName
            )
            try await contactRepo.insert(newContact)
            await refreshContacts()
        }
        
        // Add to group
        try await groupRepo.addMember(groupID: groupID, phone: contactPhone)
        await refreshGroups()
    }
    
    func move(phones: [String], from sourceGroupID: UUID?, to targetGroupID: UUID) async throws {
        // Remove from source group if specified
        if let sourceID = sourceGroupID {
            for phone in phones {
                try await groupRepo.removeMember(groupID: sourceID, phone: phone)
            }
        }
        
        // Add to target group
        for phone in phones {
            try await groupRepo.addMember(groupID: targetGroupID, phone: phone)
        }
        
        await refreshGroups()
    }
    
    func remove(phones: [String], from groupID: UUID) async throws {
        for phone in phones {
            try await groupRepo.removeMember(groupID: groupID, phone: phone)
        }
        await refreshGroups()
    }
    
    func removeParticipantEntirely(contactPhone: String, from groupID: UUID) async throws {
        try await groupRepo.removeMember(groupID: groupID, phone: contactPhone)
        await refreshGroups()
    }
    
    func getGroupMembers(groupId: UUID) -> [String]? {
        return groups.first { $0.id == groupId }?.members
    }
    
    func updateGroupMembers(groupId: UUID, members: [String]) async throws {
        try await dbManager.write { db in
            guard var group = try ContactGroup.fetchOne(db, id: groupId) else {
                throw DataProviderError.groupNotFound
            }
            
            group.memberPhones = Set(members)
            try group.update(db)
        }
        await refreshGroups()
    }
    
    // MARK: - Invite Operations
    
    func fetchInvites(offset: Int, limit: Int, filter: InviteFilter) async throws -> [Invite] {
        let allInvites = try await inviteRepo.fetchAll()
        
        // Apply filters
        var filtered = allInvites
        
        if !filter.searchTerm.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(filter.searchTerm) ||
                ($0.description?.localizedCaseInsensitiveContains(filter.searchTerm) ?? false)
            }
        }
        
        if let status = filter.status {
            filtered = filtered.filter { $0.completionStatus == status }
        }
        
        if let priority = filter.priority {
            filtered = filtered.filter { $0.priority == priority }
        }
        
        if let sentReceived = filter.sentReceived {
            filtered = filtered.filter { $0.sentReceived == sentReceived }
        }
        
        // Apply pagination
        let start = min(offset, filtered.count)
        let end = min(offset + limit, filtered.count)
        
        return Array(filtered[start..<end])
    }
    
    func countInvites(filter: InviteFilter) async throws -> Int {
        let invites = try await fetchInvites(offset: 0, limit: Int.max, filter: filter)
        return invites.count
    }
    
    func fetchInvite(by id: UUID) async throws -> Invite? {
        return try await inviteRepo.fetchOne(id: id)
    }
    
    func getInvite(by id: UUID) -> Invite? {
        return invites.first { $0.id == id }
    }
    
    func createInvite(_ invite: Invite) async throws {
        try await inviteRepo.insert(invite)
        await refreshInvites()
    }
    
    func updateInvite(_ invite: Invite) async throws {
        try await inviteRepo.update(invite)
        await refreshInvites()
    }
    
    func deleteInvite(_ id: UUID) async throws {
        try await inviteRepo.delete(id: id)
        await refreshInvites()
    }
    
    func markInviteComplete(_ id: UUID) async throws {
        try await inviteRepo.markCompleted(id: id)
        await refreshInvites()
    }
    
    func markInviteIncomplete(_ id: UUID) async throws {
        try await dbManager.write { db in
            guard var invite = try Invite.fetchOne(db, id: id) else {
                throw DataProviderError.inviteNotFound
            }
            
            invite.completed = false
            invite.dateCompleted = nil
            invite.completionStatus = .pending
            invite.lastModifiedDate = Date()
            
            try invite.update(db)
        }
        await refreshInvites()
    }
    
    func fetchInvitesByContact(phone: String) async throws -> [Invite] {
        return try await inviteRepo.fetchAll(phoneNumber: phone)
    }
    
    func fetchRecurringInvites() async throws -> [Invite] {
        return try await dbManager.read { db in
            try Invite
                .filter(Column("is_recurring") == true)
                .fetchAll(db)
        }
    }
    
    func fetchOverdueInvites() async throws -> [Invite] {
        return try await inviteRepo.fetchOverdue()
    }
    
    func fetchInvitesDueToday() async throws -> [Invite] {
        return try await inviteRepo.fetchDueToday()
    }
    
    func fetchInvitesByMessage(guid: String) async throws -> [Invite] {
        return try await dbManager.read { db in
            try Invite
                .filter(Column("message_origin_guid") == guid)
                .fetchAll(db)
        }
    }
    
    // MARK: - Value Observations
    
    private func startObservations() {
        // Observe contacts
        Task {
            do {
                for try await updatedContacts in contactRepo.observeAll() {
                    self.contacts = updatedContacts
                }
            } catch {
                logger.error("❌ Contact observation failed: \(error.localizedDescription)")
            }
        }
        
        // Observe groups
        Task {
            do {
                for try await updatedGroups in groupRepo.observeAll() {
                    self.groups = updatedGroups
                }
            } catch {
                logger.error("❌ Group observation failed: \(error.localizedDescription)")
            }
        }
        
        // Observe invites
        Task {
            do {
                for try await updatedInvites in inviteRepo.observeAll() {
                    self.invites = updatedInvites
                }
            } catch {
                logger.error("❌ Invite observation failed: \(error.localizedDescription)")
            }
        }
        
        // Observe tags
        Task {
            do {
                for try await updatedTags in tagRepo.observeAll() {
                    self.tags = updatedTags
                }
            } catch {
                logger.error("❌ Tag observation failed: \(error.localizedDescription)")
            }
        }
        
        // Observe relationships
        Task {
            do {
                for try await updatedRelationships in relationshipRepo.observeAll() {
                    self.relationships = updatedRelationships
                }
            } catch {
                logger.error("❌ Relationship observation failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Sendable Conformance

extension GRDBDataProvider: @unchecked Sendable {}

