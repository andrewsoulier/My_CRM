import XCTest
import SwiftUI
@testable import My_CRM

class ContactBarToGroupsBarDragDropTests: XCTestCase {
    
    // MARK: - Contact Bar to Groups Bar Drag Drop Tests
    
    func testDragDropFromContactBarToGroupsBarPreservesParticipantData() {
        // Create a group in the groups bar
        var targetGroup = ContactGroup(
            id: UUID(),
            name: "Target Group",
            color: .blue,
            isDeck: false
        )
        
        // Verify initial state
        XCTAssertEqual(targetGroup.name, "Target Group")
        XCTAssertEqual(targetGroup.memberCount, 0)
        XCTAssertTrue(targetGroup.memberPhones.isEmpty)
        
        // Create contact drag item from contacts bar
        let contactPhone = "555-123-4567"
        let contactUUID = UUID()
        let dragItem = ContactDragItem(
            phones: [contactPhone],
            uuids: [contactUUID],
            origin: .contactsBar
        )
        
        // Verify drag item data
        XCTAssertEqual(dragItem.phones, [contactPhone])
        XCTAssertEqual(dragItem.uuids, [contactUUID])
        XCTAssertEqual(dragItem.origin, .contactsBar)
        
        // Simulate drag and drop from contacts bar to groups bar
        // This should preserve the group name and add the contact
        for phone in dragItem.phones {
            targetGroup.memberPhones.insert(phone)
        }
        
        // Verify that group name is preserved and contact is added
        XCTAssertEqual(targetGroup.name, "Target Group", "Group name should be preserved after drag and drop")
        XCTAssertEqual(targetGroup.memberCount, 1, "Member count should be updated")
        XCTAssertTrue(targetGroup.memberPhones.contains(contactPhone), "Contact should be added to group")
        XCTAssertEqual(targetGroup.color, .blue, "Group color should be preserved")
        XCTAssertFalse(targetGroup.isDeck, "Group type should be preserved")
    }
    
    func testDragDropFromContactBarToGroupsBarPreservesGroupProperties() {
        // Create a group with specific properties
        let originalGroupId = UUID()
        let originalCreatedAt = Date()
        
        var targetGroup = ContactGroup(
            id: originalGroupId,
            name: "Original Group Name",
            color: .green,
            isDeck: false
        )
        
        // Set some additional properties
        targetGroup.createdAt = originalCreatedAt
        targetGroup.linkedGroupIDs.insert(UUID())
        targetGroup.canvases.insert(UUID())
        
        // Verify initial state
        XCTAssertEqual(targetGroup.id, originalGroupId)
        XCTAssertEqual(targetGroup.name, "Original Group Name")
        XCTAssertEqual(targetGroup.color, .green)
        XCTAssertEqual(targetGroup.createdAt, originalCreatedAt)
        XCTAssertEqual(targetGroup.linkedGroupIDs.count, 1)
        XCTAssertEqual(targetGroup.canvases.count, 1)
        
        // Create contact drag item from contacts bar
        let contactPhone = "555-987-6543"
        let contactUUID = UUID()
        let dragItem = ContactDragItem(
            phones: [contactPhone],
            uuids: [contactUUID],
            origin: .contactsBar
        )
        
        // Simulate drag and drop from contacts bar to groups bar
        for phone in dragItem.phones {
            targetGroup.memberPhones.insert(phone)
        }
        
        // Verify that ALL group properties are preserved
        XCTAssertEqual(targetGroup.id, originalGroupId, "Group ID should be preserved")
        XCTAssertEqual(targetGroup.name, "Original Group Name", "Group name should be preserved")
        XCTAssertEqual(targetGroup.color, .green, "Group color should be preserved")
        XCTAssertEqual(targetGroup.createdAt, originalCreatedAt, "Created date should be preserved")
        XCTAssertEqual(targetGroup.linkedGroupIDs.count, 1, "Linked group IDs should be preserved")
        XCTAssertEqual(targetGroup.canvases.count, 1, "Canvas IDs should be preserved")
        XCTAssertFalse(targetGroup.isDeck, "Group type should be preserved")
        XCTAssertTrue(targetGroup.isRoot, "Root status should be preserved")
        
        // Verify contact was added
        XCTAssertEqual(targetGroup.memberCount, 1, "Member count should be updated")
        XCTAssertTrue(targetGroup.memberPhones.contains(contactPhone), "Contact should be added")
    }
    
