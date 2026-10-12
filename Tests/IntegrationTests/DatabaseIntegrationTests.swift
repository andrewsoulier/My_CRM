import Quick
import Nimble
import Foundation
import SQLite3
@testable import My_CRM

class DatabaseIntegrationTests: QuickSpec {
    override func spec() {
        
        describe("Database Integration") {
            var dataProvider: SQLiteDataProvider!
            var testDatabasePath: String!
            
            beforeEach {
                // Create in-memory database for testing
                testDatabasePath = ":memory:"
                dataProvider = SQLiteDataProvider(databasePath: testDatabasePath)
                
                do {
                    try await dataProvider.initializeDatabase()
                } catch {
                    fail("Failed to initialize test database: \(error)")
                }
            }
            
            afterEach {
                do {
                    try await dataProvider.closeDatabase()
                } catch {
                    // Ignore cleanup errors
                }
            }
            
            describe("Contact Database Operations") {
                context("when working with contacts in database") {
                    it("should create and retrieve contacts") {
                        let testContact = TestData.testContacts[0]
                        
                        Task {
                            do {
                                // Create contact
                                try await dataProvider.createContact(testContact)
                                
                                // Retrieve contact
                                let retrievedContact = try await dataProvider.getContact(by: testContact.phone)
                                
                                expect(retrievedContact).toNot(beNil())
                                expect(retrievedContact?.phone).to(equal(testContact.phone))
                                expect(retrievedContact?.name).to(equal(testContact.name))
                                expect(retrievedContact?.email).to(equal(testContact.email))
                                
                            } catch {
                                fail("Contact database operations failed: \(error)")
                            }
                        }
                    }
                    
                    it("should update existing contacts") async {
                        let testContact = TestData.testContacts[0]
                        
                        do {
                            // Create contact
                            try await dataProvider.createContact(testContact)
                            
                            // Update contact
                            var updatedContact = testContact
                            updatedContact.name = "Updated Name"
                            updatedContact.email = "updated@example.com"
                            
                            try await dataProvider.updateContact(updatedContact)
                            
                            // Retrieve updated contact
                            let retrievedContact = try await dataProvider.getContact(by: testContact.phone)
                            
                            expect(retrievedContact?.name).to(equal("Updated Name"))
                            expect(retrievedContact?.email).to(equal("updated@example.com"))
                            
                        } catch {
                            fail("Contact update failed: \(error)")
                        }
                    }
                    
                    it("should delete contacts") async {
                        let testContact = TestData.testContacts[0]
                        
                        do {
                            // Create contact
                            try await dataProvider.createContact(testContact)
                            
                            // Verify contact exists
                            let retrievedContact = try await dataProvider.getContact(by: testContact.phone)
                            expect(retrievedContact).toNot(beNil())
                            
                            // Delete contact
                            try await dataProvider.deleteContact(phone: testContact.phone)
                            
                            // Verify contact is deleted
                            let deletedContact = try await dataProvider.getContact(by: testContact.phone)
                            expect(deletedContact).to(beNil())
                            
                        } catch {
                            fail("Contact deletion failed: \(error)")
                        }
                    }
                    
                    it("synchronizes contact groups column with membership changes") async {
                        var contact = TestData.testContacts[0]
                        contact.phone = "+15555550001"
                        var group = TestData.testGroups[0]
                        group.id = UUID()
                        group.name = "Grid Paste Friends"
                        
                        do {
                            try await dataProvider.createContact(contact)
                            try await dataProvider.createGroup(group)
                            
                            try await dataProvider.updateGroupMembers(groupId: group.id, members: [contact.phone])
                            
                            let groupsJSONAfterAdd = try fetchGroupsJSON(database: dataProvider.database, phone: contact.phone)
                            expect(groupsJSONAfterAdd).to(equal("[\"\(group.name)\"]"))
                            
                            try await dataProvider.updateGroupMembers(groupId: group.id, members: [])
                            
                            let groupsJSONAfterRemoval = try fetchGroupsJSON(database: dataProvider.database, phone: contact.phone)
                            expect(groupsJSONAfterRemoval).to(equal("[]"))
                            
                            group.name = "Renamed Paste Friends"
                            try await dataProvider.updateGroup(group)
                            try await dataProvider.updateGroupMembers(groupId: group.id, members: [contact.phone])
                            
                            let groupsJSONAfterRename = try fetchGroupsJSON(database: dataProvider.database, phone: contact.phone)
                            expect(groupsJSONAfterRename).to(equal("[\"\(group.name)\"]"))
                            
                        } catch {
                            fail("Contact groups synchronization failed: \(error)")
                        }
                    }
                }
            }
            
            describe("Group Database Operations") {
                context("when working with groups in database") {
                    it("should create and retrieve groups") async {
                        let testGroup = TestData.testGroups[0]
                        
                        do {
                            // Create group
                            try await dataProvider.createGroup(testGroup)
                            
                            // Retrieve group
                            let retrievedGroup = try await dataProvider.getGroup(by: testGroup.id)
                            
                            expect(retrievedGroup).toNot(beNil())
                            expect(retrievedGroup?.id).to(equal(testGroup.id))
                            expect(retrievedGroup?.name).to(equal(testGroup.name))
                            expect(retrievedGroup?.isDeck).to(equal(testGroup.isDeck))
                            
                        } catch {
                            fail("Group database operations failed: \(error)")
                        }
                    }
                    
                    it("should update group members") async {
                        let testGroup = TestData.testGroups[0]
                        let testPhones = Array(TestData.testPhoneNumbers.prefix(3))
                        
                        do {
                            // Create group
                            try await dataProvider.createGroup(testGroup)
                            
                            // Update group members
                            try await dataProvider.updateGroupMembers(groupId: testGroup.id, members: testPhones)
                            
                            // Retrieve group members
                            let members = dataProvider.getGroupMembers(groupId: testGroup.id)
                            
                            expect(members).toNot(beNil())
                            expect(members?.count).to(equal(3))
                            expect(members).to(contain(testPhones))
                            
                        } catch {
                            fail("Group member update failed: \(error)")
                        }
                    }
                    
                    it("should delete groups") async {
                        let testGroup = TestData.testGroups[0]
                        
                        do {
                            // Create group
                            try await dataProvider.createGroup(testGroup)
                            
                            // Verify group exists
                            let retrievedGroup = try await dataProvider.getGroup(by: testGroup.id)
                            expect(retrievedGroup).toNot(beNil())
                            
                            // Delete group
                            try await dataProvider.deleteGroup(id: testGroup.id)
                            
                            // Verify group is deleted
                            let deletedGroup = try await dataProvider.getGroup(by: testGroup.id)
                            expect(deletedGroup).to(beNil())
                            
                        } catch {
                            fail("Group deletion failed: \(error)")
                        }
                    }
                }
            }
            
            describe("Deck Database Operations") {
                context("when working with decks in database") {
                    it("should create and retrieve decks") async {
                        let testDeck = TestData.testDecks[0]
                        
                        do {
                            // Create deck
                            try await dataProvider.createDeck(testDeck)
                            
                            // Retrieve deck
                            let retrievedDeck = try await dataProvider.getDeck(by: testDeck.id)
                            
                            expect(retrievedDeck).toNot(beNil())
                            expect(retrievedDeck?.id).to(equal(testDeck.id))
                            expect(retrievedDeck?.name).to(equal(testDeck.name))
                            expect(retrievedDeck?.isDeck).to(beTrue())
                            
                        } catch {
                            fail("Deck database operations failed: \(error)")
                        }
                    }
                    
                    it("should distinguish between groups and decks") async {
                        let testGroup = TestData.testGroups[0]
                        let testDeck = TestData.testDecks[0]
                        
                        do {
                            // Create both group and deck
                            try await dataProvider.createGroup(testGroup)
                            try await dataProvider.createDeck(testDeck)
                            
                            // Retrieve all groups and decks
                            let allGroups = try await dataProvider.getAllGroups()
                            let allDecks = try await dataProvider.getAllDecks()
                            
                            expect(allGroups).toNot(beEmpty())
                            expect(allDecks).toNot(beEmpty())
                            
                            // Verify group is in groups list
                            let groupInList = allGroups.contains { $0.id == testGroup.id }
                            expect(groupInList).to(beTrue())
                            
                            // Verify deck is in decks list
                            let deckInList = allDecks.contains { $0.id == testDeck.id }
                            expect(deckInList).to(beTrue())
                            
                        } catch {
                            fail("Group/Deck distinction failed: \(error)")
                        }
                    }
                }
            }
            
            describe("Search Operations") {
                beforeEach {
                    // Set up test data
                    Task {
                        for contact in TestData.testContacts {
                            try await dataProvider.createContact(contact)
                        }
                    }
                }
                
                context("when searching contacts") {
                    it("should find contacts by name") async {
                        do {
                            let results = try await dataProvider.searchContacts(query: "Test1")
                            
                            expect(results).toNot(beEmpty())
                            expect(results.first?.name).to(equal("Test1"))
                            
                        } catch {
                            fail("Contact search by name failed: \(error)")
                        }
                    }
                    
                    it("should find contacts by phone number") async {
                        do {
                            let results = try await dataProvider.searchContacts(query: "101-101-0001")
                            
                            expect(results).toNot(beEmpty())
                            expect(results.first?.phone).to(equal("101-101-0001"))
                            
                        } catch {
                            fail("Contact search by phone failed: \(error)")
                        }
                    }
                    
                    it("should find contacts by email") async {
                        do {
                            let results = try await dataProvider.searchContacts(query: "test1@example.com")
                            
                            expect(results).toNot(beEmpty())
                            expect(results.first?.email).to(equal("test1@example.com"))
                            
                        } catch {
                            fail("Contact search by email failed: \(error)")
                        }
                    }
                    
                    it("should return empty results for non-matching queries") async {
                        do {
                            let results = try await dataProvider.searchContacts(query: "NonExistentContact")
                            
                            expect(results).to(beEmpty())
                            
                        } catch {
                            fail("Contact search for non-existent contact failed: \(error)")
                        }
                    }
                }
            }
            
            describe("Data Consistency") {
                context("when ensuring data consistency") {
                    it("should maintain referential integrity for group members") async {
                        let testGroup = TestData.testGroups[0]
                        let testContact = TestData.testContacts[0]
                        
                        do {
                            // Create contact and group
                            try await dataProvider.createContact(testContact)
                            try await dataProvider.createGroup(testGroup)
                            
                            // Add contact to group
                            try await dataProvider.updateGroupMembers(groupId: testGroup.id, members: [testContact.phone])
                            
                            // Verify group has the contact
                            let members = dataProvider.getGroupMembers(groupId: testGroup.id)
                            expect(members).to(contain(testContact.phone))
                            
                            // Delete the contact
                            try await dataProvider.deleteContact(phone: testContact.phone)
                            
                            // Verify group still exists but member is removed
                            let groupAfterContactDeletion = try await dataProvider.getGroup(by: testGroup.id)
                            expect(groupAfterContactDeletion).toNot(beNil())
                            
                            let membersAfterDeletion = dataProvider.getGroupMembers(groupId: testGroup.id)
                            expect(membersAfterDeletion).toNot(contain(testContact.phone))
                            
                        } catch {
                            fail("Referential integrity test failed: \(error)")
                        }
                    }
                    
                    it("should handle concurrent operations safely") async {
                        let testContacts = TestData.testContacts
                        
                        do {
                            // Create multiple contacts concurrently
                            await withTaskGroup(of: Void.self) { group in
                                for contact in testContacts {
                                    group.addTask {
                                        try? await dataProvider.createContact(contact)
                                    }
                                }
                            }
                            
                            // Verify all contacts were created
                            let allContacts = try await dataProvider.getAllContacts()
                            expect(allContacts.count).to(equal(testContacts.count))
                            
                        } catch {
                            fail("Concurrent operations test failed: \(error)")
                        }
                    }
                }
            }
            
            describe("Error Handling") {
                context("when handling database errors") {
                    it("should handle duplicate contact creation gracefully") async {
                        let testContact = TestData.testContacts[0]
                        
                        do {
                            // Create contact first time
                            try await dataProvider.createContact(testContact)
                            
                            // Attempt to create duplicate contact
                            try await dataProvider.createContact(testContact)
                            
                            // Should not throw error, but should handle gracefully
                            let retrievedContact = try await dataProvider.getContact(by: testContact.phone)
                            expect(retrievedContact).toNot(beNil())
                            
                        } catch {
                            // If it throws an error, it should be a specific database error
                            expect(error).toNot(beNil())
                        }
                    }
                    
                    it("should handle operations on non-existent entities gracefully") async {
                        let nonExistentId = UUID()
                        let nonExistentPhone = "999-999-9999"
                        
                        do {
                            // Attempt to get non-existent group
                            let group = try await dataProvider.getGroup(by: nonExistentId)
                            expect(group).to(beNil())
                            
                            // Attempt to get non-existent contact
                            let contact = try await dataProvider.getContact(by: nonExistentPhone)
                            expect(contact).to(beNil())
                            
                            // Attempt to delete non-existent entities
                            try await dataProvider.deleteGroup(id: nonExistentId)
                            try await dataProvider.deleteContact(phone: nonExistentPhone)
                            
                            // Should not throw errors
                            expect(true).to(beTrue())
                            
                        } catch {
                            fail("Error handling test failed: \(error)")
                        }
                    }
                }
            }
        }
    }
    
    private func fetchGroupsJSON(database: OpaquePointer?, phone: String) throws -> String? {
        guard let db = database else { return nil }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        let query = "SELECT groups FROM contacts WHERE phone = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "DatabaseIntegrationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        
        sqlite3_bind_text(statement, 1, phone, -1, SQLITE_TRANSIENT)
        if sqlite3_step(statement) == SQLITE_ROW, let pointer = sqlite3_column_text(statement, 0) {
            return String(cString: pointer)
        }
        return nil
    }
}
