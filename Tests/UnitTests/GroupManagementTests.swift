import XCTest
import SwiftUI
@testable import My_CRM

class GroupManagementTests: XCTestCase {
    
    // MARK: - Group Creation Tests
    
    func testGroupCreationWithBasicProperties() {
        let group = ContactGroup(
            id: UUID(),
            name: "Test Group",
            color: .blue,
            isDeck: false
        )
        
        XCTAssertEqual(group.name, "Test Group")
        XCTAssertFalse(group.isDeck)
        XCTAssertEqual(group.memberCount, 0)
        XCTAssertTrue(group.isRoot)
        XCTAssertFalse(group.hasChildren)
    }
    
    func testGroupCreationWithSpecificID() {
        let groupId = UUID()
        let group = ContactGroup(
            id: groupId,
            name: "Specific ID Group",
            color: .green,
            isDeck: false
        )
        
        XCTAssertEqual(group.id, groupId)
        XCTAssertEqual(group.name, "Specific ID Group")
        XCTAssertNotNil(group.id)
    }
    
    func testGroupCreationThroughCanvasView() {
        // Simulate group creation through canvas view
        let group = ContactGroup(
            id: UUID(),
            name: "Canvas Group",
            color: .red,
            isDeck: false
        )
        
        XCTAssertEqual(group.name, "Canvas Group")
        XCTAssertFalse(group.isDeck)
        XCTAssertEqual(group.memberCount, 0)
    }
    
    func testGroupCreationThroughGroupsToolbar() {
        // Simulate group creation through groups toolbar
        let group = ContactGroup(
            id: UUID(),
            name: "Toolbar Group",
            color: .orange,
            isDeck: false
        )
        
        XCTAssertEqual(group.name, "Toolbar Group")
        XCTAssertFalse(group.isDeck)
        XCTAssertEqual(group.memberCount, 0)
    }
    
    func testGroupCreationWithDifferentColors() {
        let colors: [Color] = [.blue, .green, .red, .orange, .purple, .cyan, .mint]
        
        for (index, color) in colors.enumerated() {
            let group = ContactGroup(
                id: UUID(),
                name: "Color Group \(index)",
                color: color,
                isDeck: false
            )
            
            XCTAssertEqual(group.color, color)
            XCTAssertEqual(group.name, "Color Group \(index)")
        }
    }
    
    func testGroupCreationWithParentChildRelationship() {
        let parentGroup = ContactGroup(
            id: UUID(),
            name: "Parent Group",
            color: .blue,
            isDeck: false
        )
        
        let childGroup = ContactGroup(
            id: UUID(),
            name: "Child Group",
            color: .green,
            parentID: parentGroup.id,
            isDeck: false
        )
        
        XCTAssertTrue(parentGroup.isRoot)
        XCTAssertFalse(childGroup.isRoot)
        XCTAssertEqual(childGroup.parentID, parentGroup.id)
    }
    
    // MARK: - Group Validation Tests
    
    func testGroupNameValidation() {
        // Test valid group names
        let validNames = ["Valid Group", "Group 123", "My-Group", "Group_Name"]
        
        for name in validNames {
            let group = ContactGroup(
                id: UUID(),
                name: name,
                color: .blue,
                isDeck: false
            )
            XCTAssertEqual(group.name, name)
        }
    }
    
    func testGroupNameWithSpecialCharacters() {
        let group = ContactGroup(
            id: UUID(),
            name: "Group with Special Chars: @#$%",
            color: .blue,
            isDeck: false
        )
        
        XCTAssertEqual(group.name, "Group with Special Chars: @#$%")
    }
    
    func testGroupNameWithEmptyString() {
        let group = ContactGroup(
            id: UUID(),
            name: "",
            color: .blue,
            isDeck: false
        )
        
        XCTAssertTrue(group.name.isEmpty)
    }
    
    // MARK: - Group Member Management Tests
    
    func testAddSingleContactToGroup() {
        var group = ContactGroup(
            id: UUID(),
            name: "Test Group",
            color: .blue,
            isDeck: false
        )
        
        let contactPhone = "555-123-4567"
        group.memberPhones.insert(contactPhone)
        
        XCTAssertEqual(group.memberCount, 1)
        XCTAssertTrue(group.memberPhones.contains(contactPhone))
    }
    
