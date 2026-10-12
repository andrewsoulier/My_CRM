import XCTest
@testable import My_CRM

class SimpleXCTests: XCTestCase {
    
    func testContactCreation() {
        let contact = Contact(
            phone: "555-123-4567",
            name: "John Doe",
            firstName: "John",
            lastName: "Doe",
            email: "john@example.com",
            address: "123 Main St",
            notes: "Test contact",
            business: "Test Company"
        )
        
        XCTAssertEqual(contact.phone, "555-123-4567")
        XCTAssertEqual(contact.name, "John Doe")
        XCTAssertEqual(contact.firstName, "John")
        XCTAssertEqual(contact.lastName, "Doe")
    }
    
    func testGroupCreation() {
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
    }
    
    func testDeckCreation() {
        let deck = ContactGroup(
            id: UUID(),
            name: "Test Deck",
            color: .cyan,
            isDeck: true
        )
        
        XCTAssertEqual(deck.name, "Test Deck")
        XCTAssertTrue(deck.isDeck)
        XCTAssertEqual(deck.memberCount, 0)
    }
    
    func testContactDragItemCreation() {
        let phones = ["555-123-4567", "555-987-6543"]
        let origin = DragOrigin.contactsBar
        let dragItem = ContactDragItem(phones: phones, uuids: [], origin: origin)
        
        XCTAssertEqual(dragItem.phones, phones)
        XCTAssertEqual(dragItem.origin, origin)
    }
    
    func testGroupDragItemCreation() {
        let phones = ["555-123-4567"]
        let groupId = UUID()
        let origin = DragOrigin.group(id: groupId)
        let dragItem = ContactDragItem(phones: phones, uuids: [], origin: origin)
        
        XCTAssertEqual(dragItem.phones, phones)
        XCTAssertEqual(dragItem.origin, origin)
    }
}