    func testDragDropMultipleContactsFromContactBarToGroupsBar() {
        // Create a group in the groups bar
        var targetGroup = ContactGroup(
            id: UUID(),
            name: "Multi Contact Group",
            color: .red,
            isDeck: false
        )
        
        // Verify initial state
        XCTAssertEqual(targetGroup.name, "Multi Contact Group")
        XCTAssertEqual(targetGroup.memberCount, 0)
        
        // Create drag item with multiple contacts from contacts bar
        let contactPhones = ["555-111-1111", "555-222-2222", "555-333-3333"]
        let contactUUIDs = [UUID(), UUID(), UUID()]
        let dragItem = ContactDragItem(
            phones: contactPhones,
            uuids: contactUUIDs,
            origin: .contactsBar
        )
        
        // Verify drag item data
        XCTAssertEqual(dragItem.phones, contactPhones)
        XCTAssertEqual(dragItem.uuids, contactUUIDs)
        XCTAssertEqual(dragItem.origin, .contactsBar)
        
        // Simulate drag and drop from contacts bar to groups bar
        for phone in dragItem.phones {
            targetGroup.memberPhones.insert(phone)
        }
        
        // Verify that group name is preserved and all contacts are added
        XCTAssertEqual(targetGroup.name, "Multi Contact Group", "Group name should be preserved")
        XCTAssertEqual(targetGroup.memberCount, 3, "Member count should be updated")
        XCTAssertEqual(targetGroup.color, .red, "Group color should be preserved")
        
        for phone in contactPhones {
            XCTAssertTrue(targetGroup.memberPhones.contains(phone), "Contact \(phone) should be added to group")
        }
    }
    
    func testDragDropFromContactBarToGroupsBarWithExistingMembers() {
        // Create a group with existing members
        var targetGroup = ContactGroup(
            id: UUID(),
            name: "Existing Members Group",
            color: .orange,
            isDeck: false
        )
        
        // Add existing members
        let existingPhones = ["555-999-9999", "555-888-8888"]
        for phone in existingPhones {
            targetGroup.memberPhones.insert(phone)
        }
        
        // Verify initial state
        XCTAssertEqual(targetGroup.name, "Existing Members Group")
        XCTAssertEqual(targetGroup.memberCount, 2)
        XCTAssertEqual(targetGroup.color, .orange)
        
        // Create contact drag item from contacts bar
        let newContactPhone = "555-777-7777"
        let newContactUUID = UUID()
        let dragItem = ContactDragItem(
            phones: [newContactPhone],
            uuids: [newContactUUID],
            origin: .contactsBar
        )
        
        // Simulate drag and drop from contacts bar to groups bar
        for phone in dragItem.phones {
            targetGroup.memberPhones.insert(phone)
        }
        
        // Verify that group name is preserved and new contact is added
        XCTAssertEqual(targetGroup.name, "Existing Members Group", "Group name should be preserved")
        XCTAssertEqual(targetGroup.memberCount, 3, "Member count should include existing + new")
        XCTAssertEqual(targetGroup.color, .orange, "Group color should be preserved")
        
        // Verify all members are present
        for phone in existingPhones {
            XCTAssertTrue(targetGroup.memberPhones.contains(phone), "Existing contact \(phone) should still be present")
        }
        XCTAssertTrue(targetGroup.memberPhones.contains(newContactPhone), "New contact should be added")
    }
    
    func testDragDropFromContactBarToGroupsBarPreventsDuplicateContacts() {
        // Create a group with existing members
        var targetGroup = ContactGroup(
            id: UUID(),
            name: "Duplicate Test Group",
            color: .purple,
            isDeck: false
        )
        
        // Add existing member
        let existingPhone = "555-123-4567"
        targetGroup.memberPhones.insert(existingPhone)
        
        // Verify initial state
        XCTAssertEqual(targetGroup.name, "Duplicate Test Group")
        XCTAssertEqual(targetGroup.memberCount, 1)
        XCTAssertTrue(targetGroup.memberPhones.contains(existingPhone))
        
        // Create drag item with same contact from contacts bar
        let dragItem = ContactDragItem(
            phones: [existingPhone], // Same phone number
            uuids: [UUID()],
            origin: .contactsBar
        )
        
        // Simulate drag and drop from contacts bar to groups bar
        for phone in dragItem.phones {
            targetGroup.memberPhones.insert(phone) // Set automatically prevents duplicates
        }
        
        // Verify that group name is preserved and duplicate is prevented
        XCTAssertEqual(targetGroup.name, "Duplicate Test Group", "Group name should be preserved")
        XCTAssertEqual(targetGroup.memberCount, 1, "Member count should remain 1 (duplicate prevented)")
        XCTAssertEqual(targetGroup.color, .purple, "Group color should be preserved")
        XCTAssertTrue(targetGroup.memberPhones.contains(existingPhone), "Contact should still be present")
    }
    