    func testAddMultipleContactsToGroup() {
        var group = ContactGroup(
            id: UUID(),
            name: "Test Group",
            color: .blue,
            isDeck: false
        )
        
        let contactPhones = ["555-123-4567", "555-987-6543", "555-555-5555"]
        
        for phone in contactPhones {
            group.memberPhones.insert(phone)
        }
        
        XCTAssertEqual(group.memberCount, 3)
        for phone in contactPhones {
            XCTAssertTrue(group.memberPhones.contains(phone))
        }
    }
    
    func testAddContactFromContactsBarDragDrop() {
        var group = ContactGroup(
            id: UUID(),
            name: "Test Group",
            color: .blue,
            isDeck: false
        )
        
        let contactPhone = "555-123-4567"
        
        // Simulate drag and drop from contacts bar
        group.memberPhones.insert(contactPhone)
        
        XCTAssertEqual(group.memberCount, 1)
        XCTAssertTrue(group.memberPhones.contains(contactPhone))
    }
    
    func testAddContactFromCanvasGroupDragDrop() {
        var group = ContactGroup(
            id: UUID(),
            name: "Canvas Group",
            color: .blue,
            isDeck: false
        )
        
        let contactPhone = "555-123-4567"
        
        // Simulate drag and drop onto canvas group
        group.memberPhones.insert(contactPhone)
        
        XCTAssertEqual(group.memberCount, 1)
        XCTAssertTrue(group.memberPhones.contains(contactPhone))
    }
    
    func testAddContactFromGroupDetailsPage() {
        var group = ContactGroup(
            id: UUID(),
            name: "Details Group",
            color: .blue,
            isDeck: false
        )
        
        let contactPhone = "555-123-4567"
        
        // Simulate adding contact from group details page
        group.memberPhones.insert(contactPhone)
        
        XCTAssertEqual(group.memberCount, 1)
        XCTAssertTrue(group.memberPhones.contains(contactPhone))
    }
    
    func testAddMultipleContactsFromContactsBar() {
        var group = ContactGroup(
            id: UUID(),
            name: "Multi Contact Group",
            color: .blue,
            isDeck: false
        )
        
        let contactPhones = ["555-123-4567", "555-987-6543", "555-555-5555"]
        
        // Simulate adding multiple contacts from contacts bar
        for phone in contactPhones {
            group.memberPhones.insert(phone)
        }
        
        XCTAssertEqual(group.memberCount, 3)
        for phone in contactPhones {
            XCTAssertTrue(group.memberPhones.contains(phone))
        }
    }
    
    func testPreventDuplicateContactAddition() {
        var group = ContactGroup(
            id: UUID(),
            name: "Duplicate Test Group",
            color: .blue,
            isDeck: false
        )
        
        let contactPhone = "555-123-4567"
        
        // Add contact first time
        group.memberPhones.insert(contactPhone)
        XCTAssertEqual(group.memberCount, 1)
        
        // Try to add same contact again
        group.memberPhones.insert(contactPhone)
        XCTAssertEqual(group.memberCount, 1) // Should still be 1
        XCTAssertTrue(group.memberPhones.contains(contactPhone))
    }
    
    func testRemoveContactFromGroup() {
        var group = ContactGroup(
            id: UUID(),
            name: "Remove Test Group",
            color: .blue,
            isDeck: false
        )
        
        let contactPhone = "555-123-4567"
        
        // Add contact
        group.memberPhones.insert(contactPhone)
        XCTAssertEqual(group.memberCount, 1)
        
        // Remove contact
        group.memberPhones.remove(contactPhone)
        XCTAssertEqual(group.memberCount, 0)
        XCTAssertFalse(group.memberPhones.contains(contactPhone))
    }
    
    func testRemoveMultipleContactsFromGroup() {
        var group = ContactGroup(
            id: UUID(),
            name: "Multi Remove Group",
            color: .blue,
            isDeck: false
        )
        
        let contactPhones = ["555-123-4567", "555-987-6543", "555-555-5555"]
        
        // Add contacts
        for phone in contactPhones {
            group.memberPhones.insert(phone)
        }
        XCTAssertEqual(group.memberCount, 3)
        
        // Remove all contacts
        for phone in contactPhones {
            group.memberPhones.remove(phone)
        }
        XCTAssertEqual(group.memberCount, 0)
    }
    
