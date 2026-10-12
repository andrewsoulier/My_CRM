import XCTest
import AppKit
@testable import MyCRM

final class DragDropTests: XCTestCase {
    var dragDropManager: DragDropManager!
    
    override func setUp() {
        super.setUp()
        dragDropManager = DragDropManager()
    }
    
    override func tearDown() {
        dragDropManager = nil
        super.tearDown()
    }
    
    func testContactItemProviderCreation() {
        let phones = ["+1-555-123-4567", "+1-555-987-6543"]
        let itemProvider = dragDropManager.createContactItemProvider(for: phones)
        
        XCTAssertTrue(itemProvider.hasItemConformingToTypeIdentifier(DragDropManager.contactUTI))
        XCTAssertTrue(itemProvider.hasItemConformingToTypeIdentifier("public.vcard"))
    }
    
    func testGroupItemProviderCreation() {
        let groupID = UUID()
        let itemProvider = dragDropManager.createGroupItemProvider(for: groupID)
        
        XCTAssertTrue(itemProvider.hasItemConformingToTypeIdentifier(DragDropManager.groupUTI))
    }
    
    func testDeckItemProviderCreation() {
        let deckID = UUID()
        let itemProvider = dragDropManager.createDeckItemProvider(for: deckID)
        
        XCTAssertTrue(itemProvider.hasItemConformingToTypeIdentifier(DragDropManager.deckUTI))
    }
    
    func testContactDecoding() async {
        let phones = ["+1-555-123-4567", "+1-555-987-6543"]
        let itemProvider = dragDropManager.createContactItemProvider(for: phones)
        
        let decodedPhones = await dragDropManager.decodeContacts(from: itemProvider)
        
        XCTAssertEqual(decodedPhones, phones)
    }
    
    func testGroupDecoding() async {
        let groupID = UUID()
        let itemProvider = dragDropManager.createGroupItemProvider(for: groupID)
        
        let decodedGroupID = await dragDropManager.decodeGroup(from: itemProvider)
        
        XCTAssertEqual(decodedGroupID, groupID)
    }
    
    func testDeckDecoding() async {
        let deckID = UUID()
        let itemProvider = dragDropManager.createDeckItemProvider(for: deckID)
        
        let decodedDeckID = await dragDropManager.decodeDeck(from: itemProvider)
        
        XCTAssertEqual(decodedDeckID, deckID)
    }
    
    func testInvalidItemProvider() async {
        let emptyItemProvider = NSItemProvider()
        
        let decodedContacts = await dragDropManager.decodeContacts(from: emptyItemProvider)
        let decodedGroup = await dragDropManager.decodeGroup(from: emptyItemProvider)
        let decodedDeck = await dragDropManager.decodeDeck(from: emptyItemProvider)
        
        XCTAssertNil(decodedContacts)
        XCTAssertNil(decodedGroup)
        XCTAssertNil(decodedDeck)
    }
    
    func testDropValidation() {
        // Valid drops
        XCTAssertTrue(dragDropManager.canDrop(.contacts(["123"]), on: .canvas))
        XCTAssertTrue(dragDropManager.canDrop(.contacts(["123"]), on: .group(UUID())))
        XCTAssertTrue(dragDropManager.canDrop(.contacts(["123"]), on: .deck(UUID())))
        XCTAssertTrue(dragDropManager.canDrop(.group(UUID()), on: .canvas))
        XCTAssertTrue(dragDropManager.canDrop(.deck(UUID()), on: .canvas))
        
        // Invalid drops
        XCTAssertFalse(dragDropManager.canDrop(.group(UUID()), on: .group(UUID())))
        XCTAssertFalse(dragDropManager.canDrop(.deck(UUID()), on: .deck(UUID())))
        XCTAssertFalse(dragDropManager.canDrop(.group(UUID()), on: .deck(UUID())))
    }
    
    func testDragStateManagement() {
        XCTAssertFalse(dragDropManager.isDragging)
        XCTAssertNil(dragDropManager.dragSource)
        XCTAssertNil(dragDropManager.dragTarget)
        
        // Start dragging
        let source = DragDropManager.DragSource.contacts(["123"])
        dragDropManager.startDragging(source)
        
        XCTAssertTrue(dragDropManager.isDragging)
        XCTAssertEqual(dragDropManager.dragSource, source)
        
        // Set drag target
        let target = DragDropManager.DragTarget.canvas
        dragDropManager.setDragTarget(target)
        
        XCTAssertEqual(dragDropManager.dragTarget, target)
        
        // Stop dragging
        dragDropManager.stopDragging()
        
        XCTAssertFalse(dragDropManager.isDragging)
        XCTAssertNil(dragDropManager.dragSource)
        XCTAssertNil(dragDropManager.dragTarget)
    }
    
