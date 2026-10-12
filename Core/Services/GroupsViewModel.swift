import Foundation
import SwiftUI
import Combine

@MainActor
class GroupsViewModel: ObservableObject {
    @Published var allGroups: [ContactGroup] = []
    @Published var displayedGroups: [ContactGroup] = []
    @Published var isLoading = false
    @Published var searchResults: [ContactGroup] = []
    @Published var isInitialLoadComplete = false
    
    private let logger = LogManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        print("🚨 GroupsViewModel.init() called")
    }
    
    func loadGroups(from dataProvider: SQLiteDataProvider) async {
        guard !isLoading else { 
            logger.warning("🚫 GroupsViewModel: Already loading, skipping...")
            return 
        }
        
        logger.info("🔄 GroupsViewModel: Starting to load groups...")
        isLoading = true
        
        do {
            // First ensure the database is loaded
            if !dataProvider.isConnectedToDatabase {
                logger.warning("🔌 GroupsViewModel: Database not connected, attempting connection...")
                let databasePath = "/Users/andrewsoulier/My_CRM Project/my_crm.db"
                logger.info("🔌 GroupsViewModel: Using database path: \(databasePath)")
                try await dataProvider.connectToDatabase(path: databasePath)
            }
            
            // Now use groups loaded in the data provider (no reload needed - observer handles sync)
            let allLoadedGroups = dataProvider.groups
            logger.info("📦 GroupsViewModel: Using \(allLoadedGroups.count) groups from data provider")
            
            if allLoadedGroups.isEmpty {
                logger.warning("⚠️ GroupsViewModel: No groups found in data provider!")
            } else {
                logger.info("✅ GroupsViewModel: Found \(allLoadedGroups.count) groups in data provider")
                logger.info("👥 GroupsViewModel: First group in data provider: \(allLoadedGroups.first?.name ?? "nil")")
                
                // Debug: Check if groups have valid data
                for (index, group) in allLoadedGroups.prefix(3).enumerated() {
                    logger.info("👥 GroupsViewModel: Group \(index): name='\(group.name)', id='\(group.id)', members=\(group.memberCount)")
                }
            }
            
            // Apply default sorting (Recently Updated)
            var sortedGroups = allLoadedGroups
            logger.info("🔄 GroupsViewModel: Applying default sort by recently updated")
            logger.info("🔄 GroupsViewModel: Before sorting - sortedGroups count: \(sortedGroups.count)")
            
            // Sort by recently created (most recent first)
            sortedGroups.sort { (group1: ContactGroup, group2: ContactGroup) in
                return group1.createdAt > group2.createdAt
            }
            
            logger.info("🔄 GroupsViewModel: Sorting completed, sorted groups count: \(sortedGroups.count)")
            
            // Debug: Check first few groups after sorting
            for (index, group) in sortedGroups.prefix(3).enumerated() {
                logger.info("👥 GroupsViewModel: After sorting - Group \(index): name='\(group.name)', id='\(group.id)', members=\(group.memberCount)")
            }
            
            // Update state variables
            logger.info("🔄 GroupsViewModel: Updating state with \(sortedGroups.count) groups")
            logger.info("🔄 GroupsViewModel: Before update - allGroups: \(self.allGroups.count), displayedGroups: \(self.displayedGroups.count)")
            
            if sortedGroups.isEmpty {
                logger.warning("ℹ️ GroupsViewModel: No groups found in database")
            } else {
                logger.info("✅ GroupsViewModel: Loaded \(sortedGroups.count) groups")
                logger.info("👥 GroupsViewModel: First group: \(sortedGroups.first?.name ?? "nil")")
            }
            
            // Load all groups at once (no pagination)
            logger.info("🔍 GroupsViewModel: Loading all \(sortedGroups.count) groups at once")
            
            // Update state variables one by one with logging
            logger.info("🔍 GroupsViewModel: Setting allGroups to \(sortedGroups.count)")
            self.allGroups = sortedGroups
            logger.info("🔍 GroupsViewModel: allGroups after assignment: \(self.allGroups.count)")
            
            logger.info("🔍 GroupsViewModel: Setting displayedGroups to \(sortedGroups.count)")
            self.displayedGroups = sortedGroups
            logger.info("🔍 GroupsViewModel: displayedGroups after assignment: \(self.displayedGroups.count)")
            
            self.isLoading = false
            self.isInitialLoadComplete = true
            
            // Debug logging
            logger.info("🔍 GroupsViewModel: Final state - allGroups: \(self.allGroups.count), displayedGroups: \(self.displayedGroups.count), isLoading: \(self.isLoading)")
            logger.info("🔍 GroupsViewModel: isInitialLoadComplete: \(self.isInitialLoadComplete)")
            
        } catch {
            logger.error("❌ GroupsViewModel: Failed to load groups: \(error.localizedDescription)")
            logger.error("❌ GroupsViewModel: Error details: \(error)")
            isLoading = false
        }
    }
    
    /// Filter groups based on search query
    func performSearch(query: String, dataProvider: SQLiteDataProvider) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        // Search through all loaded groups
        guard !allGroups.isEmpty else {
            searchResults = []
            return
        }
        
        let results = allGroups.filter { group in
            group.name.localizedCaseInsensitiveContains(query) ||
            group.memberPhones.contains { phone in
                if let contact = dataProvider.contacts.first(where: { $0.phone == phone }) {
                    return contact.displayName.localizedCaseInsensitiveContains(query) ||
                           contact.phone.contains(query)
                }
                return false
            }
        }
        
        searchResults = results
        logger.info("🔍 GroupsViewModel: Search for '\(query)' returned \(results.count) results")
    }
    
    /// Clear search results
    func clearSearch() {
        searchResults = []
        logger.info("🔍 GroupsViewModel: Search cleared")
    }
    
    /// Refresh groups from data provider
    func refreshGroups(from dataProvider: SQLiteDataProvider) async {
        logger.info("🔄 GroupsViewModel: Refreshing groups...")
        print("🔍 DEBUG: GroupsViewModel.refreshGroups() called")
        await loadGroups(from: dataProvider)
    }
    
    /// Sync with data provider without reloading from database
    /// This is called after database changes to update the view model's cached data
    func syncWithDataProvider(_ dataProvider: SQLiteDataProvider) {
        logger.info("🔄 GroupsViewModel: Syncing with data provider (no database reload)...")
        
        // Get the current groups from the data provider
        let currentGroups = dataProvider.groups
        logger.info("📦 GroupsViewModel: Syncing \(currentGroups.count) groups from data provider")
        
        // Sort by recently created (most recent first) - default sort
        let sortedGroups = currentGroups.sorted { (group1: ContactGroup, group2: ContactGroup) in
            return group1.createdAt > group2.createdAt
        }
        
        // Force SwiftUI to recognize the change
        objectWillChange.send()
        
        // Update local state
        self.allGroups = sortedGroups
        self.displayedGroups = sortedGroups
        
        // Force another update after assignment
        objectWillChange.send()
        
        logger.info("✅ GroupsViewModel: Synced - allGroups: \(self.allGroups.count), displayedGroups: \(self.displayedGroups.count)")
    }
    
    /// Sort groups by the specified option
    func sortGroups(by sortOption: GroupSortOption) async {
        logger.info("🔄 GroupsViewModel: Sorting groups by \(sortOption.displayName)")
        
        var sortedGroups = allGroups
        
        switch sortOption {
        case .recentlyUpdated:
            // Sort by creation date (most recent first)
            sortedGroups.sort { (group1: ContactGroup, group2: ContactGroup) in
                return group1.createdAt > group2.createdAt
            }
            
        case .dateCreated:
            // Sort by creation date (earliest first)
            sortedGroups.sort { (group1: ContactGroup, group2: ContactGroup) in
                return group1.createdAt < group2.createdAt
            }
            
        case .name:
            // Sort alphabetically by name
            sortedGroups.sort { (group1: ContactGroup, group2: ContactGroup) in
                return group1.name.localizedCaseInsensitiveCompare(group2.name) == .orderedAscending
            }
            
        case .size:
            // Sort by member count (largest first)
            sortedGroups.sort { (group1: ContactGroup, group2: ContactGroup) in
                return group1.memberCount > group2.memberCount
            }
        }
        
        // Update the displayed groups
        displayedGroups = sortedGroups
        logger.info("✅ GroupsViewModel: Groups sorted by \(sortOption.displayName), showing \(sortedGroups.count) groups")
    }
    
    /// Async version of syncWithDataProvider - only copies data, no DB operations
    /// This prevents infinite loops by never triggering database reloads
    func syncFromProvider(_ dataProvider: SQLiteDataProvider) async {
        guard !isLoading else {
            logger.info("🚫 GroupsViewModel: Already loading, skipping sync...")
            return
        }
        
        logger.info("🔄 GroupsViewModel: syncFromProvider called (async, no DB reload)")
        
        // Just copy the data that's already loaded in dataProvider
        let allLoadedGroups = dataProvider.groups
        logger.info("📦 GroupsViewModel: Syncing \(allLoadedGroups.count) groups from provider")
        
        // Sort by recently created (most recent first) - default sort
        let sortedGroups = allLoadedGroups.sorted { (group1: ContactGroup, group2: ContactGroup) in
            return group1.createdAt > group2.createdAt
        }
        
        // Update state on main actor
        await MainActor.run {
            self.allGroups = sortedGroups
            self.displayedGroups = sortedGroups
            self.isInitialLoadComplete = true
        }
        
        logger.info("✅ GroupsViewModel: syncFromProvider completed - allGroups: \(self.allGroups.count), displayedGroups: \(self.displayedGroups.count)")
    }
    
    /// Set up observer to automatically sync when dataProvider.groups changes
    /// This creates a one-way data flow: dataProvider → ViewModel (no loops)
    func setupDataProviderObserver(_ dataProvider: SQLiteDataProvider) {
        logger.info("🔌 GroupsViewModel: Setting up dataProvider observer...")
        
        dataProvider.$groups
            .sink { [weak self] newGroups in
                guard let self = self else { return }
                // Only sync if we have data and aren't currently loading
                if !newGroups.isEmpty && !self.isLoading {
                    self.logger.info("🔔 GroupsViewModel: dataProvider.groups changed (\(newGroups.count) groups), triggering sync...")
                    Task {
                        await self.syncFromProvider(dataProvider)
                    }
                }
            }
            .store(in: &cancellables)
        
        logger.info("✅ GroupsViewModel: dataProvider observer setup complete")
    }
}
