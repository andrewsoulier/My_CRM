import Foundation
import SwiftUI
@testable import My_CRM

/// Test fixtures for automated testing
/// Provides consistent test data for contacts, groups, and other entities
struct TestData {
    
    // MARK: - Test Contacts
    
    static let testContacts: [Contact] = [
        Contact(
            phone: "101-101-0001",
            name: "Test1",
            firstName: "Test",
            lastName: "1",
            email: "test1@example.com",
            address: "123 Test St",
            notes: "Test contact 1",
            business: "Test Company 1"
        ),
        Contact(
            phone: "101-101-0002",
            name: "Test2",
            firstName: "Test",
            lastName: "2",
            email: "test2@example.com",
            address: "456 Test Ave",
            notes: "Test contact 2",
            business: "Test Company 2"
        ),
        Contact(
            phone: "101-101-0003",
            name: "Test3",
            firstName: "Test",
            lastName: "3",
            email: "test3@example.com",
            address: "789 Test Blvd",
            notes: "Test contact 3",
            business: "Test Company 3"
        ),
        Contact(
            phone: "101-101-0004",
            name: "Test4",
            firstName: "Test",
            lastName: "4",
            email: "test4@example.com",
            address: "321 Test Rd",
            notes: "Test contact 4",
            business: "Test Company 4"
        ),
        Contact(
            phone: "101-101-0005",
            name: "Test5",
            firstName: "Test",
            lastName: "5",
            email: "test5@example.com",
            address: "654 Test Ln",
            notes: "Test contact 5",
            business: "Test Company 5"
        )
    ]
    
    // MARK: - Test Groups
    
    static let testGroups: [ContactGroup] = [
        ContactGroup(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "TestGroup1",
            color: .blue,
            isDeck: false
        ),
        ContactGroup(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "TestGroup2",
            color: .green,
            isDeck: false
        ),
        ContactGroup(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "TestGroup3",
            color: .red,
            isDeck: false
        ),
        ContactGroup(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            name: "TestGroup4",
            color: .orange,
            isDeck: false
        ),
        ContactGroup(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            name: "TestGroup5",
            color: .purple,
            isDeck: false
        )
    ]
    
    // MARK: - Test Decks
    
    static let testDecks: [ContactGroup] = [
        ContactGroup(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "TestDeck1",
            color: .cyan,
            isDeck: true
        ),
        ContactGroup(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: "TestDeck2",
            color: .mint,
            isDeck: true
        )
    ]
    
    // MARK: - Test Phone Numbers
    
    static let testPhoneNumbers: [String] = [
        "101-101-0001",
        "101-101-0002", 
        "101-101-0003",
        "101-101-0004",
        "101-101-0005"
    ]
    
    // MARK: - Test UUIDs
    
    static let testContactUUIDs: [UUID] = [
        UUID(uuidString: "AAAAAAAA-0001-0001-0001-000000000001")!,
        UUID(uuidString: "AAAAAAAA-0002-0002-0002-000000000002")!,
        UUID(uuidString: "AAAAAAAA-0003-0003-0003-000000000003")!,
        UUID(uuidString: "AAAAAAAA-0004-0004-0004-000000000004")!,
        UUID(uuidString: "AAAAAAAA-0005-0005-0005-000000000005")!
    ]
    
    // MARK: - Helper Methods
    
    /// Creates a test contact with custom phone number
    static func createTestContact(phone: String, name: String) -> Contact {
        return Contact(
            phone: phone,
            name: name,
            firstName: name,
            lastName: "Test",
            email: "\(name.lowercased())@example.com",
            address: "123 Test St",
            notes: "Test contact: \(name)",
            business: "Test Company"
        )
    }
    
    /// Creates a test group with custom name and ID
    static func createTestGroup(name: String, id: UUID? = nil) -> ContactGroup {
        return ContactGroup(
            id: id ?? UUID(),
            name: name,
            color: .blue,
            isDeck: false
        )
    }
    
    /// Creates a test deck with custom name and ID
    static func createTestDeck(name: String, id: UUID? = nil) -> ContactGroup {
        return ContactGroup(
            id: id ?? UUID(),
            name: name,
            color: .cyan,
            isDeck: true
        )
    }
    
    /// Creates a ContactDragItem for testing
    static func createTestDragItem(phones: [String], origin: DragOrigin) -> ContactDragItem {
        let uuids = phones.compactMap { phone in
            testContacts.first(where: { $0.phone == phone })?.contactUUID
        }
        return ContactDragItem(phones: phones, uuids: uuids, origin: origin)
    }
    
    /// Creates a mock data provider with test data
    static func createMockDataProvider() -> MockDataProvider {
        let provider = MockDataProvider()
        provider.contacts = testContacts
        provider.groups = testGroups + testDecks
        return provider
    }
}

// MARK: - Mock Data Provider for Testing

class MockDataProvider: DataProvider {
    var contacts: [Contact] = []
    var groups: [ContactGroup] = []
    var decks: [ContactGroup] = []
    
    // MARK: - Contact Operations
    
    func getAllContacts() async throws -> [Contact] {
        return contacts
    }
    
    func getContact(by phone: String) async throws -> Contact? {
        return contacts.first { $0.phone == phone }
    }
    
    func createContact(_ contact: Contact) async throws {
        contacts.append(contact)
    }
    
    func updateContact(_ contact: Contact) async throws {
        if let index = contacts.firstIndex(where: { $0.phone == contact.phone }) {
            contacts[index] = contact
        }
    }
    
    func deleteContact(phone: String) async throws {
        contacts.removeAll { $0.phone == phone }
    }
    
    // MARK: - Group Operations
    
    func getAllGroups() async throws -> [ContactGroup] {
        return groups
    }
    
    func getGroup(by id: UUID) async throws -> ContactGroup? {
        return groups.first { $0.id == id }
    }
    
    func createGroup(_ group: ContactGroup) async throws {
        groups.append(group)
    }
    
    func updateGroup(_ group: ContactGroup) async throws {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        }
    }
    
    func deleteGroup(id: UUID) async throws {
        groups.removeAll { $0.id == id }
    }
    
    func getGroupMembers(groupId: UUID) -> [String]? {
        return groups.first { $0.id == groupId }?.members
    }
    
    func updateGroupMembers(groupId: UUID, members: [String]) async throws {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            groups[index].memberPhones = Set(members)
        }
    }
    
    // MARK: - Deck Operations
    
    func getAllDecks() async throws -> [ContactGroup] {
        return decks
    }
    
    func getDeck(by id: UUID) async throws -> ContactGroup? {
        return decks.first { $0.id == id }
    }
    
    func createDeck(_ deck: ContactGroup) async throws {
        decks.append(deck)
    }
    
    func updateDeck(_ deck: ContactGroup) async throws {
        if let index = decks.firstIndex(where: { $0.id == deck.id }) {
            decks[index] = deck
        }
    }
    
    func deleteDeck(id: UUID) async throws {
        decks.removeAll { $0.id == id }
    }
    
    // MARK: - Search Operations
    
    func searchContacts(query: String) async throws -> [Contact] {
        return contacts.filter { contact in
            contact.name.localizedCaseInsensitiveContains(query) ||
            contact.phone.contains(query) ||
            contact.email?.localizedCaseInsensitiveContains(query) == true
        }
    }
    
    // MARK: - Database Operations
    
    func initializeDatabase() async throws {
        // Mock implementation - no actual database operations
    }
    
    func closeDatabase() async throws {
        // Mock implementation - no actual database operations
    }
}
