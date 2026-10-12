import Quick
import Nimble
import Foundation
@testable import My_CRM

class BasicTests: QuickSpec {
    override func spec() {
        
        describe("Test Data") {
            it("should create test contacts") {
                let contacts = TestData.testContacts
                
                expect(contacts).toNot(beEmpty())
                expect(contacts.count).to(equal(5))
                expect(contacts[0].name).to(equal("Test1"))
                expect(contacts[0].phone).to(equal("101-101-0001"))
            }
            
            it("should create test groups") {
                let groups = TestData.testGroups
                
                expect(groups).toNot(beEmpty())
                expect(groups.count).to(equal(5))
                expect(groups[0].name).to(equal("TestGroup1"))
                expect(groups[0].isDeck).to(beFalse())
            }
        }
        
        describe("Contact Model") {
            it("should create contact with correct properties") {
                let contact = TestData.createTestContact(phone: "555-123-4567", name: "John Doe")
                
                expect(contact.phone).to(equal("555-123-4567"))
                expect(contact.name).to(equal("John Doe"))
                expect(contact.firstName).to(equal("John Doe"))
                expect(contact.lastName).to(equal("Test"))
            }
        }
        
        describe("Group Model") {
            it("should create group with correct properties") {
                let group = TestData.createTestGroup(name: "Test Group")
                
                expect(group.name).to(equal("Test Group"))
                expect(group.isDeck).to(beFalse())
                expect(group.memberCount).to(equal(0))
                expect(group.isRoot).to(beTrue())
            }
        }
    }
}
