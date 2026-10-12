import XCTest
import SwiftUI
@testable import My_CRM

class DragDropGroupTests: XCTestCase {
    
    // MARK: - Contact Drag Item Tests
    
    func testContactDragItemCreation() {
        let phones = ["555-123-4567", "555-987-6543"]
        let uuids = [UUID(), UUID()]
        let origin = DragOrigin.contactsBar
        let dragItem = ContactDragItem(phones: phones, uuids: uuids, origin: origin)
        
        XCTAssertEqual(dragItem.phones, phones)
        XCTAssertEqual(dragItem.uuids, uuids)
        XCTAssertEqual(dragItem.origin, origin)
    }
    
    func testContactDragItemFromContactsBar() {
        let phones = ["555-123-4567"]
        let uuids = [UUID()]
        let origin = DragOrigin.contactsBar
        let dragItem = ContactDragItem(phones: phones, uuids: uuids, origin: origin)
        
        XCTAssertEqual(dragItem.origin, DragOrigin.contactsBar)
        XCTAssertEqual(dragItem.phones.count, 1)
        XCTAssertEqual(dragItem.uuids.count, 1)
    }
    
    func testContactDragItemFromGroup() {
        let groupId = UUID()
        let phones = ["555-123-4567"]
        let uuids = [UUID()]
        let origin = DragOrigin.group(id: groupId)
        let dragItem = ContactDragItem(phones: phones, uuids: uuids, origin: origin)
        
        XCTAssertEqual(dragItem.origin, DragOrigin.group(id: groupId))
        XCTAssertEqual(dragItem.phones.count, 1)
        XCTAssertEqual(dragItem.uuids.count, 1)
    }
    
    func testContactDragItemFromDeck() {
        let deckId = UUID()
        let phones = ["555-123-4567"]
        let uuids = [UUID()]
        let origin = DragOrigin.deck(id: deckId)
        let dragItem = ContactDragItem(phones: phones, uuids: uuids, origin: origin)
        
        XCTAssertEqual(dragItem.origin, DragOrigin.deck(id: deckId))
        XCTAssertEqual(dragItem.phones.count, 1)
        XCTAssertEqual(dragItem.uuids.count, 1)
    }
    
    // MARK: - Group Drag Item Tests
    
    func testGroupDragItemCreation() {
        let groupId = UUID()
        let origin = DragOrigin.group(id: groupId)
        let dragItem = ContactDragItem(phones: [], uuids: [], origin: origin)
        
        XCTAssertEqual(dragItem.phones.count, 0)
        XCTAssertEqual(dragItem.uuids.count, 0)
        XCTAssertEqual(dragItem.origin, origin)
    }
    
    // MARK: - Drag Origin Tests
    
    func testDragOriginContactsBar() {
        let origin = DragOrigin.contactsBar
        XCTAssertEqual(origin, DragOrigin.contactsBar)
    }
    
    func testDragOriginGroup() {
        let groupId = UUID()
        let origin = DragOrigin.group(id: groupId)
        XCTAssertEqual(origin, DragOrigin.group(id: groupId))
    }
    
    func testDragOriginDeck() {
        let deckId = UUID()
        let origin = DragOrigin.deck(id: deckId)
        XCTAssertEqual(origin, DragOrigin.deck(id: deckId))
    }
    
    // MARK: - Drag and Drop Simulation Tests
    
    func testDragContactFromContactsBarToGroup() {
        // Create a group
        var group = ContactGroup(
            id: UUID(),
            name: "Target Group",
            color: .blue,
            isDeck: false
        )
        
        // Create drag item from contacts bar
        let contactPhone = "555-123-4567"
        let contactUUID = UUID()
        let dragItem = ContactDragItem(
            phones: [contactPhone],
            uuids: [contactUUID],
            origin: .contactsBar
        )
        
        // Simulate drop onto group
        for phone in dragItem.phones {
            group.memberPhones.insert(phone)
        }
        
        XCTAssertEqual(group.memberCount, 1)
        XCTAssertTrue(group.memberPhones.contains(contactPhone))
    }
    
    func testDragMultipleContactsFromContactsBarToGroup() {
        // Create a group
        var group = ContactGroup(
            id: UUID(),
            name: "Target Group",
            color: .blue,
            isDeck: false
        )
        
        // Create drag item with multiple contacts
        let contactPhones = ["555-123-4567", "555-987-6543", "555-555-5555"]
        let contactUUIDs = [UUID(), UUID(), UUID()]
        let dragItem = ContactDragItem(
            phones: contactPhones,
            uuids: contactUUIDs,
            origin: .contactsBar
        )
        
        // Simulate drop onto group
        for phone in dragItem.phones {
            group.memberPhones.insert(phone)
        }
        
        XCTAssertEqual(group.memberCount, 3)
        for phone in contactPhones {
            XCTAssertTrue(group.memberPhones.contains(phone))
        }
    }
    
    func testDragContactFromGroupToGroup() {
        // Create source group
        var sourceGroup = ContactGroup(
            id: UUID(),
            name: "Source Group",
            color: .blue,
            isDeck: false
        )
        
        // Create target group
        var targetGroup = ContactGroup(
            id: UUID(),
            name: "Target Group",
            color: .green,
            isDeck: false
        )
        
        let contactPhone = "555-123-4567"
        
        // Add contact to source group
        sourceGroup.memberPhones.insert(contactPhone)
        XCTAssertEqual(sourceGroup.memberCount, 1)
        
        // Create drag item from source group
        let dragItem = ContactDragItem(
            phones: [contactPhone],
            uuids: [UUID()],
            origin: .group(id: sourceGroup.id)
        )
        
        // Simulate drop onto target group
        for phone in dragItem.phones {
            targetGroup.memberPhones.insert(phone)
        }
        
        // Remove from source group (simulate move operation)
        sourceGroup.memberPhones.remove(contactPhone)
        
        XCTAssertEqual(sourceGroup.memberCount, 0)
        XCTAssertEqual(targetGroup.memberCount, 1)
        XCTAssertTrue(targetGroup.memberPhones.contains(contactPhone))
    }
    
