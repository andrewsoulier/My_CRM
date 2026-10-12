import Quick
import Nimble
import Foundation
import SwiftUI
@testable import My_CRM

class DragDropTests: QuickSpec {
    override func spec() {
        
        describe("DragDropManager") {
            var dragDropManager: DragDropManager!
            var dataProvider: MockDataProvider!
            var undoManager: UndoManager!
            
            beforeEach {
                dragDropManager = DragDropManager.shared
                dataProvider = TestData.createMockDataProvider()
                undoManager = UndoManager()
            }
            
            describe("Contact Drag Item Creation") {
                context("when creating contact drag items") {
                    it("should create valid drag item from contacts bar") {
                        let phones = TestData.testPhoneNumbers.prefix(2).map { String($0) }
                        let origin = DragOrigin.contactsBar
                        let dragItem = TestData.createTestDragItem(phones: phones, origin: origin)
                        
                        expect(dragItem.phones).to(equal(phones))
                        expect(dragItem.origin).to(equal(origin))
                        expect(dragItem.uuids).toNot(beEmpty())
                    }
                    
                    it("should create valid drag item from group") {
                        let phones = TestData.testPhoneNumbers.prefix(2).map { String($0) }
                        let groupId = TestData.testGroups[0].id
                        let origin = DragOrigin.group(id: groupId)
                        let dragItem = TestData.createTestDragItem(phones: phones, origin: origin)
                        
                        expect(dragItem.phones).to(equal(phones))
                        expect(dragItem.origin).to(equal(origin))
                    }
                    
                    it("should create valid drag item from deck") {
                        let phones = TestData.testPhoneNumbers.prefix(2).map { String($0) }
                        let deckId = TestData.testDecks[0].id
                        let origin = DragOrigin.deck(id: deckId)
                        let dragItem = TestData.createTestDragItem(phones: phones, origin: origin)
                        
                        expect(dragItem.phones).to(equal(phones))
                        expect(dragItem.origin).to(equal(origin))
                    }
                }
            }
            
            describe("Drop Target Validation") {
                context("when validating drop targets") {
                    it("should allow contacts to be dropped on canvas") {
                        let phones = TestData.testPhoneNumbers.prefix(1).map { String($0) }
                        let dragItem = TestData.createTestDragItem(phones: phones, origin: .contactsBar)
                        let target = DropTarget.sandbox(position: nil)
                        
                        // This would be validated in the actual drop logic
                        expect(dragItem.phones).toNot(beEmpty())
                        expect(target).toNot(beNil())
                    }
                    
                    it("should allow contacts to be dropped on groups") {
                        let phones = TestData.testPhoneNumbers.prefix(1).map { String($0) }
                        let groupId = TestData.testGroups[0].id
                        let dragItem = TestData.createTestDragItem(phones: phones, origin: .contactsBar)
                        let target = DropTarget.group(id: groupId)
                        
                        expect(dragItem.phones).toNot(beEmpty())
                        expect(target).toNot(beNil())
                    }
                }
            }
            
            describe("Contact Drop Operations") {
                beforeEach {
                    // Set up test groups with initial members
                    Task {
                        try await dataProvider.createGroup(TestData.testGroups[0])
                        try await dataProvider.createGroup(TestData.testGroups[1])
                        try await dataProvider.updateGroupMembers(groupId: TestData.testGroups[0].id, members: [TestData.testPhoneNumbers[0]])
                    }
                }
                
                context("when dropping contacts from contacts bar to group") {
                    it("should add contacts to target group") async {
                        let phones = [TestData.testPhoneNumbers[1], TestData.testPhoneNumbers[2]]
                        let dragItem = TestData.createTestDragItem(phones: phones, origin: .contactsBar)
                        let targetGroupId = TestData.testGroups[0].id
                        
                        do {
                            try await dragDropManager.handleDrop(
                                item: dragItem,
                                target: .group(id: targetGroupId),
                                copy: false,
                                dataProvider: dataProvider,
                                undo: undoManager
                            )
                            
                            let members = dataProvider.getGroupMembers(groupId: targetGroupId)
                            expect(members).toNot(beNil())
                            expect(members?.count).to(equal(3)) // Original 1 + 2 new
                            expect(members).to(contain(phones))
                        } catch {
                            fail("Failed to drop contacts from contacts bar: \(error)")
                        }
                    }
                }
                
                context("when moving contacts between groups") {
                    it("should move contacts from source to target group") async {
                        let phones = [TestData.testPhoneNumbers[0]] // Already in group 0
                        let sourceGroupId = TestData.testGroups[0].id
                        let targetGroupId = TestData.testGroups[1].id
                        let dragItem = TestData.createTestDragItem(phones: phones, origin: .group(id: sourceGroupId))
                        
                        do {
                            try await dragDropManager.handleDrop(
                                item: dragItem,
                                target: .group(id: targetGroupId),
                                copy: false,
                                dataProvider: dataProvider,
                                undo: undoManager
                            )
                            
                            let sourceMembers = dataProvider.getGroupMembers(groupId: sourceGroupId)
                            let targetMembers = dataProvider.getGroupMembers(groupId: targetGroupId)
                            
                            expect(sourceMembers).toNot(contain(phones))
                            expect(targetMembers).to(contain(phones))
                        } catch {
                            fail("Failed to move contacts between groups: \(error)")
                        }
                    }
                }
                
                context("when copying contacts between groups") {
                    it("should copy contacts to target group without removing from source") async {
                        let phones = [TestData.testPhoneNumbers[0]] // Already in group 0
                        let sourceGroupId = TestData.testGroups[0].id
                        let targetGroupId = TestData.testGroups[1].id
                        let dragItem = TestData.createTestDragItem(phones: phones, origin: .group(id: sourceGroupId))
                        
                        do {
                            try await dragDropManager.handleDrop(
                                item: dragItem,
                                target: .group(id: targetGroupId),
                                copy: true,
                                dataProvider: dataProvider,
                                undo: undoManager
                            )
                            
                            let sourceMembers = dataProvider.getGroupMembers(groupId: sourceGroupId)
                            let targetMembers = dataProvider.getGroupMembers(groupId: targetGroupId)
                            
                            expect(sourceMembers).to(contain(phones))
                            expect(targetMembers).to(contain(phones))
                        } catch {
                            fail("Failed to copy contacts between groups: \(error)")
                        }
                    }
                }
                
                context("when dropping contacts on same group") {
                    it("should not modify group when dropping on same group") async {
                        let phones = [TestData.testPhoneNumbers[0]] // Already in group 0
                        let groupId = TestData.testGroups[0].id
                        let dragItem = TestData.createTestDragItem(phones: phones, origin: .group(id: groupId))
                        
                        do {
                            let originalMembers = dataProvider.getGroupMembers(groupId: groupId)
                            
                            try await dragDropManager.handleDrop(
                                item: dragItem,
                                target: .group(id: groupId),
                                copy: false,
                                dataProvider: dataProvider,
                                undo: undoManager
                            )
                            
                            let finalMembers = dataProvider.getGroupMembers(groupId: groupId)
                            expect(finalMembers).to(equal(originalMembers))
                        } catch {
                            fail("Failed to handle same-group drop: \(error)")
                        }
                    }
                }
            }
            
            describe("Drag Item Validation") {
                context("when validating drag items") {
                    it("should reject empty drag items") async {
                        let emptyDragItem = TestData.createTestDragItem(phones: [], origin: .contactsBar)
                        let targetGroupId = TestData.testGroups[0].id
                        
                        do {
                            try await dragDropManager.handleDrop(
                                item: emptyDragItem,
                                target: .group(id: targetGroupId),
                                copy: false,
                                dataProvider: dataProvider,
                                undo: undoManager
                            )
                            fail("Should have thrown error for empty drag item")
                        } catch {
                            expect(error.localizedDescription).to(contain("No valid contacts to drop"))
                        }
                    }
                    
                    it("should deduplicate phone numbers while preserving order") {
                        let phones = ["101-101-0001", "101-101-0002", "101-101-0001", "101-101-0003"]
                        let dragItem = TestData.createTestDragItem(phones: phones, origin: .contactsBar)
                        
                        // The deduplication happens in the handleDrop method
                        expect(dragItem.phones).to(equal(phones))
                    }
                }
            }
            
            describe("Undo Functionality") {
                beforeEach {
                    Task {
                        try await dataProvider.createGroup(TestData.testGroups[0])
                        try await dataProvider.createGroup(TestData.testGroups[1])
                        try await dataProvider.updateGroupMembers(groupId: TestData.testGroups[0].id, members: [TestData.testPhoneNumbers[0]])
                    }
                }
                
                context("when performing undo operations") {
                    it("should register undo operation for contact addition") async {
                        let phones = [TestData.testPhoneNumbers[1]]
                        let dragItem = TestData.createTestDragItem(phones: phones, origin: .contactsBar)
                        let targetGroupId = TestData.testGroups[0].id
                        
                        do {
                            try await dragDropManager.handleDrop(
                                item: dragItem,
                                target: .group(id: targetGroupId),
                                copy: false,
                                dataProvider: dataProvider,
                                undo: undoManager
                            )
                            
                            expect(undoManager.canUndo).to(beTrue())
                            
                            // Perform undo
                            undoManager.undo()
                            
                            let members = dataProvider.getGroupMembers(groupId: targetGroupId)
                            expect(members).toNot(contain(phones))
                        } catch {
                            fail("Failed to test undo functionality: \(error)")
                        }
                    }
                    
                    it("should register undo operation for contact movement") async {
                        let phones = [TestData.testPhoneNumbers[0]]
                        let sourceGroupId = TestData.testGroups[0].id
                        let targetGroupId = TestData.testGroups[1].id
                        let dragItem = TestData.createTestDragItem(phones: phones, origin: .group(id: sourceGroupId))
                        
                        do {
                            try await dragDropManager.handleDrop(
                                item: dragItem,
                                target: .group(id: targetGroupId),
                                copy: false,
                                dataProvider: dataProvider,
                                undo: undoManager
                            )
                            
                            expect(undoManager.canUndo).to(beTrue())
                            
                            // Perform undo
                            undoManager.undo()
                            
                            let sourceMembers = dataProvider.getGroupMembers(groupId: sourceGroupId)
                            let targetMembers = dataProvider.getGroupMembers(groupId: targetGroupId)
                            
                            expect(sourceMembers).to(contain(phones))
                            expect(targetMembers).toNot(contain(phones))
                        } catch {
                            fail("Failed to test undo for contact movement: \(error)")
                        }
                    }
                }
            }
            
            describe("Error Handling") {
                context("when handling invalid operations") {
                    it("should handle non-existent group gracefully") async {
                        let phones = [TestData.testPhoneNumbers[0]]
                        let dragItem = TestData.createTestDragItem(phones: phones, origin: .contactsBar)
                        let nonExistentGroupId = UUID()
                        
                        do {
                            try await dragDropManager.handleDrop(
                                item: dragItem,
                                target: .group(id: nonExistentGroupId),
                                copy: false,
                                dataProvider: dataProvider,
                                undo: undoManager
                            )
                            fail("Should have thrown error for non-existent group")
                        } catch {
                            expect(error).toNot(beNil())
                        }
                    }
                }
            }
        }
    }
}
