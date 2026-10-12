import Foundation
import SwiftUI
import Combine

@MainActor
class ContactsViewModel: ObservableObject {
    @Published var allContacts: [Contact] = []
    @Published var displayedContacts: [Contact] = []
    @Published var isLoading = false
    @Published var searchResults: [Contact] = []
    @Published var isInitialLoadComplete = false
    
    private let logger = LogManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        print("🚨 ContactsViewModel.init() called")
    }
    
    func loadContacts(from dataProvider: SQLiteDataProvider, sortOption: ContactFilter.ContactSortOption) async {
        guard !isLoading else { 
            logger.warning("🚫 ContactsViewModel: Already loading, skipping...")
            return 
        }
        
        logger.info("🔄 ContactsViewModel: Starting to load contacts...")
        isLoading = true
        
        do {
            // First ensure the database is loaded
            if !dataProvider.isConnectedToDatabase {
                logger.warning("🔌 ContactsViewModel: Database not connected, attempting connection...")
                let databasePath = SettingsManager.shared.settings.database.path
                logger.info("🔌 ContactsViewModel: Using database path: \(databasePath)")
                try await dataProvider.connectToDatabase(path: databasePath)
            }
            
            // Now use contacts loaded in the data provider (no reload needed - observer handles sync)
            let allLoadedContacts = dataProvider.contacts
            logger.info("📦 ContactsViewModel: Using \(allLoadedContacts.count) contacts from data provider")
            
            if allLoadedContacts.isEmpty {
                logger.error("⚠️ ContactsViewModel: No contacts found in data provider!")
            } else {
                logger.info("✅ ContactsViewModel: Found \(allLoadedContacts.count) contacts in data provider")
                logger.info("📱 ContactsViewModel: First contact in data provider: \(allLoadedContacts.first?.displayName ?? "nil")")
                
                // Debug: Check if contacts have valid data
                for (index, contact) in allLoadedContacts.prefix(3).enumerated() {
                    logger.info("📱 ContactsViewModel: Contact \(index): name='\(contact.displayName)', phone='\(contact.phone)', id='\(contact.id)'")
                }
            }
            
            // Apply sorting to the loaded contacts
            var sortedContacts = allLoadedContacts
            logger.info("🔄 ContactsViewModel: Applying sort option: \(sortOption)")
            logger.info("🔄 ContactsViewModel: Before sorting - sortedContacts count: \(sortedContacts.count)")
            
            switch sortOption {
            case .name:
                sortedContacts.sort { contact1, contact2 in
                    let name1 = contact1.displayName.isEmpty ? "no name saved" : contact1.displayName
                    let name2 = contact2.displayName.isEmpty ? "no name saved" : contact2.displayName
                    
                    // Check if names start with letters
                    let isLetter1 = name1.first?.isLetter == true
                    let isLetter2 = name2.first?.isLetter == true
                    
                    // If both are letters or both are non-letters, sort normally
                    if isLetter1 == isLetter2 {
                        return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
                    }
                    
                    // Letters come before non-letters
                    return isLetter1
                }
                logger.debug("🔄 ContactsViewModel: Sorted by name (A-Z, then numbers/special)")
                
            case .recent:
                sortedContacts.sort { contact1, contact2 in
                    let date1 = contact1.lastMessageDate ?? Date.distantPast
                    let date2 = contact2.lastMessageDate ?? Date.distantPast
                    return date1 > date2 // Most recent first
                }
                logger.debug("🔄 ContactsViewModel: Sorted by recent (last_message_date)")
                
            case .company:
                sortedContacts.sort { contact1, contact2 in
                    let company1 = contact1.business ?? ""
                    let company2 = contact2.business ?? ""
                    
                    // Check if companies start with letters
                    let isLetter1 = company1.first?.isLetter == true
                    let isLetter2 = company2.first?.isLetter == true
                    
                    // If both are letters or both are non-letters, sort normally
                    if isLetter1 == isLetter2 {
                        return company1.localizedCaseInsensitiveCompare(company2) == .orderedAscending
                    }
                    
                    // Letters come before non-letters, empty at the bottom
                    if company1.isEmpty && !company2.isEmpty {
                        return false
                    }
                    if !company1.isEmpty && company2.isEmpty {
                        return true
                    }
                    
                    return isLetter1
                }
                logger.debug("🔄 ContactsViewModel: Sorted by company (A-Z, then numbers/special, empty at bottom)")
                
            case .tags:
                sortedContacts.sort { contact1, contact2 in
                    let tag1 = contact1.contactGroup ?? ""
                    let tag2 = contact2.contactGroup ?? ""
                    
                    // Check if tags start with letters
                    let isLetter1 = tag1.first?.isLetter == true
                    let isLetter2 = tag2.first?.isLetter == true
                    
                    // If both are letters or both are non-letters, sort normally
                    if isLetter1 == isLetter2 {
                        return tag1.localizedCaseInsensitiveCompare(tag2) == .orderedAscending
                    }
                    
                    // Letters come before non-letters, empty at the bottom
                    if tag1.isEmpty && !tag2.isEmpty {
                        return false
                    }
                    if !tag1.isEmpty && tag2.isEmpty {
                        return true
                    }
                    
                    return isLetter1
                }
                logger.debug("🔄 ContactsViewModel: Sorted by tags (A-Z, then numbers/special, empty at bottom)")
            }
            
            logger.info("🔄 ContactsViewModel: Sorting completed, sorted contacts count: \(sortedContacts.count)")
            
            // Debug: Check first few contacts after sorting
            for (index, contact) in sortedContacts.prefix(3).enumerated() {
                logger.info("📱 ContactsViewModel: After sorting - Contact \(index): name='\(contact.displayName)', phone='\(contact.phone)', id='\(contact.id)'")
            }
            
            // Update state variables
            logger.info("🔄 ContactsViewModel: Updating state with \(sortedContacts.count) contacts")
            logger.info("🔄 ContactsViewModel: Before update - allContacts: \(self.allContacts.count), displayedContacts: \(self.displayedContacts.count)")
            
            if sortedContacts.isEmpty {
                logger.warning("ℹ️ ContactsViewModel: No contacts found in database")
            } else {
                logger.info("✅ ContactsViewModel: Loaded \(sortedContacts.count) contacts")
                logger.info("📱 ContactsViewModel: First contact: \(sortedContacts.first?.displayName ?? "nil")")
            }
            
            // Load all contacts at once (no pagination)
            logger.info("🔍 ContactsViewModel: Loading all \(sortedContacts.count) contacts at once")
            
            // Update state variables one by one with logging
            logger.info("🔍 ContactsViewModel: Setting allContacts to \(sortedContacts.count)")
            self.allContacts = sortedContacts
            logger.info("🔍 ContactsViewModel: allContacts after assignment: \(self.allContacts.count)")
            
            logger.info("🔍 ContactsViewModel: Setting displayedContacts to \(sortedContacts.count)")
            self.displayedContacts = sortedContacts
            logger.info("🔍 ContactsViewModel: displayedContacts after assignment: \(self.displayedContacts.count)")
            
            self.isLoading = false
            self.isInitialLoadComplete = true
            
            // Debug logging
            logger.info("🔍 ContactsViewModel: Final state - allContacts: \(self.allContacts.count), displayedContacts: \(self.displayedContacts.count), isLoading: \(self.isLoading)")
            logger.info("🔍 ContactsViewModel: isInitialLoadComplete: \(self.isInitialLoadComplete)")
            
        } catch {
            logger.error("❌ ContactsViewModel: Failed to load contacts: \(error.localizedDescription)")
            logger.error("❌ ContactsViewModel: Error details: \(error)")
            isLoading = false
        }
    }
    
    /// Filter out contacts that are currently in the canvas from displayed contacts
    func filterCanvasContacts(canvasContactPhones: Set<String>) {
        displayedContacts = allContacts.filter { contact in
            !canvasContactPhones.contains(contact.phone)
        }
        
        // Trigger view refresh to ensure UI updates immediately
        objectWillChange.send()
    }
    
    /// Check if a contact is currently in the canvas
    func isContactInCanvas(_ contact: Contact, canvasContactPhones: Set<String>) -> Bool {
        return canvasContactPhones.contains(contact.phone)
    }
    
    /// Sync with data provider without reloading from database
    /// This is called after database changes to update the view model's cached data
    func syncWithDataProvider(_ dataProvider: SQLiteDataProvider, sortOption: ContactFilter.ContactSortOption) {
        logger.info("🔄 ContactsViewModel: Syncing with data provider (no database reload)...")
        
        // Get the current contacts from the data provider
        let currentContacts = dataProvider.contacts
        logger.info("📦 ContactsViewModel: Syncing \(currentContacts.count) contacts from data provider")
        
        // Apply the same sorting logic as loadContacts
        var sortedContacts = currentContacts
        
        switch sortOption {
        case .name:
            sortedContacts.sort { contact1, contact2 in
                let name1 = contact1.displayName.isEmpty ? "no name saved" : contact1.displayName
                let name2 = contact2.displayName.isEmpty ? "no name saved" : contact2.displayName
                
                let isLetter1 = name1.first?.isLetter == true
                let isLetter2 = name2.first?.isLetter == true
                
                if isLetter1 == isLetter2 {
                    return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
                }
                
                return isLetter1
            }
            
        case .recent:
            sortedContacts.sort { contact1, contact2 in
                let date1 = contact1.lastMessageDate ?? Date.distantPast
                let date2 = contact2.lastMessageDate ?? Date.distantPast
                return date1 > date2
            }
            
        case .company:
            sortedContacts.sort { contact1, contact2 in
                let company1 = contact1.business ?? ""
                let company2 = contact2.business ?? ""
                
                let isLetter1 = company1.first?.isLetter == true
                let isLetter2 = company2.first?.isLetter == true
                
                if isLetter1 == isLetter2 {
                    return company1.localizedCaseInsensitiveCompare(company2) == .orderedAscending
                }
                
                if company1.isEmpty && !company2.isEmpty {
                    return false
                }
                if !company1.isEmpty && company2.isEmpty {
                    return true
                }
                
                return isLetter1
            }
            
        case .tags:
            sortedContacts.sort { contact1, contact2 in
                let tag1 = contact1.contactGroup ?? ""
                let tag2 = contact2.contactGroup ?? ""
                
                let isLetter1 = tag1.first?.isLetter == true
                let isLetter2 = tag2.first?.isLetter == true
                
                if isLetter1 == isLetter2 {
                    return tag1.localizedCaseInsensitiveCompare(tag2) == .orderedAscending
                }
                
                if tag1.isEmpty && !tag2.isEmpty {
                    return false
                }
                if !tag1.isEmpty && tag2.isEmpty {
                    return true
                }
                
                return isLetter1
            }
        }
        
        // Force SwiftUI to recognize the change
        objectWillChange.send()
        
        // Update local state
        self.allContacts = sortedContacts
        self.displayedContacts = sortedContacts
        
        // Force another update after assignment
        objectWillChange.send()
        
        logger.info("✅ ContactsViewModel: Synced - allContacts: \(self.allContacts.count), displayedContacts: \(self.displayedContacts.count)")
    }
    
    /// Async version of syncWithDataProvider - only copies data, no DB operations
    /// This prevents infinite loops by never triggering database reloads
    func syncFromProvider(_ dataProvider: SQLiteDataProvider, sortOption: ContactFilter.ContactSortOption) async {
        guard !isLoading else {
            logger.info("🚫 ContactsViewModel: Already loading, skipping sync...")
            return
        }
        
        logger.info("🔄 ContactsViewModel: syncFromProvider called (async, no DB reload)")
        
        // Just copy the data that's already loaded in dataProvider
        let allLoadedContacts = dataProvider.contacts
        logger.info("📦 ContactsViewModel: Syncing \(allLoadedContacts.count) contacts from provider")
        
        // Apply sorting
        var sortedContacts = allLoadedContacts
        
        switch sortOption {
        case .name:
            sortedContacts.sort { contact1, contact2 in
                let name1 = contact1.displayName.isEmpty ? "no name saved" : contact1.displayName
                let name2 = contact2.displayName.isEmpty ? "no name saved" : contact2.displayName
                
                let isLetter1 = name1.first?.isLetter == true
                let isLetter2 = name2.first?.isLetter == true
                
                if isLetter1 == isLetter2 {
                    return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
                }
                
                return isLetter1
            }
            
        case .recent:
            sortedContacts.sort { contact1, contact2 in
                let date1 = contact1.lastMessageDate ?? Date.distantPast
                let date2 = contact2.lastMessageDate ?? Date.distantPast
                return date1 > date2
            }
            
        case .company:
            sortedContacts.sort { contact1, contact2 in
                let company1 = contact1.business ?? ""
                let company2 = contact2.business ?? ""
                
                let isLetter1 = company1.first?.isLetter == true
                let isLetter2 = company2.first?.isLetter == true
                
                if isLetter1 == isLetter2 {
                    return company1.localizedCaseInsensitiveCompare(company2) == .orderedAscending
                }
                
                if company1.isEmpty && !company2.isEmpty {
                    return false
                }
                if !company1.isEmpty && company2.isEmpty {
                    return true
                }
                
                return isLetter1
            }
            
        case .tags:
            sortedContacts.sort { contact1, contact2 in
                let tag1 = contact1.contactGroup ?? ""
                let tag2 = contact2.contactGroup ?? ""
                
                let isLetter1 = tag1.first?.isLetter == true
                let isLetter2 = tag2.first?.isLetter == true
                
                if isLetter1 == isLetter2 {
                    return tag1.localizedCaseInsensitiveCompare(tag2) == .orderedAscending
                }
                
                if tag1.isEmpty && !tag2.isEmpty {
                    return false
                }
                if !tag1.isEmpty && tag2.isEmpty {
                    return true
                }
                
                return isLetter1
            }
        }
        
        // Update state on main actor
        await MainActor.run {
            self.allContacts = sortedContacts
            self.displayedContacts = sortedContacts
            self.isInitialLoadComplete = true
        }
        
        logger.info("✅ ContactsViewModel: syncFromProvider completed - allContacts: \(self.allContacts.count), displayedContacts: \(self.displayedContacts.count)")
    }
    
    /// Set up observer to automatically sync when dataProvider.contacts changes
    /// This creates a one-way data flow: dataProvider → ViewModel (no loops)
    func setupDataProviderObserver(_ dataProvider: SQLiteDataProvider, sortOption: ContactFilter.ContactSortOption) {
        logger.info("🔌 ContactsViewModel: Setting up dataProvider observer...")
        
        dataProvider.$contacts
            .sink { [weak self] newContacts in
                guard let self = self else { return }
                if !self.isLoading {
                    self.logger.info("🔔 ContactsViewModel: dataProvider.contacts changed (\(newContacts.count) contacts), triggering sync...")
                    Task {
                        await self.syncFromProvider(dataProvider, sortOption: sortOption)
                    }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .importSyncCompleted)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if !self.isLoading {
                    Task {
                        await self.syncFromProvider(dataProvider, sortOption: sortOption)
                    }
                }
            }
            .store(in: &cancellables)
        
        logger.info("✅ ContactsViewModel: dataProvider observer setup complete")
    }

}
