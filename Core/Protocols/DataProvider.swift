import Foundation
import SwiftUI

// MARK: - Filter Types
struct ContactFilter {
    var searchTerm: String = ""
    var sortBy: ContactSortOption = .name
    var groupFilter: UUID?
    var tagFilter: String?
    
    enum ContactSortOption: String, CaseIterable {
        case name = "Name"
        case recent = "Recent"
        case company = "Company"
        case tags = "Tags"
    }
}

// MARK: - DataProvider Protocol
@preconcurrency
protocol DataProvider: ObservableObject, Sendable {
    // Contact operations
    func fetchContacts(offset: Int, limit: Int, filter: ContactFilter) async throws -> [Contact]
    func countContacts(filter: ContactFilter) async throws -> Int
    func fetchContact(by phone: String) async throws -> Contact?
    func getContact(by phone: String) -> Contact?
    func createContact(_ contact: Contact) async throws
    func updateContact(_ contact: Contact) async throws
    func deleteContact(_ phone: String) async throws
    
    // Group operations
    func fetchGroups() async throws -> [ContactGroup]
    func createGroup(_ group: ContactGroup) async throws
    func updateGroup(_ group: ContactGroup) async throws
    func deleteGroup(_ id: UUID) async throws
    func deleteGroup(_ id: UUID, fromCanvas canvasId: UUID) async throws
    func add(phones: [String], to groupID: UUID) async throws
    func addContactWithSource(contactPhone: String, contactName: String, contactUUID: String, to groupID: UUID, sourceType: String, sourceUUID: String) async throws
    func move(phones: [String], from sourceGroupID: UUID?, to targetGroupID: UUID) async throws
    func remove(phones: [String], from groupID: UUID) async throws
    func removeParticipantEntirely(contactPhone: String, from groupID: UUID) async throws
    func getGroupMembers(groupId: UUID) -> [String]?
    func updateGroupMembers(groupId: UUID, members: [String]) async throws
    
    // Invite operations
    func fetchInvites(offset: Int, limit: Int, filter: InviteFilter) async throws -> [Invite]
    func countInvites(filter: InviteFilter) async throws -> Int
    func fetchInvite(by id: UUID) async throws -> Invite?
    func getInvite(by id: UUID) -> Invite?
    func createInvite(_ invite: Invite) async throws
    func updateInvite(_ invite: Invite) async throws
    func deleteInvite(_ id: UUID) async throws
    func markInviteComplete(_ id: UUID) async throws
    func markInviteIncomplete(_ id: UUID) async throws
    func fetchInvitesByContact(phone: String) async throws -> [Invite]
    func fetchRecurringInvites() async throws -> [Invite]
    func fetchOverdueInvites() async throws -> [Invite]
    func fetchInvitesDueToday() async throws -> [Invite]
    func fetchInvitesByMessage(guid: String) async throws -> [Invite]
    
    // SQLite specific operations
    func connectToDatabase(path: String) async throws
    func isConnected() -> Bool
    func closeConnection() async throws
}

// MARK: - ImageProvider Protocol
protocol ImageProvider {
    func fetchProfileImage(for contact: Contact) async throws -> NSImage?
    func saveProfileImage(_ image: NSImage, for contact: Contact) async throws
    func deleteProfileImage(for contact: Contact) async throws
}

// MARK: - Persistence Protocol
protocol Persistence {
    func save<T: Codable>(_ object: T, forKey key: String) throws
    func load<T: Codable>(_ type: T.Type, forKey key: String) throws -> T?
    func delete(forKey key: String) throws
    func clearAll() throws
}

// MARK: - Error Types
enum DataProviderError: Error, LocalizedError {
    case databaseConnectionFailed
    case queryFailed(String)
    case contactNotFound
    case groupNotFound
    case inviteNotFound
    case canvasNotFound
    case invalidData
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .databaseConnectionFailed:
            return "Failed to connect to database"
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .contactNotFound:
            return "Contact not found"
        case .groupNotFound:
            return "Group not found"
        case .canvasNotFound:
            return "Canvas not found"
        case .inviteNotFound:
            return "Invite not found"
        case .invalidData:
            return "Invalid data format"
        case .permissionDenied:
            return "Permission denied"
        }
    }
}
