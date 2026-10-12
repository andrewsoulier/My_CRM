import Foundation
import SwiftUI
import GRDB

@MainActor
final class GridViewService {
    
    // MARK: - Nested Types
    
    struct ContactColumns {
        static let name = "contact.name"
        static let firstName = "contact.first_name"
        static let lastName = "contact.last_name"
        static let nickname = "contact.nickname"
        static let phone = "contact.phone"
        static let email = "contact.email"
        static let address = "contact.address"
        static let notes = "contact.notes"
        static let creationDate = "contact.creation_date"
        static let birthday = "contact.birthday"
        static let groups = "contact.groups"
        static let tags = "contact.tags"
        static let relationships = "contact.relationships"
        static let totalMessages = "contact.total_messages"
        static let messagesSent = "contact.messages_sent"
        static let messagesReceived = "contact.messages_received"
        static let lastMessageReceived = "contact.last_message_received"
        static let lastMessageSent = "contact.last_message_sent"
        static let profilePhoto = "contact.profile_photo"
    }
    
    struct GroupColumns {
        static let name = "group.name"
        static let participants = "group.participants"
        static let color = "group.color"
        static let createdAt = "group.created_at"
        static let size = "group.size"
        static let tags = "group.tags"
        static let children = "group.children"
        static let parents = "group.parents"
    }
    
    enum GridCellValuePayload {
        case string(String)
        case number(Double)
        case date(Date)
        case chips([String])
        case empty
        
        var trimmedString: String? {
            switch self {
            case let .string(value):
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case .empty:
                return nil
            default:
                return nil
            }
        }
    }
    
    enum GridViewServiceError: LocalizedError {
        case contactNotFound(String)
        case groupNotFound(UUID)
        case columnReadOnly(String)
        case invalidValue(String)
        case unsupportedColumn(String)
        case missingDatabaseIdentifier
        case databaseNotConnected(String)
        
        var errorDescription: String? {
            switch self {
            case let .contactNotFound(phone):
                return "Contact with phone \(phone) was not found."
            case let .groupNotFound(id):
                return "Group \(id.uuidString) was not found."
            case let .columnReadOnly(column):
                return "Column \(column) is read-only."
            case let .invalidValue(details):
                return "Invalid value: \(details)."
            case let .unsupportedColumn(column):
                return "Column \(column) is not supported for editing."
            case .missingDatabaseIdentifier:
                return "Database ID is required for this operation."
            case let .databaseNotConnected(path):
                return "Grid data is unavailable because the database at \(path) is not connected. Open Settings → Database to reconnect."
            }
        }
    }
    
    // MARK: - Dependencies
    
    private let contactRepository: ContactRepository
    private let groupRepository: GroupRepository
    private let tagService: TagService
    private let relationshipService: RelationshipService
    private let gridRepository: GridViewRepository
    
    private let readOnlyContactColumns: Set<String> = [
        ContactColumns.totalMessages,
        ContactColumns.messagesSent,
        ContactColumns.messagesReceived,
        ContactColumns.lastMessageReceived,
        ContactColumns.lastMessageSent
    ]
    
    private let readOnlyGroupColumns: Set<String> = [
        GroupColumns.size,
        GroupColumns.parents
    ]
    
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private func ensureDatabaseConnected() throws {
        let manager = GRDBDatabaseManager.shared
        let userPath = SettingsManager.shared.settings.database.path
        
        // Check if connected
        guard manager.isConnected else {
            throw GridViewServiceError.databaseNotConnected(userPath)
        }
        
        // Verify the connected path matches the user's configured path
        // This handles cases where the user changed the database path in settings
        if let connectedPath = manager.currentDatabasePath, connectedPath != userPath {
            // Path mismatch - GRDB is connected to a different database
            throw GridViewServiceError.databaseNotConnected(userPath)
        }
    }
    
    /// Ensures GRDBDatabaseManager is connected to the user's configured database path
    /// Reconnects if necessary (e.g., when user changes database path in settings)
    func ensureGRDBConnected() async throws {
        let manager = GRDBDatabaseManager.shared
        let userPath = SettingsManager.shared.settings.database.path
        
        // Check if already connected to the correct path
        if manager.isConnected, 
           let connectedPath = manager.currentDatabasePath,
           connectedPath == userPath {
            return // Already connected to correct path
        }
        
        // Need to connect or reconnect
        try await manager.connect(to: userPath)
    }
    
    // MARK: - Lifecycle
    
    init(
        contactRepository: ContactRepository? = nil,
        groupRepository: GroupRepository? = nil,
        tagService: TagService? = nil,
        relationshipService: RelationshipService? = nil,
        gridRepository: GridViewRepository? = nil
    ) {
        self.contactRepository = contactRepository ?? ContactRepository()
        self.groupRepository = groupRepository ?? GroupRepository()
        self.tagService = tagService ?? TagService()
        self.relationshipService = relationshipService ?? RelationshipService()
        self.gridRepository = gridRepository ?? GridViewRepository()
    }
    
    // MARK: - Paging
    
