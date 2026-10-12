import Foundation
import Contacts
import SQLite3

/// Service for syncing contacts between CRM database and macOS Contacts app
@MainActor
final class ContactSyncService {
    static let shared = ContactSyncService()
    
    private let logger = LogManager.shared
    private let store = CNContactStore()
    
    private init() {}
    
    /// Normalize phone number for matching (same as ContactsImporter)
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
    
    /// Check if we have permission to access Contacts
    func hasPermission() -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        return status == .authorized
    }
    
    /// Request permission to access Contacts
    func requestPermission() async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        
        if status == .authorized {
            return true
        }
        
        if status == .notDetermined {
            do {
                return try await store.requestAccess(for: .contacts)
            } catch {
                logger.error("❌ ContactSyncService: Error requesting permission: \(error)")
                return false
            }
        }
        
        return false
    }
    
    /// Find existing contact in macOS Contacts using matching strategies
    /// Strategy 1: appleContactID (if stored)
    /// Strategy 2: Phone number (normalized)
    /// Strategy 3: Email address
    func findExistingContact(for contact: Contact) async throws -> CNContact? {
        guard hasPermission() else {
            logger.warning("⚠️ ContactSyncService: No permission to access Contacts")
            return nil
        }
        
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        
        // Strategy 1: Try appleContactID first (most reliable)
        if let appleID = contact.appleContactID, !appleID.isEmpty {
            do {
                let cnContact = try store.unifiedContact(withIdentifier: appleID, keysToFetch: keys)
                logger.info("✅ ContactSyncService: Found contact by appleContactID: \(appleID)")
                return cnContact
            } catch {
                // Contact not found by ID, continue to other strategies
                logger.info("ℹ️ ContactSyncService: Contact not found by appleContactID: \(appleID)")
            }
        }
        
        // Strategy 2: Try phone number (normalized)
        if !contact.phone.isEmpty {
            let normalizedPhone = normalizePhone(contact.phone)
            let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: normalizedPhone))
            
            do {
                let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
                if let found = contacts.first {
                    logger.info("✅ ContactSyncService: Found contact by phone: \(normalizedPhone)")
                    return found
                }
            } catch {
                logger.warning("⚠️ ContactSyncService: Error searching by phone: \(error)")
            }
        }
        
        // Strategy 3: Try email address
        if let email = contact.email, !email.isEmpty {
            let predicate = CNContact.predicateForContacts(matchingEmailAddress: email)
            
            do {
                let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
                if let found = contacts.first {
                    logger.info("✅ ContactSyncService: Found contact by email: \(email)")
                    return found
                }
            } catch {
                logger.warning("⚠️ ContactSyncService: Error searching by email: \(error)")
            }
        }
        
        logger.info("ℹ️ ContactSyncService: No matching contact found for: \(contact.displayName)")
        return nil
    }
    
    /// Create a new CNMutableContact from CRM Contact
    func createMacOSContact(from contact: Contact) -> CNMutableContact {
        let cnContact = CNMutableContact()
        
        // Name fields
        cnContact.givenName = contact.firstName ?? ""
        cnContact.familyName = contact.lastName ?? ""
        cnContact.nickname = contact.nickname ?? ""
        
        // If no first/last name, use the name field
        if cnContact.givenName.isEmpty && cnContact.familyName.isEmpty {
            let nameParts = contact.name.components(separatedBy: " ")
            if nameParts.count > 1 {
                cnContact.givenName = nameParts[0]
                cnContact.familyName = nameParts.dropFirst().joined(separator: " ")
            } else {
                cnContact.givenName = contact.name
            }
        }
        
        // Phone number
        if !contact.phone.isEmpty {
            let phoneNumber = CNLabeledValue(
                label: CNLabelPhoneNumberMobile,
                value: CNPhoneNumber(stringValue: contact.phone)
            )
            cnContact.phoneNumbers = [phoneNumber]
        }
        
        // Email
        if let email = contact.email, !email.isEmpty {
            let emailValue = CNLabeledValue(
                label: CNLabelWork,
                value: email as NSString
            )
            cnContact.emailAddresses = [emailValue]
        }
        
        // Address (parse from string)
        if let address = contact.address, !address.isEmpty {
            let mutablePostal = CNMutablePostalAddress()
            mutablePostal.street = address
            let addressValue = CNLabeledValue(
                label: CNLabelHome,
                value: mutablePostal as CNPostalAddress
            )
            cnContact.postalAddresses = [addressValue]
        }
        
        // Photo
        if let photoData = contact.profilePhotoData {
            cnContact.imageData = photoData
        }
        
        // Notes
        if let notes = contact.notes, !notes.isEmpty {
            cnContact.note = notes
        }
        
        // Organization
        if let business = contact.business, !business.isEmpty {
            cnContact.organizationName = business
        }
        
        // Birthday
        if let birthday = contact.birthday {
            var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: birthday)
            cnContact.birthday = dateComponents
        }
        
        return cnContact
    }
    
    /// Update an existing CNContact with CRM Contact data
    func updateMacOSContact(_ cnContact: CNContact, with contact: Contact) -> CNMutableContact {
        let mutableContact = cnContact.mutableCopy() as! CNMutableContact
        
        // Update name fields
        if let firstName = contact.firstName, !firstName.isEmpty {
            mutableContact.givenName = firstName
        }
        if let lastName = contact.lastName, !lastName.isEmpty {
            mutableContact.familyName = lastName
        }
        if let nickname = contact.nickname, !nickname.isEmpty {
            mutableContact.nickname = nickname
        }
        
        // Update phone (replace if exists, add if not)
        if !contact.phone.isEmpty {
            let phoneNumber = CNLabeledValue(
                label: CNLabelPhoneNumberMobile,
                value: CNPhoneNumber(stringValue: contact.phone)
            )
            mutableContact.phoneNumbers = [phoneNumber]
        }
        
        // Update email (replace if exists, add if not)
        if let email = contact.email, !email.isEmpty {
            let emailValue = CNLabeledValue(
                label: CNLabelWork,
                value: email as NSString
            )
            mutableContact.emailAddresses = [emailValue]
        }
        
        // Update address
        if let address = contact.address, !address.isEmpty {
            let mutablePostal = CNMutablePostalAddress()
            mutablePostal.street = address
            let addressValue = CNLabeledValue(
                label: CNLabelHome,
                value: mutablePostal as CNPostalAddress
            )
            mutableContact.postalAddresses = [addressValue]
        }
        
        // Update photo
        if let photoData = contact.profilePhotoData {
            mutableContact.imageData = photoData
        }
        
        // Update notes
        if let notes = contact.notes, !notes.isEmpty {
            mutableContact.note = notes
        }
        
        // Update organization
        if let business = contact.business, !business.isEmpty {
            mutableContact.organizationName = business
        }
        
        // Update birthday
        if let birthday = contact.birthday {
            var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: birthday)
            mutableContact.birthday = dateComponents
        }
        
        return mutableContact
    }
    
    /// Sync a single contact to macOS Contacts
    /// Returns true if successful, false otherwise
    func syncContactToMacOS(_ contact: Contact) async throws -> Bool {
        // Check permission
        guard hasPermission() else {
            logger.warning("⚠️ ContactSyncService: No permission to sync contact: \(contact.displayName)")
            return false
        }
        
        // Find existing contact
        let existingContact = try await findExistingContact(for: contact)
        
        let saveRequest = CNSaveRequest()
        var appleContactID: String?
        
        if let existing = existingContact {
            // Update existing contact
            let mutableContact = updateMacOSContact(existing, with: contact)
            saveRequest.update(mutableContact)
            appleContactID = existing.identifier
            logger.info("📝 ContactSyncService: Updating contact: \(contact.displayName)")
        } else {
            // Create new contact
            let newContact = createMacOSContact(from: contact)
            saveRequest.add(newContact, toContainerWithIdentifier: nil)
            logger.info("➕ ContactSyncService: Creating new contact: \(contact.displayName)")
        }
        
        // Execute save
        do {
            try store.execute(saveRequest)
            
            // If we created a new contact, we need to fetch it again to get the identifier
            if appleContactID == nil {
                if let found = try await findExistingContact(for: contact) {
                    appleContactID = found.identifier
                }
            }
            
            // Update database with appleContactID if we have it
            if let appleID = appleContactID, !appleID.isEmpty {
                await updateContactAppleID(phone: contact.phone, appleID: appleID)
            }
            
            logger.info("✅ ContactSyncService: Successfully synced contact: \(contact.displayName)")
            return true
        } catch {
            logger.error("❌ ContactSyncService: Failed to sync contact \(contact.displayName): \(error)")
            throw error
        }
    }
    
    /// Update appleContactID in database
    private func updateContactAppleID(phone: String, appleID: String) async {
        guard let db = try? CRMDatabase.shared.open() else {
            logger.error("❌ ContactSyncService: Failed to open database to update appleContactID")
            return
        }
        defer { sqlite3_close(db) }
        
        let sql = "UPDATE contacts SET apple_contact_id = ? WHERE phone = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, appleID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, phone, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                logger.info("✅ ContactSyncService: Updated appleContactID for phone: \(phone)")
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                logger.error("❌ ContactSyncService: Failed to update appleContactID: \(errorMessage)")
            }
        }
        
        sqlite3_finalize(statement)
    }
    
    /// Sync all contacts (for initial sync on app start)
    func syncAllContacts(contacts: [Contact]) async {
        logger.info("🔄 ContactSyncService: Starting full contact sync (\(contacts.count) contacts)")
        
        guard hasPermission() else {
            logger.warning("⚠️ ContactSyncService: No permission for full sync")
            return
        }
        
        var successCount = 0
        var failureCount = 0
        
        for contact in contacts {
            do {
                let success = try await syncContactToMacOS(contact)
                if success {
                    successCount += 1
                } else {
                    failureCount += 1
                }
            } catch {
                logger.error("❌ ContactSyncService: Error syncing contact \(contact.displayName): \(error)")
                failureCount += 1
            }
        }
        
        logger.info("✅ ContactSyncService: Full sync complete - Success: \(successCount), Failed: \(failureCount)")
    }
}


