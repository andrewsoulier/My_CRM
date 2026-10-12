import Quick
import Nimble
import Foundation
@testable import My_CRM

class UserWorkflowTests: QuickSpec {
    override func spec() {
        
        describe("Complete User Workflows") {
            var dataProvider: MockDataProvider!
            var dragDropManager: DragDropManager!
            var undoManager: UndoManager!
            
            beforeEach {
                dataProvider = TestData.createMockDataProvider()
                dragDropManager = DragDropManager.shared
                undoManager = UndoManager()
            }
            
            describe("Workflow: Create Group and Add Contacts") {
                context("when user creates a new group and adds contacts") {
                    it("should complete the full workflow successfully") async {
                        // Step 1: Create a new group
                        let newGroup = TestData.createTestGroup(name: "Workflow Test Group")
                        
                        do {
                            try await dataProvider.createGroup(newGroup)
                            
                            // Verify group was created
                            let retrievedGroup = try await dataProvider.getGroup(by: newGroup.id)
                            expect(retrievedGroup).toNot(beNil())
                            expect(retrievedGroup?.name).to(equal("Workflow Test Group"))
                            
                            // Step 2: Add contacts to the group
                            let contactsToAdd = Array(TestData.testPhoneNumbers.prefix(3))
                            try await dataProvider.updateGroupMembers(groupId: newGroup.id, members: contactsToAdd)
                            
                            // Verify contacts were added
                            let members = dataProvider.getGroupMembers(groupId: newGroup.id)
                            expect(members).toNot(beNil())
                            expect(members?.count).to(equal(3))
                            expect(members).to(contain(contactsToAdd))
                            
                            // Step 3: Verify group properties
                            expect(retrievedGroup?.memberCount).to(equal(3))
                            expect(retrievedGroup?.isRoot).to(beTrue())
                            
                        } catch {
                            fail("Workflow failed: \(error)")
                        }
                    }
                }
            }
            
            describe("Workflow: Drag and Drop from Contacts Bar to Group") {
                beforeEach {
                    // Set up initial state
                    Task {
                        let group = TestData.testGroups[0]
                        try await dataProvider.createGroup(group)
                    }
                }
                
                context("when user drags contacts from contacts bar to group") {
                    it("should complete the drag and drop workflow") async {
                        let group = TestData.testGroups[0]
                        let contactsToDrag = Array(TestData.testPhoneNumbers.prefix(2))
                        let dragItem = TestData.createTestDragItem(phones: contactsToDrag, origin: .contactsBar)
                        
                        do {
                            // Perform drag and drop
                            try await dragDropManager.handleDrop(
                                item: dragItem,
                                target: .group(id: group.id),
                                copy: false,
                                dataProvider: dataProvider,
                                undo: undoManager
                            )
                            
                            // Verify contacts were added to group
                            let members = dataProvider.getGroupMembers(groupId: group.id)
                            expect(members).toNot(beNil())
                            expect(members?.count).to(equal(2))
                            expect(members).to(contain(contactsToDrag))
                            
                            // Verify undo is available
                            expect(undoManager.canUndo).to(beTrue())
                            
                        } catch {
                            fail("Drag and drop workflow failed: \(error)")
                        }
                    }
                }
            }
            
            describe("Workflow: Move Contacts Between Groups") {
                beforeEach {
                    // Set up two groups with initial members
                    Task {
                        let group1 = TestData.testGroups[0]
                        let group2 = TestData.testGroups[1]
                        
                        try await dataProvider.createGroup(group1)
                        try await dataProvider.createGroup(group2)
                        
                        // Add contacts to group 1
                        try await dataProvider.updateGroupMembers(groupId: group1.id, members: [TestData.testPhoneNumbers[0], TestData.testPhoneNumbers[1]])
                        try await dataProvider.updateGroupMembers(groupId: group2.id, members: [TestData.testPhoneNumbers[2]])
                    }
                }
                
                context("when user moves contacts from one group to another") {
                    it("should complete the move workflow") async {
                        let sourceGroup = TestData.testGroups[0]
                        let targetGroup = TestData.testGroups[1]
                        let contactsToMove = [TestData.testPhoneNumbers[0]]
                        let dragItem = TestData.createTestDragItem(phones: contactsToMove, origin: .group(id: sourceGroup.id))
                        
                        do {
                            // Record initial state
                            let initialSourceMembers = dataProvider.getGroupMembers(groupId: sourceGroup.id)
                            let initialTargetMembers = dataProvider.getGroupMembers(groupId: targetGroup.id)
                            
                            // Perform move operation
                            try await dragDropManager.handleDrop(
                                item: dragItem,
                                target: .group(id: targetGroup.id),
                                copy: false,
                                dataProvider: dataProvider,
                                undo: undoManager
                            )
                            
                            // Verify move was successful
                            let finalSourceMembers = dataProvider.getGroupMembers(groupId: sourceGroup.id)
                            let finalTargetMembers = dataProvider.getGroupMembers(groupId: targetGroup.id)
                            
                            expect(finalSourceMembers).toNot(contain(contactsToMove))
                            expect(finalTargetMembers).to(contain(contactsToMove))
                            expect(finalSourceMembers?.count).to(equal(1)) // One contact removed
                            expect(finalTargetMembers?.count).to(equal(2)) // One contact added
                            
                            // Verify undo is available
                            expect(undoManager.canUndo).to(beTrue())
                            
                        } catch {
                            fail("Move workflow failed: \(error)")
                        }
                    }
                }
            }
            
            describe("Workflow: Copy Contacts Between Groups") {
                beforeEach {
                    // Set up two groups with initial members
                    Task {
                        let group1 = TestData.testGroups[0]
                        let group2 = TestData.testGroups[1]
                        
                        try await dataProvider.createGroup(group1)
                        try await dataProvider.createGroup(group2)
                        
                        // Add contacts to group 1
                        try await dataProvider.updateGroupMembers(groupId: group1.id, members: [TestData.testPhoneNumbers[0], TestData.testPhoneNumbers[1]])
                        try await dataProvider.updateGroupMembers(groupId: group2.id, members: [TestData.testPhoneNumbers[2]])
                    }
                }
                
                context("when user copies contacts from one group to another") {
                    it("should complete the copy workflow") async {
                        let sourceGroup = TestData.testGroups[0]
                        let targetGroup = TestData.testGroups[1]
                        let contactsToCopy = [TestData.testPhoneNumbers[0]]
                        let dragItem = TestData.createTestDragItem(phones: contactsToCopy, origin: .group(id: sourceGroup.id))
                        
                        do {
                            // Record initial state
                            let initialSourceMembers = dataProvider.getGroupMembers(groupId: sourceGroup.id)
                            let initialTargetMembers = dataProvider.getGroupMembers(groupId: targetGroup.id)
                            
                            // Perform copy operation
                            try await dragDropManager.handleDrop(
                                item: dragItem,
                                target: .group(id: targetGroup.id),
                                copy: true,
                                dataProvider: dataProvider,
                                undo: undoManager
                            )
                            
                            // Verify copy was successful
                            let finalSourceMembers = dataProvider.getGroupMembers(groupId: sourceGroup.id)
                            let finalTargetMembers = dataProvider.getGroupMembers(groupId: targetGroup.id)
                            
                            expect(finalSourceMembers).to(contain(contactsToCopy)) // Still in source
                            expect(finalTargetMembers).to(contain(contactsToCopy)) // Also in target
                            expect(finalSourceMembers?.count).to(equal(initialSourceMembers?.count ?? 0)) // Source unchanged
                            expect(finalTargetMembers?.count).to(equal((initialTargetMembers?.count ?? 0) + 1)) // Target increased
                            
                            // Verify undo is available
                            expect(undoManager.canUndo).to(beTrue())
                            
                        } catch {
                            fail("Copy workflow failed: \(error)")
                        }
                    }
                }
            }
            
            describe("Workflow: Create Deck and Organize Contacts") {
                context("when user creates a deck and organizes contacts") {
                    it("should complete the deck creation and organization workflow") async {
                        // Step 1: Create a new deck
                        let newDeck = TestData.createTestDeck(name: "Workflow Test Deck")
                        
                        do {
                            try await dataProvider.createDeck(newDeck)
                            
                            // Verify deck was created
                            let retrievedDeck = try await dataProvider.getDeck(by: newDeck.id)
                            expect(retrievedDeck).toNot(beNil())
                            expect(retrievedDeck?.name).to(equal("Workflow Test Deck"))
                            expect(retrievedDeck?.isDeck).to(beTrue())
                            
                            // Step 2: Add contacts to the deck
                            let contactsToAdd = Array(TestData.testPhoneNumbers.prefix(3))
                            try await dataProvider.updateGroupMembers(groupId: newDeck.id, members: contactsToAdd)
                            
                            // Verify contacts were added
                            let members = dataProvider.getGroupMembers(groupId: newDeck.id)
                            expect(members).toNot(beNil())
                            expect(members?.count).to(equal(3))
                            expect(members).to(contain(contactsToAdd))
                            
                        } catch {
                            fail("Deck workflow failed: \(error)")
                        }
                    }
                }
            }
            
            describe("Workflow: Undo and Redo Operations") {
                beforeEach {
                    // Set up initial state
                    Task {
                        let group = TestData.testGroups[0]
                        try await dataProvider.createGroup(group)
                        try await dataProvider.updateGroupMembers(groupId: group.id, members: [TestData.testPhoneNumbers[0]])
                    }
                }
                
                context("when user performs undo and redo operations") {
                    it("should complete the undo/redo workflow") async {
                        let group = TestData.testGroups[0]
                        let contactsToAdd = [TestData.testPhoneNumbers[1], TestData.testPhoneNumbers[2]]
                        let dragItem = TestData.createTestDragItem(phones: contactsToAdd, origin: .contactsBar)
                        
                        do {
                            // Step 1: Add contacts (creates undo operation)
                            try await dragDropManager.handleDrop(
                                item: dragItem,
                                target: .group(id: group.id),
                                copy: false,
                                dataProvider: dataProvider,
                                undo: undoManager
                            )
                            
                            // Verify contacts were added
                            let membersAfterAdd = dataProvider.getGroupMembers(groupId: group.id)
                            expect(membersAfterAdd?.count).to(equal(3))
                            expect(undoManager.canUndo).to(beTrue())
                            
                            // Step 2: Undo the operation
                            undoManager.undo()
                            
                            // Verify undo was successful
                            let membersAfterUndo = dataProvider.getGroupMembers(groupId: group.id)
                            expect(membersAfterUndo?.count).to(equal(1))
                            expect(membersAfterUndo).toNot(contain(contactsToAdd))
                            expect(undoManager.canRedo).to(beTrue())
                            
                            // Step 3: Redo the operation
                            undoManager.redo()
                            
                            // Verify redo was successful
                            let membersAfterRedo = dataProvider.getGroupMembers(groupId: group.id)
                            expect(membersAfterRedo?.count).to(equal(3))
                            expect(membersAfterRedo).to(contain(contactsToAdd))
                            
                        } catch {
                            fail("Undo/redo workflow failed: \(error)")
                        }
                    }
                }
            }
            
            describe("Workflow: Error Recovery") {
                context("when operations fail") {
                    it("should handle errors gracefully and maintain data consistency") async {
                        let nonExistentGroupId = UUID()
                        let contactsToDrag = [TestData.testPhoneNumbers[0]]
                        let dragItem = TestData.createTestDragItem(phones: contactsToDrag, origin: .contactsBar)
                        
                        do {
                            // Attempt to drop on non-existent group
                            try await dragDropManager.handleDrop(
                                item: dragItem,
                                target: .group(id: nonExistentGroupId),
                                copy: false,
                                dataProvider: dataProvider,
                                undo: undoManager
                            )
                            fail("Should have thrown error for non-existent group")
                        } catch {
                            // Verify error was thrown
                            expect(error).toNot(beNil())
                            
                            // Verify no undo operation was registered for failed operation
                            expect(undoManager.canUndo).to(beFalse())
                        }
                    }
                }
            }
        }
    }
}