    func fetchContacts(offset: Int = 0, limit: Int = 200, sorts: [GridSortDescriptor] = [], filters: [String: AnyCodable] = [:]) async throws -> [Contact] {
        try ensureDatabaseConnected()
        return try await contactRepository.fetch(limit: limit, offset: offset, sorts: sorts, filters: filters)
    }
    
    func fetchContacts(offset: Int = 0, limit: Int = 200, sorts: [GridSortDescriptor] = [], filterModel: FilterModel) async throws -> [Contact] {
        try ensureDatabaseConnected()
        return try await contactRepository.fetch(limit: limit, offset: offset, sorts: sorts, filterModel: filterModel)
    }
    
    func countContacts(filters: [String: AnyCodable] = [:]) async throws -> Int {
        try ensureDatabaseConnected()
        return try await contactRepository.count(filters: filters)
    }
    
    func countContacts(filterModel: FilterModel) async throws -> Int {
        try ensureDatabaseConnected()
        return try await contactRepository.count(filterModel: filterModel)
    }
    
    func fetchGroups(offset: Int = 0, limit: Int = 200, sorts: [GridSortDescriptor] = [], filters: [String: AnyCodable] = [:]) async throws -> [ContactGroup] {
        try ensureDatabaseConnected()
        return try await groupRepository.fetch(limit: limit, offset: offset, sorts: sorts, filters: filters)
    }
    
    func fetchGroups(offset: Int = 0, limit: Int = 200, sorts: [GridSortDescriptor] = [], filterModel: FilterModel) async throws -> [ContactGroup] {
        try ensureDatabaseConnected()
        return try await groupRepository.fetch(limit: limit, offset: offset, sorts: sorts, filterModel: filterModel)
    }
    
    func countGroups(filters: [String: AnyCodable] = [:]) async throws -> Int {
        try ensureDatabaseConnected()
        return try await groupRepository.count(filters: filters)
    }
    
    func countGroups(filterModel: FilterModel) async throws -> Int {
        try ensureDatabaseConnected()
        return try await groupRepository.count(filterModel: filterModel)
    }
    
    // MARK: - View Presets & Custom Columns
    
    func fetchViews(for entityType: GridEntityType, userId: String = "default") async throws -> [GridViewConfig] {
        try ensureDatabaseConnected()
        return try await gridRepository.fetchViews(entityType: entityType, userId: userId)
    }
    
    func fetchView(uuid: UUID) async throws -> GridViewConfig? {
        try ensureDatabaseConnected()
        return try await gridRepository.fetchView(uuid: uuid)
    }
    
    func save(view: GridViewConfig) async throws {
        try ensureDatabaseConnected()
        try await gridRepository.upsert(view: view)
    }
    
    func deleteView(uuid: UUID) async throws {
        try ensureDatabaseConnected()
        try await gridRepository.delete(viewUUID: uuid)
    }
    
    func fetchCustomColumns(for entityType: GridEntityType, userId: String = "default", viewUUID: UUID? = nil) async throws -> [GridCustomColumn] {
        try ensureDatabaseConnected()
        return try await gridRepository.fetchCustomColumns(entityType: entityType, userId: userId, viewUUID: viewUUID)
    }

    func fetchCustomCellValues(columnUUIDs: [UUID], recordIds: [String]) async throws -> [String: [UUID: String?]] {
        try ensureDatabaseConnected()
        guard !columnUUIDs.isEmpty, !recordIds.isEmpty else { return [:] }
        let values = try await gridRepository.fetchCellValues(forColumns: columnUUIDs, recordIds: recordIds)
        var result: [String: [UUID: String?]] = [:]
        for value in values {
            var entry = result[value.recordId] ?? [:]
            entry[value.columnId] = value.value
            result[value.recordId] = entry
        }
        return result
    }
    
    func save(customColumn: GridCustomColumn) async throws {
        try ensureDatabaseConnected()
        try await gridRepository.upsert(column: customColumn)
    }
    
    func deleteCustomColumn(uuid: UUID) async throws {
        try ensureDatabaseConnected()
        try await gridRepository.deleteColumn(uuid: uuid)
    }
    
    func updateCustomCell(sessionId: UUID, columnUUID: UUID, recordId: String, entityType: GridEntityType, newValue: String?) async throws -> GridCustomCellValue {
        try ensureDatabaseConnected()
        let existing = try await gridRepository.fetchCellValues(forColumns: [columnUUID], recordIds: [recordId]).first
        let previousValue = existing?.value
        
        var cellValue = GridCustomCellValue(
            databaseId: existing?.databaseId,
            columnId: columnUUID,
            recordId: recordId,
            entityType: entityType,
            value: newValue,
            updatedAt: Date()
        )
        
        try await gridRepository.upsert(cellValues: [cellValue])
        
        let entry = GridEditLogEntry(
            databaseId: nil,
            sessionId: sessionId,
            entityType: entityType,
            recordId: recordId,
            columnId: columnUUID.uuidString,
            previousValue: previousValue,
            nextValue: newValue,
            createdAt: Date(),
            direction: .undo
        )
        try await gridRepository.appendEditLogEntry(entry)
        
        // refresh from DB to capture generated ID
        if let refreshed = try await gridRepository.fetchCellValues(forColumns: [columnUUID], recordIds: [recordId]).first {
            cellValue = refreshed
        }
        return cellValue
    }
    
