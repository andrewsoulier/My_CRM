import Foundation
import SwiftUI
import UniformTypeIdentifiers

private let contactISOFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

struct Contact: Identifiable, Hashable, Codable, Transferable {
    var id: UUID
    var databaseId: Int64?
    var phone: String // primary UID
    var name: String
    var nickname: String?
    var firstName: String?
    var lastName: String?
    var email: String?
    var address: String?
    var notes: String?
    var creationDate: Date?
    var business: String?
    var contactGroup: String?
    var birthday: Date?
    var appleContactID: String?
    var profilePhotoData: Data? // Add profile photo data
    var lastMessageDate: Date? // Last message date for sorting
    var lastMessageSentDate: Date?
    var lastMessageReceivedDate: Date?
    var tagIDs: [UUID]
    var relationshipIDs: [UUID]
    var totalMessages: Int
    var messagesSentCount: Int
    var messagesReceivedCount: Int
    var sentLastMessage: Bool
    
    // Transferable conformance
    static var transferRepresentation: some TransferRepresentation {
        // Use CodableRepresentation as primary for internal drag and drop
        CodableRepresentation(contentType: .crmContactList)
        FileRepresentation(contentType: .vCard) { contact in
            // Create vCard data
            let vCardString = contact.toVCardString()
            let vCardData = vCardString.data(using: .utf8) ?? Data()
            
            // Create temporary file with person's name (or phone if name is missing)
            let fileName = contact.name.isEmpty ? contact.phone : contact.name
            let safeFileName = fileName
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "\\", with: "_")
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(safeFileName).vcf")
            
            print("📁 Creating vCard file: \(tempURL)")
            print("📄 vCard content: \(vCardString)")
            
            try vCardData.write(to: tempURL)
            
            // Verify file was created
            let fileExists = FileManager.default.fileExists(atPath: tempURL.path)
            print("✅ File created successfully: \(fileExists)")
            
            return SentTransferredFile(tempURL)
        } importing: { received in
            // Import vCard data back to Contact
            let vCardData = try Data(contentsOf: received.file)
            let vCardString = String(data: vCardData, encoding: .utf8) ?? ""
            return Contact.fromVCardString(vCardString)
        }
    }
    
    // Convert Contact to vCard format
    // Standard format matching: Andrew Soulier.vcf specification
    func toVCardString() -> String {
        var vCard = "BEGIN:VCARD\n"
        vCard += "VERSION:3.0\n"
        vCard += "PRODID:-//Apple Inc.//macOS 15.6.1//EN\n"
        
        // Format name with proper N: field structure
        if let firstName = firstName, let lastName = lastName, !firstName.isEmpty, !lastName.isEmpty {
            vCard += "N:\(lastName);\(firstName);;;\n"
            vCard += "FN:\(firstName) \(lastName)\n"
        } else {
            // Use display name for both N and FN fields
            vCard += "N:\(name);;;;\n"
            vCard += "FN:\(name)\n"
        }
        
        // Add organization if available
        if let business = business, !business.isEmpty {
            vCard += "ORG:\(business);\n"
        }
        
        // Phone with proper type specifications
        vCard += "TEL;type=CELL;type=VOICE;type=pref:\(phone)\n"
        
        if let email = email, !email.isEmpty {
            vCard += "EMAIL:\(email)\n"
        }
        
        if let address = address, !address.isEmpty {
            vCard += "ADR:;;\(address);;;;\n"
        }
        
        if let notes = notes, !notes.isEmpty {
            vCard += "NOTE:\(notes)\n"
        }
        
        vCard += "END:VCARD\n"
        return vCard
    }
    
    // Convert vCard string back to Contact
    // Handles standard vCard format matching: Andrew Soulier.vcf specification
    static func fromVCardString(_ vCardString: String) -> Contact {
        print("📱 Parsing vCard string: \(vCardString)")
        let lines = vCardString.components(separatedBy: .newlines)
        var name = ""
        var firstName = ""
        var lastName = ""
        var phone = ""
        var email = ""
        var address = ""
        var notes = ""
        var business = ""
        
        for line in lines {
            if line.hasPrefix("UID:") {
                let uidString = String(line.dropFirst(4))
                // Use UID as phone number since we're now storing phone as UID
                phone = uidString
            } else if line.hasPrefix("FN:") {
                name = String(line.dropFirst(3))
            } else if line.hasPrefix("N:") {
                let parts = String(line.dropFirst(2)).components(separatedBy: ";")
                if parts.count >= 2 {
                    lastName = parts[0]
                    firstName = parts[1]
                }
            } else if line.hasPrefix("TEL;") {
                // Extract phone number from TEL line (handle both old and new formats)
                let phonePart = line.components(separatedBy: ":").last ?? ""
                phone = phonePart
            } else if line.hasPrefix("EMAIL:") {
                email = String(line.dropFirst(6))
            } else if line.hasPrefix("ADR:") {
                address = String(line.dropFirst(4))
            } else if line.hasPrefix("NOTE:") {
                notes = String(line.dropFirst(5))
            } else if line.hasPrefix("ORG:") {
                // Handle organization field (may have semicolon at end)
                let orgString = String(line.dropFirst(4))
                business = orgString.replacingOccurrences(of: ";", with: "")
            }
        }
        
        // Clean up business field (remove trailing semicolon)
        business = business.replacingOccurrences(of: ";", with: "").trimmingCharacters(in: .whitespaces)
        
        // Determine the best name to use - prioritize full name, then first/last, then email, then phone
        var finalName = name.trimmingCharacters(in: .whitespaces)
        if finalName.isEmpty {
            let constructedName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            if !constructedName.isEmpty {
                finalName = constructedName
            } else if !email.isEmpty {
                finalName = email
            } else if !phone.isEmpty {
                finalName = phone
            } else {
                // Last resort fallback
                finalName = "Unknown Contact"
            }
        }
        
        let contact = Contact(
            phone: phone,
            name: finalName,
            firstName: firstName.isEmpty ? nil : firstName,
            lastName: lastName.isEmpty ? nil : lastName,
            email: email.isEmpty ? nil : email,
            address: address.isEmpty ? nil : address,
            notes: notes.isEmpty ? nil : notes,
            business: business.isEmpty ? nil : business
        )
        
        print("📱 Created contact from vCard: \(contact.name) with phone: '\(phone)' - phone length: \(phone.count)")
        print("📱 vCard parsing results - name: '\(name)', firstName: '\(firstName)', lastName: '\(lastName)', phone: '\(phone)', business: '\(business)'")
        
        return contact
    }
    

    
    // Computed properties
    var displayName: String {
        if let nickname = nickname, !nickname.isEmpty {
            return nickname
        }
        if let firstName = firstName, let lastName = lastName, !firstName.isEmpty, !lastName.isEmpty {
            return "\(firstName) \(lastName)"
        } else if let firstName = firstName, !firstName.isEmpty {
            return firstName
        } else if let lastName = lastName, !lastName.isEmpty {
            return lastName
        } else if !name.isEmpty {
            return name
        } else {
            return phone // Fallback to phone number if no name is available
        }
    }
    
    var initials: String {
        // Prioritize firstName and lastName for initials
        if let firstName = firstName, let lastName = lastName, !firstName.isEmpty, !lastName.isEmpty {
            let firstInitial = String(firstName.prefix(1)).uppercased()
            let lastInitial = String(lastName.prefix(1)).uppercased()
            return firstInitial + lastInitial
        } else if let firstName = firstName, !firstName.isEmpty {
            return String(firstName.prefix(1)).uppercased()
        } else if let lastName = lastName, !lastName.isEmpty {
            return String(lastName.prefix(1)).uppercased()
        } else if !name.isEmpty {
            // Use the name field if available
            let components = name.components(separatedBy: " ")
            let initials = components.prefix(2).compactMap { $0.first }
            let result = String(initials).uppercased()
            return result.isEmpty ? "?" : result
        } else {
            // Fallback to phone number (first 2 characters)
            let phoneDigits = phone.filter { $0.isNumber }
            if phoneDigits.count >= 2 {
                return String(phoneDigits.prefix(2))
            } else if phoneDigits.count == 1 {
                return phoneDigits + "?"
            } else {
                return "??"
            }
        }
    }
    
    // Computed property to get NSImage from profile photo data
    var profileImage: NSImage? {
        guard let photoData = profilePhotoData, !photoData.isEmpty else { 
            print("📷 No profile photo data for contact: \(displayName) (\(phone))")
            return nil 
        }
        
        guard let image = NSImage(data: photoData) else {
            print("❌ Failed to create NSImage from profile photo data for contact: \(displayName) (\(phone)) - data size: \(photoData.count) bytes")
            return nil
        }
        
        print("✅ Successfully created profile image for contact: \(displayName) (\(phone)) - image size: \(image.size)")
        return image
    }
    
    // SQLite integration
    init(from sqliteRow: [String: Any]) {
        self.id = UUID(uuidString: sqliteRow["id"] as? String ?? "") ?? UUID()
        if let rawDatabaseID = sqliteRow["database_id"] as? Int64 {
            self.databaseId = rawDatabaseID
        } else if let rawInt = sqliteRow["database_id"] as? Int {
            self.databaseId = Int64(rawInt)
        } else if let rawId = sqliteRow["id"] as? Int64 {
            self.databaseId = rawId
        } else if let rawInt = sqliteRow["id"] as? Int {
            self.databaseId = Int64(rawInt)
        } else {
            self.databaseId = nil
        }
        self.phone = sqliteRow["phone"] as? String ?? ""
        self.name = sqliteRow["name"] as? String ?? ""
        self.nickname = sqliteRow["nickname"] as? String
        self.firstName = sqliteRow["first_name"] as? String
        self.lastName = sqliteRow["last_name"] as? String
        self.email = sqliteRow["email"] as? String
        self.address = sqliteRow["address"] as? String
        self.notes = sqliteRow["notes"] as? String
        self.creationDate = parseDate(sqliteRow["creation_date"])
        self.business = sqliteRow["business"] as? String
        self.contactGroup = sqliteRow["contact_group"] as? String
        self.birthday = parseDate(sqliteRow["birthday"])
        self.appleContactID = sqliteRow["apple_contact_id"] as? String
        self.profilePhotoData = sqliteRow["profile_photo"] as? Data
        if let tagIDsJSON = sqliteRow["tag_ids"] as? String,
           let data = tagIDsJSON.data(using: .utf8),
           let identifiers = try? JSONDecoder().decode([String].self, from: data) {
            self.tagIDs = identifiers.compactMap { UUID(uuidString: $0) }
        } else {
            self.tagIDs = []
        }
        if let relationshipIDsJSON = sqliteRow["relationship_ids"] as? String,
           let data = relationshipIDsJSON.data(using: .utf8),
           let identifiers = try? JSONDecoder().decode([String].self, from: data) {
            self.relationshipIDs = identifiers.compactMap { UUID(uuidString: $0) }
        } else {
            self.relationshipIDs = []
        }
        self.lastMessageSentDate = parseDate(sqliteRow["last_message_sent_date"])
        self.lastMessageReceivedDate = parseDate(sqliteRow["last_message_received_date"])
        self.totalMessages = sqliteRow["total_messages"] as? Int ?? 0
        self.messagesSentCount = sqliteRow["messages_sent"] as? Int ?? 0
        self.messagesReceivedCount = sqliteRow["messages_received"] as? Int ?? 0
        if let sentValue = sqliteRow["sent_last_message"] as? Int {
            self.sentLastMessage = sentValue != 0
        } else if let sentValue = sqliteRow["sent_last_message"] as? Bool {
            self.sentLastMessage = sentValue
        } else {
            self.sentLastMessage = false
        }
    }
    
    init(phone: String, name: String, nickname: String? = nil, firstName: String? = nil, lastName: String? = nil,
         email: String? = nil, address: String? = nil, notes: String? = nil,
         business: String? = nil, contactGroup: String? = nil, birthday: Date? = nil,
         appleContactID: String? = nil, profilePhotoData: Data? = nil, lastMessageDate: Date? = nil,
         lastMessageSentDate: Date? = nil, lastMessageReceivedDate: Date? = nil,
         tagIDs: [UUID] = [], relationshipIDs: [UUID] = []) {
        self.id = UUID()
        self.databaseId = nil
        self.phone = phone
        self.name = name
        self.nickname = nickname
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.address = address
        self.notes = notes
        self.creationDate = Date()
        self.business = business
        self.contactGroup = contactGroup
        self.birthday = birthday
        self.appleContactID = appleContactID
        self.profilePhotoData = profilePhotoData
        self.lastMessageDate = lastMessageDate
        self.lastMessageSentDate = lastMessageSentDate
        self.lastMessageReceivedDate = lastMessageReceivedDate
        self.tagIDs = tagIDs
        self.relationshipIDs = relationshipIDs
        self.totalMessages = 0
        self.messagesSentCount = 0
        self.messagesReceivedCount = 0
        self.sentLastMessage = false
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(phone)
    }
    
    static func == (lhs: Contact, rhs: Contact) -> Bool {
        lhs.phone == rhs.phone
    }
}

private func parseDate(_ value: Any?) -> Date? {
    if let date = value as? Date {
        return date
    }
    if let string = value as? String {
        return contactISOFormatter.date(from: string)
    }
    if let number = value as? NSNumber {
        return Date(timeIntervalSince1970: number.doubleValue)
    }
    return nil
}