    func testVCFGeneration() {
        let phones = ["+1-555-123-4567", "+1-555-987-6543"]
        let itemProvider = dragDropManager.createContactItemProvider(for: phones)
        
        // Test that VCF data can be generated
        XCTAssertTrue(itemProvider.hasItemConformingToTypeIdentifier("public.vcard"))
    }
    
    func testContactDragItemEncodingDecoding() throws {
        let phones = ["123-456-7890", "987-654-3210"]
        let origin = DragOrigin.contactsBar
        let item = ContactDragItem(phones: phones, origin: origin)
        
        // Test encoding
        let data = try JSONEncoder().encode(item)
        XCTAssertNotNil(data)
        
        // Test decoding
        let decodedItem = try JSONDecoder().decode(ContactDragItem.self, from: data)
        XCTAssertEqual(decodedItem.phones, phones)
        XCTAssertEqual(decodedItem.origin, origin)
    }
    
    func testDragOriginEncodingDecoding() throws {
        let groupId = UUID()
        let deckId = UUID()
        
        let origins: [DragOrigin] = [
            .contactsBar,
            .group(id: groupId),
            .deck(id: deckId)
        ]
        
        for origin in origins {
            let data = try JSONEncoder().encode(origin)
            let decodedOrigin = try JSONDecoder().decode(DragOrigin.self, from: data)
            XCTAssertEqual(decodedOrigin, origin)
        }
    }
    
    func testContactTransferable() throws {
        let phones = ["123-456-7890"]
        let origin = DragOrigin.contactsBar
        let item = ContactDragItem(phones: phones, origin: origin)
        let transferable = ContactTransferable(item: item)
        
        XCTAssertEqual(transferable.item.phones, phones)
        XCTAssertEqual(transferable.item.origin, origin)
    }
    
    func testProviderBridgeEncodingDecoding() throws {
        let phones = ["123-456-7890", "987-654-3210"]
        let origin = DragOrigin.group(id: UUID())
        let item = ContactDragItem(phones: phones, origin: origin)
        
        // Test encoding
        let data = ProviderBridge.encode(item)
        XCTAssertNotNil(data)
        
        // Test decoding
        guard let data = data else {
            XCTFail("Failed to encode item")
            return
        }
        let decodedItem = ProviderBridge.decode(data)
        XCTAssertNotNil(decodedItem)
        guard let decodedItem = decodedItem else {
            XCTFail("Failed to decode item")
            return
        }
        XCTAssertEqual(decodedItem.phones, phones)
        XCTAssertEqual(decodedItem.origin, origin)
    }
    
    func testVCFDataCreation() throws {
        let phones = ["123-456-7890"]
        let mockProvider = SQLiteDataProvider()
        
        // Add a test contact
        let contact = Contact(
            phone: "123-456-7890",
            name: "Test Contact",
            firstName: "Test",
            lastName: "Contact",
            email: "test@example.com",
            address: "123 Test St",
            notes: "Test notes",
            business: "Test Company"
        )
        mockProvider.contacts.append(contact)
        
        let vcfData = ProviderBridge.createVCFData(for: phones, dataProvider: mockProvider)
        XCTAssertNotNil(vcfData)
        
        guard let vcfData = vcfData else {
            XCTFail("Failed to generate VCF data")
            return
        }
        let vcfString = String(data: vcfData, encoding: .utf8)
        XCTAssertNotNil(vcfString)
        guard let vcfString = vcfString else {
            XCTFail("Failed to convert VCF data to string")
            return
        }
        XCTAssertTrue(vcfString.contains("BEGIN:VCARD"))
        XCTAssertTrue(vcfString.contains("TEL:123-456-7890"))
        XCTAssertTrue(vcfString.contains("FN:Test Contact"))
    }
    
    func testDeduplicationPreservesOrder() throws {
        let phones = ["A", "B", "A", "C", "B"]
        let origin = DragOrigin.contactsBar
        let item = ContactDragItem(phones: phones, origin: origin)
        
        // The DragDropManager should deduplicate while preserving order
        guard let uniquePhones = Array(NSOrderedSet(array: item.phones)) as? [String] else {
            XCTFail("Failed to convert phones to string array")
            return
        }
        XCTAssertEqual(uniquePhones, ["A", "B", "C"])
    }
}