    // MARK: - Contact Editing
    
    @discardableResult
    func editContact(sessionId: UUID, phone: String, columnId: String, newValue: GridCellValuePayload) async throws -> Contact {
        try ensureDatabaseConnected()
        guard !readOnlyContactColumns.contains(columnId) else {
            throw GridViewServiceError.columnReadOnly(columnId)
        }
        
        guard let contact = try await contactRepository.fetchOne(phone: phone) else {
            throw GridViewServiceError.contactNotFound(phone)
        }
        
        let previousValue = try await contactValueString(contact, columnId: columnId)
        let updatedContact = try await applyContactChange(original: contact, columnId: columnId, payload: newValue)
        let nextValue = try await contactValueString(updatedContact, columnId: columnId)
        
        if previousValue != nextValue {
            let entry = GridEditLogEntry(
                databaseId: nil,
                sessionId: sessionId,
                entityType: .contacts,
                recordId: recordIdentifier(for: updatedContact),
                columnId: columnId,
                previousValue: previousValue,
                nextValue: nextValue,
                createdAt: Date(),
                direction: .undo
            )
            try await gridRepository.appendEditLogEntry(entry)
        }
        
        return updatedContact
    }
    
    // MARK: - Group Editing
    
    @discardableResult
    func editGroup(sessionId: UUID, groupID: UUID, columnId: String, newValue: GridCellValuePayload) async throws -> ContactGroup {
        try ensureDatabaseConnected()
        guard !readOnlyGroupColumns.contains(columnId) else {
            throw GridViewServiceError.columnReadOnly(columnId)
        }
        
        guard let group = try await groupRepository.fetchOne(id: groupID) else {
            throw GridViewServiceError.groupNotFound(groupID)
        }
        
        let previousValue = try await groupValueString(group, columnId: columnId)
        let updatedGroup = try await applyGroupChange(original: group, columnId: columnId, payload: newValue)
        let nextValue = try await groupValueString(updatedGroup, columnId: columnId)
        
        if previousValue != nextValue {
            let entry = GridEditLogEntry(
                databaseId: nil,
                sessionId: sessionId,
                entityType: .groups,
                recordId: updatedGroup.id.uuidString,
                columnId: columnId,
                previousValue: previousValue,
                nextValue: nextValue,
                createdAt: Date(),
                direction: .undo
            )
            try await gridRepository.appendEditLogEntry(entry)
        }
        
        return updatedGroup
    }
    
    // MARK: - Undo / Redo
    
    func undoLatest(sessionId: UUID) async throws -> GridEditLogEntry? {
        try ensureDatabaseConnected()
        guard var entry = try await gridRepository.fetchEditLog(sessionId: sessionId, direction: .undo, limit: 1).first else {
            return nil
        }
        
        try await applyLogEntry(entry, targetValue: entry.previousValue)
        
        if let id = entry.databaseId {
            try await gridRepository.updateEditLogDirection(databaseId: id, direction: .redo, previousValue: entry.previousValue, nextValue: entry.nextValue)
        }
        
        entry.direction = .redo
        return entry
    }
    
    func redoLatest(sessionId: UUID) async throws -> GridEditLogEntry? {
        try ensureDatabaseConnected()
        guard var entry = try await gridRepository.fetchEditLog(sessionId: sessionId, direction: .redo, limit: 1).first else {
            return nil
        }
        
        try await applyLogEntry(entry, targetValue: entry.nextValue)
        
        if let id = entry.databaseId {
            try await gridRepository.updateEditLogDirection(databaseId: id, direction: .undo, previousValue: entry.previousValue, nextValue: entry.nextValue)
        }
        
        entry.direction = .undo
        return entry
    }
    
    // MARK: - Helpers
    