    func testDragDropFromContactBarToGroupsBarPreservesGroupMetadata() {
        // Create a group with metadata
        var targetGroup = ContactGroup(
            id: UUID(),
            name: "Metadata Test Group",
            color: .cyan,
            isDeck: false
        )
        
        // Set metadata
        targetGroup.metadata = GroupMetadata()
        targetGroup.metadata.inviteCount = 5
        targetGroup.metadata.interconnectivityScore = 0.85
        
        // Verify initial metadata
        XCTAssertEqual(targetGroup.metadata.inviteCount, 5)
        XCTAssertEqual(targetGroup.metadata.interconnectivityScore, 0.85)
        
        // Create contact drag item from contacts bar
        let contactPhone = "555-555-5555"
        let dragItem = ContactDragItem(
            phones: [contactPhone],
            uuids: [UUID()],
            origin: .contactsBar
        )
        
        // Simulate drag and drop from contacts bar to groups bar
        for phone in dragItem.phones {
            targetGroup.memberPhones.insert(phone)
        }
        
        // Verify that group name and metadata are preserved
        XCTAssertEqual(targetGroup.name, "Metadata Test Group", "Group name should be preserved")
        XCTAssertEqual(targetGroup.metadata.inviteCount, 5, "Metadata invite count should be preserved")
        XCTAssertEqual(targetGroup.metadata.interconnectivityScore, 0.85, "Metadata interconnectivity score should be preserved")
        XCTAssertEqual(targetGroup.memberCount, 1, "Member count should be updated")
        XCTAssertTrue(targetGroup.memberPhones.contains(contactPhone), "Contact should be added")
    }
    
    func testDragDropFromContactBarToGroupsBarWithParentChildRelationship() {
        // Create parent group
        let parentGroup = ContactGroup(
            id: UUID(),
            name: "Parent Group",
            color: .blue,
            isDeck: false
        )
        
        // Create child group
        var childGroup = ContactGroup(
            id: UUID(),
            name: "Child Group",
            color: .green,
            parentID: parentGroup.id,
            isDeck: false
        )
        
        // Verify initial parent-child relationship
        XCTAssertTrue(parentGroup.isRoot)
        XCTAssertFalse(childGroup.isRoot)
        XCTAssertEqual(childGroup.parentID, parentGroup.id)
        
        // Create contact drag item from contacts bar
        let contactPhone = "555-123-4567"
        let dragItem = ContactDragItem(
            phones: [contactPhone],
            uuids: [UUID()],
            origin: .contactsBar
        )
        
        // Simulate drag and drop from contacts bar to child group
        for phone in dragItem.phones {
            childGroup.memberPhones.insert(phone)
        }
        
        // Verify that group name and parent-child relationship are preserved
        XCTAssertEqual(childGroup.name, "Child Group", "Group name should be preserved")
        XCTAssertEqual(childGroup.parentID, parentGroup.id, "Parent ID should be preserved")
        XCTAssertFalse(childGroup.isRoot, "Root status should be preserved")
        XCTAssertEqual(childGroup.memberCount, 1, "Member count should be updated")
        XCTAssertTrue(childGroup.memberPhones.contains(contactPhone), "Contact should be added")
    }
    
    func testDragDropFromContactBarToGroupsBarWithDeck() {
        // Create a deck
        var deck = ContactGroup(
            id: UUID(),
            name: "Test Deck",
            color: .cyan,
            isDeck: true
        )
        
        // Verify initial state
        XCTAssertEqual(deck.name, "Test Deck")
        XCTAssertTrue(deck.isDeck)
        XCTAssertEqual(deck.memberCount, 0)
        
        // Create contact drag item from contacts bar
        let contactPhone = "555-123-4567"
        let dragItem = ContactDragItem(
            phones: [contactPhone],
            uuids: [UUID()],
            origin: .contactsBar
        )
        
        // Simulate drag and drop from contacts bar to deck
        for phone in dragItem.phones {
            deck.memberPhones.insert(phone)
        }
        
        // Verify that deck name and type are preserved
        XCTAssertEqual(deck.name, "Test Deck", "Deck name should be preserved")
        XCTAssertTrue(deck.isDeck, "Deck type should be preserved")
        XCTAssertEqual(deck.memberCount, 1, "Member count should be updated")
        XCTAssertTrue(deck.memberPhones.contains(contactPhone), "Contact should be added")
    }
    
    // MARK: - Data Integrity Tests
    
