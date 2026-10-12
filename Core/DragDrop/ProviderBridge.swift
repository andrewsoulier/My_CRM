import Foundation
import Contacts
import UniformTypeIdentifiers

class ProviderBridge {
    
    // MARK: - Encode/Decode ContactDragItem
    
    static func encode(_ item: ContactDragItem) -> Data? {
        return try? JSONEncoder().encode(item)
    }
    
    static func decode(_ data: Data) -> ContactDragItem? {
        do {
            let item = try JSONDecoder().decode(ContactDragItem.self, from: data)
            DragDropLogger.shared.log("Successfully decoded ContactDragItem with \(item.phones.count) phones", operation: "DECODE")
            return item
        } catch {
            DragDropLogger.shared.log("Failed to decode ContactDragItem: \(error)", operation: "ERROR")
            return nil
        }
    }
    
    // MARK: - VCF Export for External Drag
    
    static func createVCFData(for phones: [String], dataProvider: any DataProvider) -> Data? {
        var vcfContent = ""
        
        for phone in phones {
            // Try to get contact from data provider
            if let contact = dataProvider.getContact(by: phone) {
                vcfContent += createVCFEntry(for: contact)
            } else {
                // Fallback: create basic VCF entry with just phone
                vcfContent += createBasicVCFEntry(for: phone)
            }
        }
        
        return vcfContent.data(using: .utf8)
    }
    
    private static func createVCFEntry(for contact: Contact) -> String {
        // Use the standardized vCard format from Contact.toVCardString()
        return contact.toVCardString()
    }
    
    private static func createBasicVCFEntry(for phone: String) -> String {
        // Create a basic contact and use standardized vCard format
        let contact = Contact(phone: phone, name: "Contact (\(phone))")
        return contact.toVCardString()
    }
    
    // MARK: - NSItemProvider Creation
    
    static func createItemProvider(for item: ContactDragItem, dataProvider: any DataProvider) -> NSItemProvider {
        let provider = NSItemProvider()
        
        // Register CRM contact list representation
        provider.registerDataRepresentation(forTypeIdentifier: UTType.crmContactList.identifier, visibility: .all) { completion in
            if let data = encode(item) {
                completion(data, nil)
            } else {
                completion(nil, NSError(domain: "CRM", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode contact drag item"]))
            }
            return nil
        }
        
        // Register VCF representation for external drag
        provider.registerFileRepresentation(forTypeIdentifier: UTType.vCard.identifier, visibility: .all) { completion in
            if let vcfData = createVCFData(for: item.phones, dataProvider: dataProvider) {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Contacts.vcf")
                do {
                    try vcfData.write(to: tempURL)
                    completion(tempURL, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            } else {
                completion(nil, false, NSError(domain: "CRM", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create VCF data"]))
            }
            return nil
        }
        
        return provider
    }
}