    private func applyContactChange(original contact: Contact, columnId: String, payload: GridCellValuePayload) async throws -> Contact {
        try ensureDatabaseConnected()
        var mutable = contact
        
        switch columnId {
        case ContactColumns.name:
            mutable.name = payload.trimmedString ?? ""
            try await contactRepository.update(mutable)
            
        case ContactColumns.firstName:
            mutable.firstName = payload.trimmedString
            try await contactRepository.update(mutable)
            
        case ContactColumns.lastName:
            mutable.lastName = payload.trimmedString
            try await contactRepository.update(mutable)
            
        case ContactColumns.nickname:
            mutable.nickname = payload.trimmedString
            try await contactRepository.update(mutable)
            
        case ContactColumns.phone:
            throw GridViewServiceError.columnReadOnly(columnId) // safeguard until phone updates are supported
            
        case ContactColumns.email:
            mutable.email = payload.trimmedString
            try await contactRepository.update(mutable)
            
        case ContactColumns.address:
            mutable.address = payload.trimmedString
            try await contactRepository.update(mutable)
            
        case ContactColumns.notes:
            mutable.notes = payload.trimmedString
            try await contactRepository.update(mutable)
            
        case ContactColumns.creationDate:
            mutable.creationDate = try date(from: payload)
            try await contactRepository.update(mutable)
            
        case ContactColumns.birthday:
            mutable.birthday = try date(from: payload)
            try await contactRepository.update(mutable)
            
        case ContactColumns.groups:
            let names = try chipStrings(from: payload)
            try await updateContactGroups(contact: mutable, newGroupNames: names)
            
        case ContactColumns.tags:
            let names = try chipStrings(from: payload)
            mutable = try await updateContactTags(contact: mutable, newTagNames: names)
            
        case ContactColumns.relationships:
            let names = try chipStrings(from: payload)
            mutable = try await updateContactRelationships(contact: mutable, newRelationshipNames: names)
            
        case ContactColumns.profilePhoto:
            // Handle image data URL (data:image/png;base64,...) or file path
            if let imageString = payload.trimmedString, !imageString.isEmpty {
                if imageString.hasPrefix("data:image") {
                    // Extract base64 data from data URL
                    let components = imageString.components(separatedBy: ",")
                    if components.count == 2, let base64Data = Data(base64Encoded: components[1]) {
                        mutable.profilePhotoData = base64Data
                    }
                } else if let imageData = try? Data(contentsOf: URL(fileURLWithPath: imageString)) {
                    // Handle file path
                    mutable.profilePhotoData = imageData
                }
            } else {
                mutable.profilePhotoData = nil
            }
            try await contactRepository.update(mutable)
            
        default:
            throw GridViewServiceError.unsupportedColumn(columnId)
        }
        
        // refresh contact from database to ensure values like tag IDs are current
        if let refreshed = try await contactRepository.fetchOne(phone: mutable.phone) {
            return refreshed
        }
        return mutable
    }
    
    private func applyGroupChange(original group: ContactGroup, columnId: String, payload: GridCellValuePayload) async throws -> ContactGroup {
        try ensureDatabaseConnected()
        var mutable = group
        
        switch columnId {
        case GroupColumns.name:
            guard let value = payload.trimmedString, !value.isEmpty else {
                throw GridViewServiceError.invalidValue("Group name cannot be empty")
            }
            mutable.name = value
            try await groupRepository.update(mutable)
            
        case GroupColumns.color:
            guard let hex = payload.trimmedString else {
                throw GridViewServiceError.invalidValue("Color value required")
            }
            if let color = Color(hex: hex) {
                mutable.color = color
                mutable.colorHexString = hex
                try await groupRepository.update(mutable)
            } else {
                throw GridViewServiceError.invalidValue("Invalid color hex \(hex)")
            }
            
        case GroupColumns.participants:
            let members = try chipStrings(from: payload)
            try await updateGroupParticipants(group: mutable, memberPhones: members)
            
        case GroupColumns.tags:
            let names = try chipStrings(from: payload)
            mutable = try await updateGroupTags(group: mutable, tagNames: names)
            
        case GroupColumns.children:
            let names = try chipStrings(from: payload)
            mutable = try await updateChildGroups(group: mutable, childNames: names)
            
        case GroupColumns.createdAt:
            mutable.createdAt = try date(from: payload) ?? mutable.createdAt
            try await groupRepository.update(mutable)
            
        default:
            throw GridViewServiceError.unsupportedColumn(columnId)
        }
        
        if let refreshed = try await groupRepository.fetchOne(id: mutable.id) {
            return refreshed
        }
        return mutable
    }
    
