import Quick
import Nimble
import Foundation
@testable import My_CRM

class SimpleTests: QuickSpec {
    override func spec() {
        
        describe("Basic Functionality") {
            context("when testing basic operations") {
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
                
                it("should create test decks") {
                    let decks = TestData.testDecks
                    
                    expect(decks).toNot(beEmpty())
                    expect(decks.count).to(equal(2))
                    expect(decks[0].name).to(equal("TestDeck1"))
                    expect(decks[0].isDeck).to(beTrue())
                }
            }
        }
        
        describe("Contact Model") {
            context("when working with Contact model") {
                it("should create contact with correct properties") {
                    let contact = TestData.createTestContact(phone: "555-123-4567", name: "John Doe")
                    
                    expect(contact.phone).to(equal("555-123-4567"))
                    expect(contact.name).to(equal("John Doe"))
                    expect(contact.firstName).to(equal("John Doe"))
                    expect(contact.lastName).to(equal("Test"))
                }
            }
        }
        
        describe("Group Model") {
            context("when working with Group model") {
                it("should create group with correct properties") {
                    let group = TestData.createTestGroup(name: "Test Group")
                    
                    expect(group.name).to(equal("Test Group"))
                    expect(group.isDeck).to(beFalse())
                    expect(group.memberCount).to(equal(0))
                    expect(group.isRoot).to(beTrue())
                }
                
                it("should create deck with correct properties") {
                    let deck = TestData.createTestDeck(name: "Test Deck")
                    
                    expect(deck.name).to(equal("Test Deck"))
                    expect(deck.isDeck).to(beTrue())
                    expect(deck.memberCount).to(equal(0))
                }
            }
        }
        
        describe("Drag and Drop Models") {
            context("when working with drag and drop models") {
                it("should create contact drag item") {
                    let phones = ["101-101-0001", "101-101-0002"]
                    let origin = DragOrigin.contactsBar
                    let dragItem = TestData.createTestDragItem(phones: phones, origin: origin)
                    
                    expect(dragItem.phones).to(equal(phones))
                    expect(dragItem.origin).to(equal(origin))
                }
                
                it("should create group drag item") {
                    let phones = ["101-101-0001"]
                    let groupId = TestData.testGroups[0].id
                    let origin = DragOrigin.group(id: groupId)
                    let dragItem = TestData.createTestDragItem(phones: phones, origin: origin)
                    
                    expect(dragItem.phones).to(equal(phones))
                    expect(dragItem.origin).to(equal(origin))
                }
            }
        }
        
        describe("Mock Data Provider") {
            context("when working with mock data provider") {
                it("should create mock data provider") {
                    let provider = TestData.createMockDataProvider()
                    
                    expect(provider).toNot(beNil())
                    expect(provider.contacts).toNot(beEmpty())
                    expect(provider.groups).toNot(beEmpty())
                }
                
                it("should have correct number of test contacts") {
                    let provider = TestData.createMockDataProvider()
                    
                    expect(provider.contacts.count).to(equal(5))
                    expect(provider.groups.count).to(equal(7)) // 5 groups + 2 decks
                }
            }
        }
    }
}