    // MARK: - Group vs Deck Tests
    
    func testGroupVsDeckDistinction() {
        let group = ContactGroup(
            id: UUID(),
            name: "Regular Group",
            color: .blue,
            isDeck: false
        )
        
        let deck = ContactGroup(
            id: UUID(),
            name: "Deck Group",
            color: .cyan,
            isDeck: true
        )
        
        XCTAssertFalse(group.isDeck)
        XCTAssertTrue(deck.isDeck)
        XCTAssertEqual(group.name, "Regular Group")
        XCTAssertEqual(deck.name, "Deck Group")
    }
    
    func testDeckCreation() {
        let deck = ContactGroup(
            id: UUID(),
            name: "Test Deck",
            color: .cyan,
            isDeck: true
        )
        
        XCTAssertTrue(deck.isDeck)
        XCTAssertEqual(deck.name, "Test Deck")
        XCTAssertEqual(deck.memberCount, 0)
    }
    
    // MARK: - Group Properties Tests
    
    func testGroupMemberCount() {
        var group = ContactGroup(
            id: UUID(),
            name: "Count Test Group",
            color: .blue,
            isDeck: false
        )
        
        XCTAssertEqual(group.memberCount, 0)
        
        // Add contacts and verify count
        let contactPhones = ["555-123-4567", "555-987-6543", "555-555-5555"]
        for phone in contactPhones {
            group.memberPhones.insert(phone)
        }
        
        XCTAssertEqual(group.memberCount, 3)
    }
    
    func testGroupIsRoot() {
        let rootGroup = ContactGroup(
            id: UUID(),
            name: "Root Group",
            color: .blue,
            isDeck: false
        )
        
        let childGroup = ContactGroup(
            id: UUID(),
            name: "Child Group",
            color: .green,
            parentID: rootGroup.id,
            isDeck: false
        )
        
        XCTAssertTrue(rootGroup.isRoot)
        XCTAssertFalse(childGroup.isRoot)
    }
    
    func testGroupHasChildren() {
        let parentGroup = ContactGroup(
            id: UUID(),
            name: "Parent Group",
            color: .blue,
            isDeck: false
        )
        
        let childGroup = ContactGroup(
            id: UUID(),
            name: "Child Group",
            color: .green,
            parentID: parentGroup.id,
            isDeck: false
        )
        
        // Add child to parent's linked groups
        var parent = parentGroup
        parent.linkedGroupIDs.insert(childGroup.id)
        
        XCTAssertTrue(parent.hasChildren)
        XCTAssertFalse(childGroup.hasChildren)
    }
    
    // MARK: - Edge Cases and Error Handling
    
    func testGroupWithMaximumMembers() {
        var group = ContactGroup(
            id: UUID(),
            name: "Large Group",
            color: .blue,
            isDeck: false
        )
        
        // Add many contacts
        for i in 0..<100 {
            let phone = "555-\(String(format: "%03d", i))-\(String(format: "%04d", i))"
            group.memberPhones.insert(phone)
        }
        
        XCTAssertEqual(group.memberCount, 100)
    }
    
    func testGroupWithSpecialCharactersInName() {
        let specialNames = [
            "Group with Spaces",
            "Group-with-dashes",
            "Group_with_underscores",
            "Group.with.dots",
            "Group@with#symbols",
            "Group with émojis 🎉"
        ]
        
        for name in specialNames {
            let group = ContactGroup(
                id: UUID(),
                name: name,
                color: .blue,
                isDeck: false
            )
            XCTAssertEqual(group.name, name)
        }
    }
    
    func testGroupWithEmptyMembers() {
        let group = ContactGroup(
            id: UUID(),
            name: "Empty Group",
            color: .blue,
            isDeck: false
        )
        
        XCTAssertEqual(group.memberCount, 0)
        XCTAssertTrue(group.memberPhones.isEmpty)
    }
    
    func testGroupUpdate() {
        var group = ContactGroup(
            id: UUID(),
            name: "Original Name",
            color: .blue,
            isDeck: false
        )
        
        // Update group properties
        group.name = "Updated Name"
        group.color = .green
        
        XCTAssertEqual(group.name, "Updated Name")
        XCTAssertEqual(group.color, .green)
    }
}