    private func updateContactGroups(contact: Contact, newGroupNames: [String]) async throws {
        try ensureDatabaseConnected()
        let trimmed = Set(newGroupNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let currentGroups = try await groupRepository.fetchContaining(phone: contact.phone)
        let currentByName = Dictionary(uniqueKeysWithValues: currentGroups.map { ($0.name.lowercased(), $0) })
        
        // Remove from groups no longer present
        for group in currentGroups where !trimmed.contains(group.name) {
            try await groupRepository.removeMember(groupID: group.id, phone: contact.phone)
        }
        
        // Ensure membership for requested groups
        for name in trimmed {
            if let existing = currentByName[name.lowercased()] {
                // ensure membership, repository handles duplicates
                try await groupRepository.addMember(groupID: existing.id, phone: contact.phone)
            } else {
                var newGroup = ContactGroup(name: name)
                try await groupRepository.insert(newGroup)
                newGroup = try await groupRepository.fetchOne(id: newGroup.id) ?? newGroup
                try await groupRepository.addMember(groupID: newGroup.id, phone: contact.phone)
            }
        }
    }
    
    private func updateContactTags(contact: Contact, newTagNames: [String]) async throws -> Contact {
        try ensureDatabaseConnected()
        guard let contactId = contact.databaseId else {
            throw GridViewServiceError.missingDatabaseIdentifier
        }
        
        let trimmed = OrderedSet(newTagNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        var resolvedTagIDs: [UUID] = []
        
        for name in trimmed {
            let tag = try await tagService.ensureTag(name: name)
            resolvedTagIDs.append(tag.id)
            try await tagService.assign(tagUUID: tag.id, toContact: contactId)
        }
        
        // Remove tags that are no longer associated
        for tagID in contact.tagIDs where !resolvedTagIDs.contains(tagID) {
            try await tagService.remove(tagUUID: tagID, fromContact: contactId)
        }
        
        try await contactRepository.updateTagIDs(phone: contact.phone, tagIDs: resolvedTagIDs)
        
        var mutable = contact
        mutable.tagIDs = resolvedTagIDs
        return mutable
    }
    
    private func updateContactRelationships(contact: Contact, newRelationshipNames: [String]) async throws -> Contact {
        try ensureDatabaseConnected()
        guard let contactId = contact.databaseId else {
            throw GridViewServiceError.missingDatabaseIdentifier
        }
        
        let trimmed = OrderedSet(newRelationshipNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        var resolvedRelationshipIDs: [UUID] = []
        
        for name in trimmed {
            let relationship = try await relationshipService.ensureRelationship(name: name)
            resolvedRelationshipIDs.append(relationship.id)
            try await relationshipService.assign(relationshipUUID: relationship.id, toContact: contactId)
        }
        
        for relationshipID in contact.relationshipIDs where !resolvedRelationshipIDs.contains(relationshipID) {
            try await relationshipService.remove(relationshipUUID: relationshipID, fromContact: contactId)
        }
        
        try await contactRepository.updateRelationshipIDs(phone: contact.phone, relationshipIDs: resolvedRelationshipIDs)
        
        var mutable = contact
        mutable.relationshipIDs = resolvedRelationshipIDs
        return mutable
    }
    
    private func updateGroupParticipants(group: ContactGroup, memberPhones: [String]) async throws {
        try ensureDatabaseConnected()
        let trimmed = Set(memberPhones.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let currentMembers = Set(group.memberPhones)
        
        // Remove absent members (this will update participants JSON via GroupRepository)
        for phone in currentMembers where !trimmed.contains(phone) {
            try await groupRepository.removeMember(groupID: group.id, phone: phone)
        }
        
        // Add new members (this will update participants JSON with names via GroupRepository)
        for phone in trimmed where !currentMembers.contains(phone) {
            try await groupRepository.addMember(groupID: group.id, phone: phone)
        }
        
        // Also update names for existing participants in case contact names have changed
        // This ensures all participants have current names
        for phone in trimmed.intersection(currentMembers) {
            try await groupRepository.addMember(groupID: group.id, phone: phone)
        }
    }
    
    private func updateGroupTags(group: ContactGroup, tagNames: [String]) async throws -> ContactGroup {
        try ensureDatabaseConnected()
        let trimmed = OrderedSet(tagNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        var resolvedTagIDs: [UUID] = []
        
        for name in trimmed {
            let tag = try await tagService.ensureTag(name: name)
            resolvedTagIDs.append(tag.id)
            // Link group via tag repository (group UUID stored)
            try await tagService.assign(tagUUID: tag.id, toGroup: group.id)
        }
        
        for tagID in group.tags where !resolvedTagIDs.contains(tagID) {
            try await tagService.remove(tagUUID: tagID, fromGroup: group.id)
        }
        
        var mutable = group
        mutable.tags = Set(resolvedTagIDs)
        try await groupRepository.update(mutable)
        
        if let refreshed = try await groupRepository.fetchOne(id: mutable.id) {
            return refreshed
        }
        return mutable
    }
    
    private func updateChildGroups(group: ContactGroup, childNames: [String]) async throws -> ContactGroup {
        try ensureDatabaseConnected()
        let trimmed = OrderedSet(childNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        var resolvedChildIDs: [UUID] = []
        
        for name in trimmed {
            let existing = try await groupRepository.search(query: name).first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            if let match = existing {
                resolvedChildIDs.append(match.id)
                try await groupRepository.updateParentGroups(groupID: match.id, parentIDs: [group.id])
            } else {
                var child = ContactGroup(name: name)
                child.parentID = group.id
                try await groupRepository.insert(child)
                resolvedChildIDs.append(child.id)
            }
        }
        
        var mutable = group
        mutable.childGroupIDs = Set(resolvedChildIDs)
        try await groupRepository.update(mutable)
        
        if let refreshed = try await groupRepository.fetchOne(id: mutable.id) {
            return refreshed
        }
        return mutable
    }
    
    private func contactValueString(_ contact: Contact, columnId: String) async throws -> String? {
        try ensureDatabaseConnected()
        switch columnId {
        case ContactColumns.name:
            return contact.name
        case ContactColumns.firstName:
            return contact.firstName
        case ContactColumns.lastName:
            return contact.lastName
        case ContactColumns.nickname:
            return contact.nickname
        case ContactColumns.phone:
            return contact.phone
        case ContactColumns.email:
            return contact.email
        case ContactColumns.address:
            return contact.address
        case ContactColumns.notes:
            return contact.notes
        case ContactColumns.creationDate:
            if let date = contact.creationDate {
                return isoFormatter.string(from: date)
            }
            return nil
        case ContactColumns.birthday:
            if let date = contact.birthday {
                return isoFormatter.string(from: date)
            }
            return nil
        case ContactColumns.groups:
            let groups = try await groupRepository.fetchContaining(phone: contact.phone)
            let names = groups.map { $0.name }.sorted()
            return try jsonString(from: names)
        case ContactColumns.tags:
            let tagsByID = Dictionary(uniqueKeysWithValues: tagService.allTags().map { ($0.id, $0.name) })
            let names = contact.tagIDs.compactMap { tagsByID[$0] }.sorted()
            return try jsonString(from: names)
        case ContactColumns.relationships:
            let relationsByID = Dictionary(uniqueKeysWithValues: relationshipService.allRelationships().map { ($0.id, $0.name) })
            let names = contact.relationshipIDs.compactMap { relationsByID[$0] }.sorted()
            return try jsonString(from: names)
        case ContactColumns.totalMessages:
            return nil
        case ContactColumns.messagesSent:
            return nil
        case ContactColumns.messagesReceived:
            return nil
        case ContactColumns.lastMessageReceived:
            if let date = contact.lastMessageReceivedDate ?? contact.lastMessageDate {
                return isoFormatter.string(from: date)
            }
            return nil
        case ContactColumns.lastMessageSent:
            if let date = contact.lastMessageSentDate ?? contact.lastMessageDate {
                return isoFormatter.string(from: date)
            }
            return nil
        case ContactColumns.profilePhoto:
            // Return base64 data URL if photo exists
            if let photoData = contact.profilePhotoData, !photoData.isEmpty {
                let base64 = photoData.base64EncodedString()
                return "data:image/png;base64,\(base64)"
            }
            return nil
        default:
            return nil
        }
    }
    
    private func groupValueString(_ group: ContactGroup, columnId: String) async throws -> String? {
        try ensureDatabaseConnected()
        switch columnId {
        case GroupColumns.name:
            return group.name
        case GroupColumns.participants:
            let members = group.members.sorted()
            return try jsonString(from: members)
        case GroupColumns.color:
            return group.colorHexString
        case GroupColumns.tags:
            let tagsByID = Dictionary(uniqueKeysWithValues: tagService.allTags().map { ($0.id, $0.name) })
            let names = group.tags.compactMap { tagsByID[$0] }.sorted()
            return try jsonString(from: names)
        case GroupColumns.children:
            let children = try await trimmedChildGroupNames(for: group)
            return try jsonString(from: children)
        case GroupColumns.parents:
            let parents = try await trimmedParentGroupNames(for: group)
            return try jsonString(from: parents)
        case GroupColumns.createdAt:
            return isoFormatter.string(from: group.createdAt)
        case GroupColumns.size:
            return "\(group.memberCount)"
        default:
            return nil
        }
    }
    
    private func trimmedChildGroupNames(for group: ContactGroup) async throws -> [String] {
        try ensureDatabaseConnected()
        var names: [String] = []
        for id in group.childGroupIDs {
            if let child = try await groupRepository.fetchOne(id: id) {
                names.append(child.name)
            }
        }
        return names.sorted()
    }
    
    private func trimmedParentGroupNames(for group: ContactGroup) async throws -> [String] {
        try ensureDatabaseConnected()
        var names: [String] = []
        for id in group.parentGroupIDs {
            if let parent = try await groupRepository.fetchOne(id: id) {
                names.append(parent.name)
            }
        }
        return names.sorted()
    }
    
    private func chipStrings(from payload: GridCellValuePayload) throws -> [String] {
        switch payload {
        case let .chips(values):
            return values
        case let .string(value):
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return []
            }
            return value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        case .empty:
            return []
        default:
            throw GridViewServiceError.invalidValue("Expected chip values")
        }
    }
    
    private func date(from payload: GridCellValuePayload) throws -> Date? {
        switch payload {
        case let .date(date):
            return date
        case let .string(value):
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil
            }
            if let date = isoFormatter.date(from: value) {
                return date
            }
            throw GridViewServiceError.invalidValue("Unable to parse date \(value)")
        case .empty:
            return nil
        default:
            throw GridViewServiceError.invalidValue("Expected date value")
        }
    }
    
    private func jsonString(from values: [String]) throws -> String {
        let data = try JSONEncoder().encode(values)
        guard let string = String(data: data, encoding: .utf8) else {
            throw GridViewServiceError.invalidValue("Unable to encode JSON")
        }
        return string
    }
    
    private func recordIdentifier(for contact: Contact) -> String {
        if let databaseId = contact.databaseId {
            return "contact:\(databaseId)"
        }
        return "contact:\(contact.phone)"
    }
    
    private func applyLogEntry(_ entry: GridEditLogEntry, targetValue: String?) async throws {
        switch entry.entityType {
        case .contacts:
            try await applyContactLogEntry(entry, targetValue: targetValue)
        case .groups:
            try await applyGroupLogEntry(entry, targetValue: targetValue)
        }
    }
    
    private func applyContactLogEntry(_ entry: GridEditLogEntry, targetValue: String?) async throws {
        try ensureDatabaseConnected()
        let recordId = entry.recordId
        let phone: String
        
        if recordId.starts(with: "contact:") {
            let identifier = String(recordId.dropFirst("contact:".count))
            if let databaseID = Int64(identifier), let contact = try await fetchContactBy(databaseId: databaseID) {
                try await restoreContact(contact: contact, columnId: entry.columnId, serializedValue: targetValue)
                return
            } else if let fallback = try await contactRepository.fetchOne(phone: identifier) {
                try await restoreContact(contact: fallback, columnId: entry.columnId, serializedValue: targetValue)
                return
            }
        }
        
        // Fallback: interpret recordId as phone number
        if recordId.starts(with: "contact:") {
            phone = String(recordId.dropFirst("contact:".count))
        } else {
            phone = recordId
        }
        
        guard let contact = try await contactRepository.fetchOne(phone: phone) else {
            throw GridViewServiceError.contactNotFound(phone)
        }
        try await restoreContact(contact: contact, columnId: entry.columnId, serializedValue: targetValue)
    }
    
    private func restoreContact(contact: Contact, columnId: String, serializedValue: String?) async throws {
        switch columnId {
        case ContactColumns.groups, ContactColumns.tags, ContactColumns.relationships:
            if let serializedValue,
               let data = serializedValue.data(using: .utf8),
               let names = try? JSONDecoder().decode([String].self, from: data) {
                let payload = GridCellValuePayload.chips(names)
                _ = try await applyContactChange(original: contact, columnId: columnId, payload: payload)
            } else {
                _ = try await applyContactChange(original: contact, columnId: columnId, payload: .chips([]))
            }
        case ContactColumns.creationDate, ContactColumns.birthday:
            if let serializedValue {
                if let date = isoFormatter.date(from: serializedValue) {
                    _ = try await applyContactChange(original: contact, columnId: columnId, payload: .date(date))
                } else {
                    _ = try await applyContactChange(original: contact, columnId: columnId, payload: .empty)
                }
            } else {
                _ = try await applyContactChange(original: contact, columnId: columnId, payload: .empty)
            }
        default:
            if let value = serializedValue {
                _ = try await applyContactChange(original: contact, columnId: columnId, payload: .string(value))
            } else {
                _ = try await applyContactChange(original: contact, columnId: columnId, payload: .empty)
            }
        }
    }
    
    private func applyGroupLogEntry(_ entry: GridEditLogEntry, targetValue: String?) async throws {
        try ensureDatabaseConnected()
        guard let groupUUID = UUID(uuidString: entry.recordId),
              let group = try await groupRepository.fetchOne(id: groupUUID) else {
            throw GridViewServiceError.groupNotFound(UUID(uuidString: entry.recordId) ?? UUID())
        }
        
        switch entry.columnId {
        case GroupColumns.participants, GroupColumns.tags, GroupColumns.children:
            if let value = targetValue,
               let data = value.data(using: .utf8),
               let names = try? JSONDecoder().decode([String].self, from: data) {
                let payload = GridCellValuePayload.chips(names)
                _ = try await applyGroupChange(original: group, columnId: entry.columnId, payload: payload)
            } else {
                _ = try await applyGroupChange(original: group, columnId: entry.columnId, payload: .chips([]))
            }
        case GroupColumns.createdAt:
            if let value = targetValue,
               let date = isoFormatter.date(from: value) {
                _ = try await applyGroupChange(original: group, columnId: entry.columnId, payload: .date(date))
            }
        default:
            if let value = targetValue {
                _ = try await applyGroupChange(original: group, columnId: entry.columnId, payload: .string(value))
            }
        }
    }
    
    private func fetchContactBy(databaseId: Int64) async throws -> Contact? {
        try ensureDatabaseConnected()
        let contacts = try await contactRepository.fetch(limit: Int.max, offset: 0)
        return contacts.first { $0.databaseId == databaseId }
    }
    
    func groupNames(for contact: Contact) async throws -> [String] {
        try ensureDatabaseConnected()
        let groups = try await groupRepository.fetchContaining(phone: contact.phone)
        return groups.map { $0.name }.sorted()
    }
    
    func groupsWithColors(for contact: Contact) async throws -> [[String: Any]] {
        try ensureDatabaseConnected()
        let groups = try await groupRepository.fetchContaining(phone: contact.phone)
        return groups.sorted(by: { $0.name < $1.name }).map { group in
            [
                "name": group.name,
                "color": group.colorHexString ?? ""
            ]
        }
    }
    
    func tagNames(for contact: Contact) -> [String] {
        let tagsByID = Dictionary(uniqueKeysWithValues: tagService.allTags().map { ($0.id, $0.name) })
        return contact.tagIDs.compactMap { tagsByID[$0] }.sorted()
    }
    
    func relationshipNames(for contact: Contact) -> [String] {
        let relationshipsByID = Dictionary(uniqueKeysWithValues: relationshipService.allRelationships().map { ($0.id, $0.name) })
        return contact.relationshipIDs.compactMap { relationshipsByID[$0] }.sorted()
    }
    
    func tagNames(for group: ContactGroup) -> [String] {
        let tagsByID = Dictionary(uniqueKeysWithValues: tagService.allTags().map { ($0.id, $0.name) })
        return group.tags.compactMap { tagsByID[$0] }.sorted()
    }
    
    func childGroupNames(for group: ContactGroup) async throws -> [String] {
        try ensureDatabaseConnected()
        return try await trimmedChildGroupNames(for: group)
    }
    
    func parentGroupNames(for group: ContactGroup) async throws -> [String] {
        try ensureDatabaseConnected()
        return try await trimmedParentGroupNames(for: group)
    }
    
    func participantNames(for group: ContactGroup) async throws -> [String] {
        try ensureDatabaseConnected()
        // First try to get names from participants JSON in database
        if let participants = try await getParticipantsFromDatabase(groupId: group.id) {
            let names = participants.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
            if !names.isEmpty {
                return names.sorted()
            }
        }
        
        // Fallback: look up contact names by phone number
        var names: [String] = []
        for phone in group.memberPhones.sorted() {
            if let contact = try? await contactRepository.fetchOne(phone: phone) {
                names.append(contact.name)
            } else {
                // If contact not found, use phone number as fallback
                names.append(phone)
            }
        }
        return names
    }
    
    private func getParticipantsFromDatabase(groupId: UUID) async throws -> [[String: Any]]? {
        try ensureDatabaseConnected()
        guard let dbManager = try? GRDBDatabaseManager.shared else { return nil }
        
        return try await dbManager.read { db in
            if let row = try? Row.fetchOne(db, sql: "SELECT participants FROM groups WHERE id = ?", arguments: [groupId.uuidString]),
               let participantsJson: String = row["participants"],
               !participantsJson.isEmpty,
               let data = participantsJson.data(using: .utf8),
               let participants = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return participants
            }
            return nil
        }
    }
    
    func fetchContact(recordIdentifier: String) async throws -> Contact {
        try ensureDatabaseConnected()
        if recordIdentifier.starts(with: "contact:") {
            let identifier = String(recordIdentifier.dropFirst("contact:".count))
            if let databaseId = Int64(identifier), let contact = try await contactRepository.fetchOne(databaseId: databaseId) {
                return contact
            } else if let contact = try await contactRepository.fetchOne(phone: identifier) {
                return contact
            }
        }
        if let contact = try await contactRepository.fetchOne(phone: recordIdentifier) {
            return contact
        }
        throw GridViewServiceError.contactNotFound(recordIdentifier)
    }
    
    func fetchGroup(recordIdentifier: String) async throws -> ContactGroup {
        try ensureDatabaseConnected()
        if let uuid = UUID(uuidString: recordIdentifier),
           let group = try await groupRepository.fetchOne(id: uuid) {
            return group
        }
        throw GridViewServiceError.groupNotFound(UUID(uuidString: recordIdentifier) ?? UUID())
    }
    
    // MARK: - Delete Operations
    
    /// Delete contacts by their record identifiers (phone numbers)
    func deleteContacts(recordIds: [String]) async throws {
        try ensureDatabaseConnected()
        for recordId in recordIds {
            try await contactRepository.delete(phone: recordId)
        }
    }
    
    /// Delete groups by their record identifiers (UUID strings)
    func deleteGroups(recordIds: [String]) async throws {
        try ensureDatabaseConnected()
        for recordId in recordIds {
            // Handle both UUID format and integer IDs (legacy format)
            let groupId: UUID
            if let uuid = UUID(uuidString: recordId) {
                groupId = uuid
            } else if let integerId = Int(recordId) {
                // Convert integer ID to UUID format: 00000000-0000-0000-0000-%012d
                let uuidString = String(format: "00000000-0000-0000-0000-%012d", integerId)
                guard let convertedUUID = UUID(uuidString: uuidString) else {
                    throw GridViewServiceError.invalidValue("Failed to convert integer ID to UUID: \(recordId)")
                }
                groupId = convertedUUID
            } else {
                throw GridViewServiceError.invalidValue("Invalid group identifier format: \(recordId)")
            }
            try await groupRepository.delete(id: groupId)
        }
    }
    
    // MARK: - Notification Helpers
    
    func batchNotificationMessage(for errors: [GridViewServiceError]) -> String? {
        guard !errors.isEmpty else { return nil }
        if errors.count == 1 {
            return errors.first?.localizedDescription
        }
        return "\(errors.count) errors with pasting data"
    }
}

// MARK: - OrderedSet Helper

private struct OrderedSet<Element: Hashable>: Sequence {
    private var ordered: [Element] = []
    private var set: Set<Element> = []
    
    init<S: Sequence>(_ sequence: S) where S.Element == Element {
        for element in sequence {
            append(element)
        }
    }
    
    mutating func append(_ element: Element) {
        if set.insert(element).inserted {
            ordered.append(element)
        }
    }
    
    func map<T>(_ transform: (Element) -> T) -> [T] {
        ordered.map(transform)
    }
    
    func filter(_ isIncluded: (Element) -> Bool) -> OrderedSet<Element> {
        OrderedSet<Element>(ordered.filter(isIncluded))
    }
    
    func contains(_ element: Element) -> Bool {
        set.contains(element)
    }
    
    func toArray() -> [Element] {
        ordered
    }
    
    func makeIterator() -> IndexingIterator<[Element]> {
        ordered.makeIterator()
    }
}