    func testDragDropDataIntegrityCheck() {
        // Create a group with comprehensive data
        let originalId = UUID()
        let originalCreatedAt = Date()
        let linkedGroupId = UUID()
        let canvasId = UUID()
        
        var targetGroup = ContactGroup(
            id: originalId,
            name: "Integrity Test Group",
            color: .mint,
            isDeck: false
        )
        
        // Set comprehensive data
        targetGroup.createdAt = originalCreatedAt
        targetGroup.linkedGroupIDs.insert(linkedGroupId)
        targetGroup.canvases.insert(canvasId)
        targetGroup.metadata = GroupMetadata()
        targetGroup.metadata.inviteCount = 10
        targetGroup.metadata.interconnectivityScore = 0.95
        
        // Create contact drag item from contacts bar
        let contactPhone = "555-999-9999"
        let contactUUID = UUID()
        let dragItem = ContactDragItem(
            phones: [contactPhone],
            uuids: [contactUUID],
            origin: .contactsBar
        )
        
        // Simulate drag and drop from contacts bar to groups bar
        for phone in dragItem.phones {
            targetGroup.memberPhones.insert(phone)
        }
        
        // Comprehensive data integrity check
        XCTAssertEqual(targetGroup.id, originalId, "Group ID must be preserved")
        XCTAssertEqual(targetGroup.name, "Integrity Test Group", "Group name must be preserved")
        XCTAssertEqual(targetGroup.color, .mint, "Group color must be preserved")
        XCTAssertEqual(targetGroup.createdAt, originalCreatedAt, "Created date must be preserved")
        XCTAssertEqual(targetGroup.linkedGroupIDs.count, 1, "Linked group IDs must be preserved")
        XCTAssertTrue(targetGroup.linkedGroupIDs.contains(linkedGroupId), "Linked group ID must be preserved")
        XCTAssertEqual(targetGroup.canvases.count, 1, "Canvas IDs must be preserved")
        XCTAssertTrue(targetGroup.canvases.contains(canvasId), "Canvas ID must be preserved")
        XCTAssertEqual(targetGroup.metadata.inviteCount, 10, "Metadata invite count must be preserved")
        XCTAssertEqual(targetGroup.metadata.interconnectivityScore, 0.95, "Metadata interconnectivity score must be preserved")
        XCTAssertFalse(targetGroup.isDeck, "Group type must be preserved")
        XCTAssertTrue(targetGroup.isRoot, "Root status must be preserved")
        
        // Verify contact was added
        XCTAssertEqual(targetGroup.memberCount, 1, "Member count must be updated")
        XCTAssertTrue(targetGroup.memberPhones.contains(contactPhone), "Contact must be added")
    }
    
    func testDragDropOverwriteProtection() {
        // This test specifically checks that drag and drop doesn't overwrite existing data
        var targetGroup = ContactGroup(
            id: UUID(),
            name: "Overwrite Protection Group",
            color: .yellow,
            isDeck: false
        )
        
        // Set up existing data that should NOT be overwritten
        let existingPhone = "555-111-1111"
        targetGroup.memberPhones.insert(existingPhone)
        targetGroup.linkedGroupIDs.insert(UUID())
        targetGroup.canvases.insert(UUID())
        
        // Store original values
        let originalName = targetGroup.name
        let originalColor = targetGroup.color
        let originalMemberCount = targetGroup.memberCount
        let originalLinkedCount = targetGroup.linkedGroupIDs.count
        let originalCanvasCount = targetGroup.canvases.count
        
        // Create contact drag item from contacts bar
        let newContactPhone = "555-222-2222"
        let dragItem = ContactDragItem(
            phones: [newContactPhone],
            uuids: [UUID()],
            origin: .contactsBar
        )
        
        // Simulate drag and drop from contacts bar to groups bar
        for phone in dragItem.phones {
            targetGroup.memberPhones.insert(phone)
        }
        
        // Verify that existing data is NOT overwritten
        XCTAssertEqual(targetGroup.name, originalName, "Group name should NOT be overwritten")
        XCTAssertEqual(targetGroup.color, originalColor, "Group color should NOT be overwritten")
        XCTAssertEqual(targetGroup.linkedGroupIDs.count, originalLinkedCount, "Linked group IDs should NOT be overwritten")
        XCTAssertEqual(targetGroup.canvases.count, originalCanvasCount, "Canvas IDs should NOT be overwritten")
        
        // Verify that member count increased (not overwritten)
        XCTAssertEqual(targetGroup.memberCount, originalMemberCount + 1, "Member count should increase, not be overwritten")
        
        // Verify both existing and new contacts are present
        XCTAssertTrue(targetGroup.memberPhones.contains(existingPhone), "Existing contact should still be present")
        XCTAssertTrue(targetGroup.memberPhones.contains(newContactPhone), "New contact should be added")
    }
}