    func testDragContactFromDeckToGroup() {
        // Create a group
        var group = ContactGroup(
            id: UUID(),
            name: "Target Group",
            color: .blue,
            isDeck: false
        )
        
        // Create drag item from deck
        let contactPhone = "555-123-4567"
        let deckId = UUID()
        let dragItem = ContactDragItem(
            phones: [contactPhone],
            uuids: [UUID()],
            origin: .deck(id: deckId)
        )
        
        // Simulate drop onto group
        for phone in dragItem.phones {
            group.memberPhones.insert(phone)
        }
        
        XCTAssertEqual(group.memberCount, 1)
        XCTAssertTrue(group.memberPhones.contains(contactPhone))
    }
    
    // MARK: - Drag and Drop Validation Tests
    
    func testPreventDuplicateContactInGroup() {
        // Create a group
        var group = ContactGroup(
            id: UUID(),
            name: "Test Group",
            color: .blue,
            isDeck: false
        )
        
        let contactPhone = "555-123-4567"
        
        // Add contact first time
        group.memberPhones.insert(contactPhone)
        XCTAssertEqual(group.memberCount, 1)
        
        // Try to add same contact again (simulate drag and drop)
        let dragItem = ContactDragItem(
            phones: [contactPhone],
            uuids: [UUID()],
            origin: .contactsBar
        )
        
        for phone in dragItem.phones {
            group.memberPhones.insert(phone) // Set automatically prevents duplicates
        }
        
        XCTAssertEqual(group.memberCount, 1) // Should still be 1
        XCTAssertTrue(group.memberPhones.contains(contactPhone))
    }
    
    func testDragToEmptyGroup() {
        // Create an empty group
        var group = ContactGroup(
            id: UUID(),
            name: "Empty Group",
            color: .blue,
            isDeck: false
        )
        
        XCTAssertEqual(group.memberCount, 0)
        
        // Drag contact to empty group
        let contactPhone = "555-123-4567"
        let dragItem = ContactDragItem(
            phones: [contactPhone],
            uuids: [UUID()],
            origin: .contactsBar
        )
        
        for phone in dragItem.phones {
            group.memberPhones.insert(phone)
        }
        
        XCTAssertEqual(group.memberCount, 1)
        XCTAssertTrue(group.memberPhones.contains(contactPhone))
    }
    
    func testDragToGroupWithExistingMembers() {
        // Create a group with existing members
        var group = ContactGroup(
            id: UUID(),
            name: "Existing Group",
            color: .blue,
            isDeck: false
        )
        
        // Add existing contact
        let existingPhone = "555-111-1111"
        group.memberPhones.insert(existingPhone)
        XCTAssertEqual(group.memberCount, 1)
        
        // Drag new contact to group
        let newPhone = "555-222-2222"
        let dragItem = ContactDragItem(
            phones: [newPhone],
            uuids: [UUID()],
            origin: .contactsBar
        )
        
        for phone in dragItem.phones {
            group.memberPhones.insert(phone)
        }
        
        XCTAssertEqual(group.memberCount, 2)
        XCTAssertTrue(group.memberPhones.contains(existingPhone))
        XCTAssertTrue(group.memberPhones.contains(newPhone))
    }
    
    // MARK: - Edge Cases
    
    func testDragEmptyContactList() {
        // Create a group
        var group = ContactGroup(
            id: UUID(),
            name: "Test Group",
            color: .blue,
            isDeck: false
        )
        
        // Create drag item with no contacts
        let dragItem = ContactDragItem(
            phones: [],
            uuids: [],
            origin: .contactsBar
        )
        
        // Simulate drop (should not change group)
        for phone in dragItem.phones {
            group.memberPhones.insert(phone)
        }
        
        XCTAssertEqual(group.memberCount, 0)
    }
    
    func testDragWithMismatchedPhonesAndUUIDs() {
        // Create a group
        var group = ContactGroup(
            id: UUID(),
            name: "Test Group",
            color: .blue,
            isDeck: false
        )
        
        // Create drag item with mismatched arrays
        let dragItem = ContactDragItem(
            phones: ["555-123-4567", "555-987-6543"],
            uuids: [UUID()], // Only one UUID for two phones
            origin: .contactsBar
        )
        
        // Simulate drop
        for phone in dragItem.phones {
            group.memberPhones.insert(phone)
        }
        
        XCTAssertEqual(group.memberCount, 2)
        XCTAssertTrue(group.memberPhones.contains("555-123-4567"))
        XCTAssertTrue(group.memberPhones.contains("555-987-6543"))
    }
    
    func testDragToDeck() {
        // Create a deck
        var deck = ContactGroup(
            id: UUID(),
            name: "Test Deck",
            color: .cyan,
            isDeck: true
        )
        
        // Drag contact to deck
        let contactPhone = "555-123-4567"
        let dragItem = ContactDragItem(
            phones: [contactPhone],
            uuids: [UUID()],
            origin: .contactsBar
        )
        
        for phone in dragItem.phones {
            deck.memberPhones.insert(phone)
        }
        
        XCTAssertTrue(deck.isDeck)
        XCTAssertEqual(deck.memberCount, 1)
        XCTAssertTrue(deck.memberPhones.contains(contactPhone))
    }
}
