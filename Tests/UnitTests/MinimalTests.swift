import Quick
import Nimble
import Foundation
@testable import My_CRM

class MinimalTests: QuickSpec {
    override func spec() {
        
        describe("Basic Models") {
            it("should create contact with correct properties") {
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
                
                expect(contact.phone).to(equal("555-123-4567"))
                expect(contact.name).to(equal("John Doe"))
                expect(contact.firstName).to(equal("John"))
                expect(contact.lastName).to(equal("Doe"))
            }
            
            it("should create group with correct properties") {
                let group = ContactGroup(
                    id: UUID(),
                    name: "Test Group",
                    color: .blue,
                    isDeck: false
                )
                
                expect(group.name).to(equal("Test Group"))
                expect(group.isDeck).to(beFalse())
                expect(group.memberCount).to(equal(0))
                expect(group.isRoot).to(beTrue())
            }
            
            it("should create deck with correct properties") {
                let deck = ContactGroup(
                    id: UUID(),
                    name: "Test Deck",
                    color: .cyan,
                    isDeck: true
                )
                
                expect(deck.name).to(equal("Test Deck"))
                expect(deck.isDeck).to(beTrue())
                expect(deck.memberCount).to(equal(0))
            }
        }
        
        describe("Drag and Drop Models") {
            it("should create contact drag item") {
                let phones = ["555-123-4567", "555-987-6543"]
                let origin = DragOrigin.contactsBar
                let dragItem = ContactDragItem(phones: phones, uuids: [], origin: origin)
                
                expect(dragItem.phones).to(equal(phones))
                expect(dragItem.origin).to(equal(origin))
            }
            
            it("should create group drag item") {
                let phones = ["555-123-4567"]
                let groupId = UUID()
                let origin = DragOrigin.group(id: groupId)
                let dragItem = ContactDragItem(phones: phones, uuids: [], origin: origin)
                
                expect(dragItem.phones).to(equal(phones))
                expect(dragItem.origin).to(equal(origin))
            }
        }
    }
}
