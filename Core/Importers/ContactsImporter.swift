import Foundation
import Contacts
import SQLite3

struct ContactsImportResult {
    let totalRead: Int
    let totalInserted: Int
    let totalUpdated: Int
}

final class ContactsImporter {
    private let logger = LogManager.shared
    
    /// Normalize phone number to format +###########
    /// Removes spaces, parentheses, dashes, and ensures it starts with +
    private func normalizePhone(_ phone: String) -> String {
        // Remove all non-digit characters except +
        let digitsOnly = phone.filter { $0.isNumber || $0 == "+" }
        
        // If it already starts with +, return as is
        if digitsOnly.hasPrefix("+") {
            return digitsOnly
        }
        
        // If it's 10 digits, assume US number and prepend +1
        if digitsOnly.count == 10 {
            return "+1" + digitsOnly
        }
        
        // If it's 11 digits starting with 1, prepend +
        if digitsOnly.count == 11 && digitsOnly.hasPrefix("1") {
            return "+" + digitsOnly
        }
        
        // Otherwise, just prepend + to whatever we have
        return "+" + digitsOnly
    }
    
    func run() -> ContactsImportResult {
        logger.info("👤 ContactsImporter.run(): Starting contact import from system address book")
        
        // Check permission status first
        let status = CNContactStore.authorizationStatus(for: .contacts)
        logger.info("👤 ContactsImporter: Current permission status = \(status.rawValue)")
        
        if status == .notDetermined {
            logger.info("👤 ContactsImporter: Requesting Contacts permission...")
            let store = CNContactStore()
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            DispatchQueue.main.async {
                store.requestAccess(for: .contacts) { success, error in
                    if let error = error {
                        self.logger.error("❌ ContactsImporter: Permission request error: \(error.localizedDescription)")
                    }
                    granted = success
                    semaphore.signal()
                }
            }
            let waitResult = semaphore.wait(timeout: .now() + 120)
            if waitResult == .timedOut {
                logger.warning("⚠️ ContactsImporter: Contacts permission request timed out")
                return ContactsImportResult(totalRead: 0, totalInserted: 0, totalUpdated: 0)
            }
            if !granted {
                logger.warning("⚠️ ContactsImporter: Contacts permission denied by user")
                return ContactsImportResult(totalRead: 0, totalInserted: 0, totalUpdated: 0)
            }
            logger.info("✅ ContactsImporter: Contacts permission granted")
        } else if status != .authorized {
            logger.error("❌ ContactsImporter: Contacts permission denied or restricted (status=\(status.rawValue))")
            print("❌ ContactsImporter: Contacts permission denied or restricted")
            return ContactsImportResult(totalRead: 0, totalInserted: 0, totalUpdated: 0)
        }
        
        // Permission is granted, proceed with import
        logger.info("✅ ContactsImporter: Permission granted, starting import...")
        print("✅ ContactsImporter: Permission granted, starting import...")
        
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor
        ]

        var totalRead = 0
        var totalInserted = 0
        var totalUpdated = 0

        // Open database connection ONCE for all operations
        guard let db = try? CRMDatabase.shared.open() else {
            logger.error("❌ ContactsImporter: Failed to open database")
            return ContactsImportResult(totalRead: 0, totalInserted: 0, totalUpdated: 0)
        }
        defer { sqlite3_close(db) }
        
        // Ensure schema exists
        let dao = ContactsDAO()
        dao.ensureSchema(db: db)
        
        // Start a transaction for better performance and to avoid locks
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        
        let request = CNContactFetchRequest(keysToFetch: keys)
        do {
            try store.enumerateContacts(with: request) { c, _ in
                totalRead += 1
                
                let fullName = [c.givenName, c.familyName].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                let email = c.emailAddresses.first.map { String($0.value) }
                let appleId = c.identifier
                let validFirstName = c.givenName.trimmingCharacters(in: .whitespaces)
                let validLastName = c.familyName.trimmingCharacters(in: .whitespaces)
                let nickname = validFirstName.isEmpty ? nil : validFirstName
                let profilePhoto = c.thumbnailImageData ?? c.imageData
                
                var identifiers: [String] = []
                for phoneEntry in c.phoneNumbers {
                    let raw = phoneEntry.value.stringValue
                    guard !raw.isEmpty else { continue }
                    identifiers.append(self.normalizePhone(raw))
                }
                if identifiers.isEmpty, let emailAddress = c.emailAddresses.first {
                    identifiers.append(String(emailAddress.value))
                }
                
                if identifiers.isEmpty {
                    self.logger.info("⚠️ ContactsImporter: Skipping contact with no phone or email: \(fullName.isEmpty ? appleId : fullName)")
                    return
                }
                
                for identifier in identifiers {
                    let validName: String
                    if !fullName.isEmpty {
                        validName = fullName
                    } else if let email = email, !email.isEmpty {
                        validName = email
                    } else {
                        validName = identifier
                    }
                    
                    let beforeExists = dao.rowExistsPublic(db: db, phone: identifier)
                    dao.upsertWithConnection(db: db,
                                            phone: identifier,
                                            name: validName,
                                            firstName: validFirstName.isEmpty ? nil : validFirstName,
                                            lastName: validLastName.isEmpty ? nil : validLastName,
                                            email: email,
                                            appleContactID: appleId,
                                            profilePhotoData: profilePhoto,
                                            nickname: nickname)
                    if beforeExists { totalUpdated += 1 } else { totalInserted += 1 }
                }
            }
            
            // Commit the transaction
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
            
            logger.info("👤 ContactsImporter.run(): Successfully enumerated \(totalRead) contacts from address book")
        } catch {
            // Rollback on error
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            logger.error("❌ ContactsImporter: Failed to enumerate contacts: \(error.localizedDescription)")
            print("❌ ContactsImporter: Failed to enumerate contacts: \(error)")
        }

        logger.info("👤 ContactsImporter.run(): Import complete - read=\(totalRead), inserted=\(totalInserted), updated=\(totalUpdated)")
        return ContactsImportResult(totalRead: totalRead, totalInserted: totalInserted, totalUpdated: totalUpdated)
    }
    
    /// Import macOS Contacts groups to CRM (first run only)
    /// Should be called after contacts are imported
    func importMacOSGroups(dataProvider: SQLiteDataProvider) async {
        logger.info("🔄 ContactsImporter: Starting macOS groups import")
        
        // Check permission
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else {
            logger.warning("⚠️ ContactsImporter: No permission to import groups")
            return
        }
        
        do {
            let importedCount = try await GroupSyncService.shared.importMacOSGroupsToCRM(dataProvider: dataProvider)
            logger.info("✅ ContactsImporter: Imported \(importedCount) macOS groups to CRM")
        } catch {
            logger.error("❌ ContactsImporter: Failed to import macOS groups: \(error)")
        }
    }
}


