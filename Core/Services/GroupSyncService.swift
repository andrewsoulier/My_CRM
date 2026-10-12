import Foundation
import Contacts
import SQLite3

/// Service for syncing groups between CRM database and macOS Contacts app
@MainActor
final class GroupSyncService {
    static let shared = GroupSyncService()
    
    private let logger = LogManager.shared
    private let store = CNContactStore()
    
    private init() {}
    
    /// Fetch a macOS Contacts group by identifier
    private func fetchCNGroup(withIdentifier identifier: String) throws -> CNGroup {
        let predicate = CNGroup.predicateForGroups(withIdentifiers: [identifier])
        let groups = try store.groups(matching: predicate)
        guard let cnGroup = groups.first else {
            throw GroupSyncError.groupNotFound
        }
        return cnGroup
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
                logger.error("❌ GroupSyncService: Error requesting permission: \(error)")
                return false
            }
        }
        
        return false
    }
    
    /// Import all macOS Contacts groups to CRM (first run)
    /// Returns the number of groups imported
    func importMacOSGroupsToCRM(dataProvider: SQLiteDataProvider) async throws -> Int {
        logger.info("🔄 GroupSyncService: Starting import of macOS Contacts groups")
        
        guard hasPermission() else {
            logger.warning("⚠️ GroupSyncService: No permission to import groups")
            return 0
        }
        
        var importedCount = 0
        
        do {
            // Get all groups from macOS Contacts
            let groups = try store.groups(matching: nil)
            
            logger.info("📋 GroupSyncService: Found \(groups.count) macOS Contacts groups")
            
            for cnGroup in groups {
                // Skip default groups (like "All Contacts")
                if cnGroup.name.isEmpty {
                    continue
                }
                
                // Check if group already exists in CRM by macOSGroupID
                let existingGroup = await findCRMGroupByMacOSID(cnGroup.identifier, dataProvider: dataProvider)
                
                if existingGroup != nil {
                    logger.info("ℹ️ GroupSyncService: Group '\(cnGroup.name)' already exists in CRM, skipping")
                    continue
                }
                
                // Create new CRM group
                let crmGroup = ContactGroup(
                    name: cnGroup.name,
                    color: .blue,
                    isDeck: false
                )
                var newGroup = crmGroup
                newGroup.macOSGroupID = cnGroup.identifier
                
                // Save group to database
                do {
                    try await dataProvider.createGroup(newGroup)
                    logger.info("✅ GroupSyncService: Created CRM group: \(newGroup.name)")
                    
                    // Get contacts in this macOS group
                    let contacts = try store.unifiedContacts(matching: CNContact.predicateForContactsInGroup(withIdentifier: cnGroup.identifier), keysToFetch: [
                        CNContactIdentifierKey as CNKeyDescriptor,
                        CNContactPhoneNumbersKey as CNKeyDescriptor,
                        CNContactEmailAddressesKey as CNKeyDescriptor,
                    ])
                    
                    logger.info("👥 GroupSyncService: Found \(contacts.count) contacts in macOS group '\(cnGroup.name)'")
                    
                    // Add each contact to the CRM group
                    var addedCount = 0
                    for cnContact in contacts {
                        // Find contact in CRM by matching
                        if let crmContact = await findContactInCRM(cnContact: cnContact, dataProvider: dataProvider) {
                            do {
                                try await dataProvider.add(phones: [crmContact.phone], to: newGroup.id)
                                addedCount += 1
                            } catch {
                                logger.warning("⚠️ GroupSyncService: Failed to add contact \(crmContact.displayName) to group: \(error)")
                            }
                        }
                    }
                    
                    logger.info("✅ GroupSyncService: Added \(addedCount) contacts to CRM group '\(newGroup.name)'")
                    importedCount += 1
                } catch {
                    logger.error("❌ GroupSyncService: Failed to create CRM group '\(cnGroup.name)': \(error)")
                }
            }
            
            logger.info("✅ GroupSyncService: Import complete - \(importedCount) groups imported")
            return importedCount
        } catch {
            logger.error("❌ GroupSyncService: Error importing groups: \(error)")
            throw error
        }
    }
    
    /// Find CRM group by macOS Group ID
    private func findCRMGroupByMacOSID(_ macOSID: String, dataProvider: SQLiteDataProvider) async -> ContactGroup? {
        return dataProvider.groups.first { $0.macOSGroupID == macOSID }
    }
    
    /// Find contact in CRM by matching with macOS Contact
    private func findContactInCRM(cnContact: CNContact, dataProvider: SQLiteDataProvider) async -> Contact? {
        // Try by appleContactID first
        if let contact = dataProvider.contacts.first(where: { $0.appleContactID == cnContact.identifier }) {
            return contact
        }
        
        // Try by phone number
        if let phoneNumber = cnContact.phoneNumbers.first?.value.stringValue {
            let normalizedPhone = normalizePhone(phoneNumber)
            if let contact = dataProvider.contacts.first(where: { normalizePhone($0.phone) == normalizedPhone }) {
                return contact
            }
        }
        
        // Try by email
        if let email = cnContact.emailAddresses.first?.value as String? {
            if let contact = dataProvider.contacts.first(where: { $0.email?.lowercased() == email.lowercased() }) {
                return contact
            }
        }
        
        return nil
    }
    
    /// Normalize phone number for matching
    private func normalizePhone(_ phone: String) -> String {
        let digitsOnly = phone.filter { $0.isNumber || $0 == "+" }
        
        if digitsOnly.hasPrefix("+") {
            return digitsOnly
        }
        
        if digitsOnly.count == 10 {
            return "+1" + digitsOnly
        }
        
        if digitsOnly.count == 11 && digitsOnly.hasPrefix("1") {
            return "+" + digitsOnly
        }
        
        return "+" + digitsOnly
    }
    
    /// Create a macOS Contacts group from CRM group
    func createMacOSGroup(from group: ContactGroup) async throws -> String {
        guard hasPermission() else {
            throw GroupSyncError.noPermission
        }
        
        let saveRequest = CNSaveRequest()
        let cnGroup = CNMutableGroup()
        cnGroup.name = group.name
        
        saveRequest.add(cnGroup, toContainerWithIdentifier: nil)
        
        do {
            try store.execute(saveRequest)
            logger.info("✅ GroupSyncService: Created macOS group: \(group.name)")
            
            // Update CRM group with macOSGroupID
            await updateGroupMacOSID(groupID: group.id, macOSID: cnGroup.identifier)
            
            return cnGroup.identifier
        } catch {
            logger.error("❌ GroupSyncService: Failed to create macOS group '\(group.name)': \(error)")
            throw error
        }
    }
    
    /// Update macOS Contacts group name
    func updateMacOSGroup(_ group: ContactGroup) async throws {
        guard hasPermission() else {
            throw GroupSyncError.noPermission
        }
        
        guard let macOSID = group.macOSGroupID else {
            logger.warning("⚠️ GroupSyncService: Group '\(group.name)' has no macOSGroupID, cannot update")
            return
        }
        
        do {
            let cnGroup = try fetchCNGroup(withIdentifier: macOSID)
            let mutableGroup = cnGroup.mutableCopy() as! CNMutableGroup
            mutableGroup.name = group.name
            
            let saveRequest = CNSaveRequest()
            saveRequest.update(mutableGroup)
            
            try store.execute(saveRequest)
            logger.info("✅ GroupSyncService: Updated macOS group: \(group.name)")
        } catch {
            logger.error("❌ GroupSyncService: Failed to update macOS group '\(group.name)': \(error)")
            throw error
        }
    }
    
    /// Delete macOS Contacts group
    func deleteMacOSGroup(macOSGroupID: String) async throws {
        guard hasPermission() else {
            throw GroupSyncError.noPermission
        }
        
        do {
            let cnGroup = try fetchCNGroup(withIdentifier: macOSGroupID)
            let mutableGroup = cnGroup.mutableCopy() as! CNMutableGroup
            let saveRequest = CNSaveRequest()
            saveRequest.delete(mutableGroup)
            
            try store.execute(saveRequest)
            logger.info("✅ GroupSyncService: Deleted macOS group: \(macOSGroupID)")
        } catch {
            logger.error("❌ GroupSyncService: Failed to delete macOS group '\(macOSGroupID)': \(error)")
            throw error
        }
    }
    
    /// Sync group membership (add/remove contacts from macOS group)
    func syncGroupMembership(_ group: ContactGroup, dataProvider: SQLiteDataProvider) async throws {
        guard hasPermission() else {
            throw GroupSyncError.noPermission
        }
        
        guard let macOSID = group.macOSGroupID else {
            logger.warning("⚠️ GroupSyncService: Group '\(group.name)' has no macOSGroupID, creating macOS group first")
            // Create the group first
            let newMacOSID = try await createMacOSGroup(from: group)
            // Update the group in memory
            var updatedGroup = group
            updatedGroup.macOSGroupID = newMacOSID
            // Continue with membership sync
            return try await syncGroupMembership(updatedGroup, dataProvider: dataProvider)
        }
        
        // Get current contacts in macOS group
        let currentMacOSContacts = try store.unifiedContacts(
            matching: CNContact.predicateForContactsInGroup(withIdentifier: macOSID),
            keysToFetch: [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
            ]
        )
        
        // Get CRM contacts that should be in the group
        let crmContactPhones = Set(group.memberPhones)
        var crmContacts: [Contact] = []
        for phone in crmContactPhones {
            if let contact = dataProvider.contacts.first(where: { $0.phone == phone }) {
                crmContacts.append(contact)
            }
        }
        
        // Find macOS contacts for CRM group members
        var contactsToAdd: [CNContact] = []
        var contactsToRemove: [CNContact] = []
        
        // Find contacts that need to be added
        for crmContact in crmContacts {
            var found = false
            for cnContact in currentMacOSContacts {
                if matchesContact(crmContact: crmContact, cnContact: cnContact) {
                    found = true
                    break
                }
            }
            if !found {
                // Need to find the macOS contact for this CRM contact
                if let cnContact = try await findMacOSContact(for: crmContact) {
                    contactsToAdd.append(cnContact)
                }
            }
        }
        
        // Find contacts that need to be removed (in macOS but not in CRM group)
        for cnContact in currentMacOSContacts {
            var shouldKeep = false
            for crmContact in crmContacts {
                if matchesContact(crmContact: crmContact, cnContact: cnContact) {
                    shouldKeep = true
                    break
                }
            }
            if !shouldKeep {
                contactsToRemove.append(cnContact)
            }
        }
        
        // Apply changes
        if !contactsToAdd.isEmpty || !contactsToRemove.isEmpty {
            let saveRequest = CNSaveRequest()
            let cnGroup = try fetchCNGroup(withIdentifier: macOSID)
            
            for contact in contactsToAdd {
                saveRequest.addMember(contact, to: cnGroup)
            }
            
            for contact in contactsToRemove {
                saveRequest.removeMember(contact, from: cnGroup)
            }
            
            try store.execute(saveRequest)
            
            logger.info("✅ GroupSyncService: Synced membership for '\(group.name)' - Added: \(contactsToAdd.count), Removed: \(contactsToRemove.count)")
        }
    }
    
    /// Check if CRM contact matches macOS contact
    private func matchesContact(crmContact: Contact, cnContact: CNContact) -> Bool {
        // Match by appleContactID
        if let appleID = crmContact.appleContactID, appleID == cnContact.identifier {
            return true
        }
        
        // Match by phone
        if let phoneNumber = cnContact.phoneNumbers.first?.value.stringValue {
            let normalizedPhone = normalizePhone(phoneNumber)
            if normalizePhone(crmContact.phone) == normalizedPhone {
                return true
            }
        }
        
        // Match by email
        if let email = cnContact.emailAddresses.first?.value as String?,
           let crmEmail = crmContact.email,
           email.lowercased() == crmEmail.lowercased() {
            return true
        }
        
        return false
    }
    
    /// Find macOS contact for CRM contact
    private func findMacOSContact(for contact: Contact) async throws -> CNContact? {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        
        // Try by appleContactID
        if let appleID = contact.appleContactID, !appleID.isEmpty {
            do {
                return try store.unifiedContact(withIdentifier: appleID, keysToFetch: keys)
            } catch {
                // Not found, continue
            }
        }
        
        // Try by phone
        if !contact.phone.isEmpty {
            let normalizedPhone = normalizePhone(contact.phone)
            let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: normalizedPhone))
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            if let found = contacts.first {
                return found
            }
        }
        
        // Try by email
        if let email = contact.email, !email.isEmpty {
            let predicate = CNContact.predicateForContacts(matchingEmailAddress: email)
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            if let found = contacts.first {
                return found
            }
        }
        
        return nil
    }
    
    /// Update macOSGroupID in database
    private func updateGroupMacOSID(groupID: UUID, macOSID: String) async {
        guard let db = try? CRMDatabase.shared.open() else {
            logger.error("❌ GroupSyncService: Failed to open database to update macOSGroupID")
            return
        }
        defer { sqlite3_close(db) }
        
        let sql = "UPDATE groups SET macos_group_id = ? WHERE id = ?"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, macOSID, -1, SQLITE_TRANSIENT)
            let groupIDString = groupID.uuidString
            sqlite3_bind_text(statement, 2, groupIDString, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                logger.info("✅ GroupSyncService: Updated macOSGroupID for group: \(groupID)")
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                logger.error("❌ GroupSyncService: Failed to update macOSGroupID: \(errorMessage)")
            }
        }
        
        sqlite3_finalize(statement)
    }
    
    /// Sync a group to macOS Contacts (create or update)
    func syncGroupToMacOS(_ group: ContactGroup, dataProvider: SQLiteDataProvider) async throws -> Bool {
        guard hasPermission() else {
            logger.warning("⚠️ GroupSyncService: No permission to sync group: \(group.name)")
            return false
        }
        
        if let macOSID = group.macOSGroupID {
            // Group exists, update it
            try await updateMacOSGroup(group)
            // Sync membership
            try await syncGroupMembership(group, dataProvider: dataProvider)
        } else {
            // Group doesn't exist, create it
            let macOSID = try await createMacOSGroup(from: group)
            // Update group in memory with macOSID
            var updatedGroup = group
            updatedGroup.macOSGroupID = macOSID
            // Sync membership
            try await syncGroupMembership(updatedGroup, dataProvider: dataProvider)
        }
        
        return true
    }
}

enum GroupSyncError: Error {
    case noPermission
    case groupNotFound
    case contactNotFound
}


