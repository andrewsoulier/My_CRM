import SwiftUI
import UniformTypeIdentifiers

struct PageNavBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var dragDropManager: DragDropManager
    @EnvironmentObject var selectionManager: SelectionManager
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedTab: NavigationTab = .navigation
    
    enum NavigationTab: String, CaseIterable {
        case navigation = "Navigation"
        case contacts = "Contacts"
        case groups = "Groups"
        
        var icon: String {
            switch self {
            case .navigation: return "sidebar.left"
            case .contacts: return "person.2"
            case .groups: return "person.3.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("My CRM")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    appState.togglePageNavBar()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(
                headerBackground
            )
            
            // Tab Selector
            HStack(spacing: 0) {
                ForEach(NavigationTab.allCases, id: \.self) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.caption)
                            Text(tab.rawValue)
                                .font(.caption2)
                        }
                        .foregroundColor(selectedTab == tab ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Rectangle()
                                .fill(selectedTab == tab ? navSelectionHighlight(for: colorScheme) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(navTabBackgroundColor)
            
            // Content based on selected tab
            switch selectedTab {
            case .navigation:
                NavigationTreeView()
            case .contacts:
                ContactsSectionView()
            case .groups:
                GroupsSectionView()
            }
        }
        .background(navBackgroundColor)
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(.separatorColor)),
            alignment: .trailing
        )
        .onTapGesture {
            hotkeyManager.enableNavHotkeys()
        }
        .onAppear {
            hotkeyManager.enableNavHotkeys()
        }
    }
    
    private var navBackgroundColor: Color {
        navBackground(for: colorScheme)
    }
    
    private var navTabBackgroundColor: Color {
        colorScheme == .dark ? Color.clear : Color(NSColor.controlColor).opacity(0.5)
    }
    
    @ViewBuilder
    private var headerBackground: some View {
        if colorScheme == .dark {
            Color.clear
        } else {
            LinearGradient(
                colors: [Color(NSColor.controlColor), Color(NSColor.controlColor).opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Navigation Tree View
struct NavigationTreeView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !mainPages.isEmpty {
                    NavigationSection(title: "Main", items: mainPages)
                }
                if !toolPages.isEmpty {
                    NavigationSection(title: "Tools", items: toolPages)
                }
                if !managementPages.isEmpty {
                    NavigationSection(title: "Management", items: managementPages)
                }
            }
        }
    }
    
    private var mainPages: [NavigationItem] {
        filterNavigationItems([
            NavigationItem(page: .peopleMaps, icon: "person.3.fill", isExpanded: true),
            NavigationItem(page: .gridView, icon: "square.grid.3x3.fill"),
            NavigationItem(page: .deckBuilder, icon: "rectangle.stack", isExpanded: false)
        ])
    }
    
    private var toolPages: [NavigationItem] {
        filterNavigationItems([
            NavigationItem(page: .smartLists, icon: "list.bullet"),
            NavigationItem(page: .timeline, icon: "clock.fill"),
            NavigationItem(page: .flashcardTrainer, icon: "brain.head.profile"),
            NavigationItem(page: .quickSend, icon: "paperplane.fill"),
            NavigationItem(page: .engagementDashboard, icon: "chart.bar.fill")
        ])
    }
    
    private var managementPages: [NavigationItem] {
        filterNavigationItems([
            NavigationItem(page: .canvasManagement, icon: "rectangle.on.rectangle"),
            NavigationItem(page: .automationsManager, icon: "gearshape.fill"),
            NavigationItem(page: .tagManager, icon: "tag.fill"),
            NavigationItem(page: .groupsAndCircles, icon: "person.2.fill"),
            NavigationItem(page: .importSync, icon: "arrow.triangle.2.circlepath"),
            NavigationItem(page: .settings, icon: "gear")
        ])
    }
    
    private func filterNavigationItems(_ items: [NavigationItem]) -> [NavigationItem] {
        items.compactMap { item in
            let filteredChildren = filterNavigationItems(item.children)
            let shouldDisplayItem = shouldDisplay(page: item.page) || !filteredChildren.isEmpty
            
            guard shouldDisplayItem else {
                return nil
            }
            
            var updatedItem = item
            updatedItem.children = filteredChildren
            return updatedItem
        }
    }
    
    private func shouldDisplay(page: Page) -> Bool {
        appState.isDeveloperModeEnabled || !page.isPlaceholder
    }
}

// MARK: - Styling Helpers

private func navSelectionHighlight(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
}

private func navBackground(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color.clear : Color(NSColor.controlColor)
}

// MARK: - Contacts Section View
struct ContactsSectionView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var dragDropManager: DragDropManager
    @EnvironmentObject var selectionManager: SelectionManager
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Contacts")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Contacts content - use the same logic as ContactsBarView but in a more compact form
            ContactsCompactView()
        }
    }
}

// MARK: - Groups Section View
struct GroupsSectionView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var dragDropManager: DragDropManager
    @EnvironmentObject var selectionManager: SelectionManager
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Groups")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Groups content - use the same logic as GroupsToolbarView but in a more compact form
            GroupsCompactView()
        }
    }
}

// MARK: - Compact Views
struct ContactsCompactView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var dragDropManager: DragDropManager
    @EnvironmentObject var selectionManager: SelectionManager
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    @EnvironmentObject var hotkeyManager: HotkeyManager
    
    @State private var searchTerm: String = ""
    @FocusState private var isSearchFocused: Bool
    
    private var contactsToDisplay: [Contact] {
        let contacts = if !appState.searchTerm.isEmpty {
            globalCanvasService.contactsViewModel.searchResults
        } else {
            globalCanvasService.contactsViewModel.displayedContacts
        }
        print("📊 ContactsCompactView: Displaying \(contacts.count) contacts")
        return contacts
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search contacts...", text: $searchTerm)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onTapGesture {
                        hotkeyManager.enableNavHotkeys()
                    }
                    .onSubmit {
                        performSearch(query: searchTerm)
                    }
                    .onChange(of: searchTerm) { _, newValue in
                        performSearch(query: newValue)
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            // Contacts list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(contactsToDisplay) { contact in
                        ContactCompactRowView(contact: contact)
                    }
                    
                    if globalCanvasService.contactsViewModel.isLoading {
                        ProgressView()
                            .padding()
                    }
                }
                .padding(.horizontal)
            }
        }
        .onAppear {
            // Only load contacts if not already loaded and not currently loading
            if globalCanvasService.contactsViewModel.allContacts.isEmpty && 
               !globalCanvasService.contactsViewModel.isLoading && 
               globalCanvasService.contactsViewModel.isInitialLoadComplete == false {
                loadAllContacts()
            }
        }
    }
    
    private func loadAllContacts() {
        print("🔍 DEBUG: PageNavBarView.loadAllContacts() called")
        Task {
            await globalCanvasService.contactsViewModel.loadContacts(from: dataProvider, sortOption: appState.sortOption)
            if appState.searchTerm.isEmpty {
                globalCanvasService.contactsViewModel.filterCanvasContacts(canvasContactPhones: globalCanvasService.canvasContactPhones)
            }
        }
    }
    
    private func performSearch(query: String) {
        appState.searchTerm = query
        guard !query.isEmpty else {
            globalCanvasService.contactsViewModel.searchResults = []
            globalCanvasService.contactsViewModel.filterCanvasContacts(canvasContactPhones: globalCanvasService.canvasContactPhones)
            return
        }
        
        guard !globalCanvasService.contactsViewModel.allContacts.isEmpty else {
            globalCanvasService.contactsViewModel.searchResults = []
            return
        }
        
        let fuzzyMatcher = FuzzyMatcher()
        let results = fuzzyMatcher.search(query: query, in: globalCanvasService.contactsViewModel.allContacts)
        globalCanvasService.contactsViewModel.searchResults = results.map { $0.item }
    }
}

struct GroupsCompactView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var dragDropManager: DragDropManager
    @EnvironmentObject var selectionManager: SelectionManager
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    @EnvironmentObject var hotkeyManager: HotkeyManager
    
    @State private var searchTerm: String = ""
    @FocusState private var isSearchFocused: Bool
    
    private var groupsViewModel: GroupsViewModel {
        globalCanvasService.groupsViewModel
    }
    
    private var groupsToDisplay: [ContactGroup] {
        let groups = if !searchTerm.isEmpty {
            groupsViewModel.allGroups.filter { group in
                group.name.localizedCaseInsensitiveContains(searchTerm)
            }
        } else {
            groupsViewModel.displayedGroups
        }
        print("📊 GroupsCompactView: Displaying \(groups.count) groups")
        return groups
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search groups...", text: $searchTerm)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onTapGesture {
                        hotkeyManager.enableNavHotkeys()
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            // Groups list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(groupsToDisplay) { group in
                        GroupCompactRowView(group: group)
                    }
                    
                    if groupsViewModel.isLoading {
                        ProgressView()
                            .padding()
                    }
                }
                .padding(.horizontal)
            }
        }
        .onAppear {
            // Only load groups if not already loaded and not currently loading
            if groupsViewModel.allGroups.isEmpty && 
               !groupsViewModel.isLoading && 
               groupsViewModel.isInitialLoadComplete == false {
                loadAllGroups()
            }
        }
    }
    
    private func loadAllGroups() {
        print("🔍 DEBUG: PageNavBarView.loadAllGroups() called")
        Task {
            await groupsViewModel.loadGroups(from: dataProvider)
        }
    }
}

struct ContactCompactRowView: View {
    let contact: Contact
    @EnvironmentObject var selectionManager: SelectionManager
    @EnvironmentObject var dragDropManager: DragDropManager
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    
    private var isFocused: Bool {
        guard !selectionManager.contactListContext.isEmpty,
              selectionManager.focusedContactIndex < selectionManager.contactListContext.count else {
            return false
        }
        return selectionManager.contactListContext[selectionManager.focusedContactIndex] == contact.phone
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Contact avatar
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 24, height: 24)
                
                if let profileImage = contact.profileImage {
                    Image(nsImage: profileImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 22, height: 22)
                        .clipShape(Circle())
                        .onAppear {
                            print("🖼️ Displaying profile image for contact in navbar: \(contact.displayName) (\(contact.phone)) - image size: \(profileImage.size)")
                        }
                } else {
                    Text(contact.initials)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                        .onAppear {
                            print("🔤 Displaying initials '\(contact.initials)' for contact in navbar: \(contact.displayName) (\(contact.phone)) - profilePhotoData: \(contact.profilePhotoData?.count ?? 0) bytes")
                        }
                }
            }
            
            // Contact info
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName.isEmpty ? "no name saved" : contact.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if !contact.phone.isEmpty {
                    Text(contact.phone)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isFocused ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .draggable(contact) {
            DragPreview(count: 1)
        }
        .onAppear {
            print("🔍 ContactCompactRowView appeared for: \(contact.displayName) (\(contact.phone)) - profilePhotoData: \(contact.profilePhotoData?.count ?? 0) bytes")
            DragDropLogger.shared.logDragStart(contact: contact, source: "ContactsCompactView")
            DragDropLogger.shared.logProviderCreation(contact: contact, typeIdentifier: UTType.vCard.identifier)
        }
        .onTapGesture {
            handleContactSelection()
        }
    }
    
    private func handleContactSelection() {
        let modifiers = NSEvent.modifierFlags
        let eventModifiers: EventModifiers = {
            var result: EventModifiers = []
            if modifiers.contains(.command) { result.insert(.command) }
            if modifiers.contains(.shift) { result.insert(.shift) }
            if modifiers.contains(.option) { result.insert(.option) }
            if modifiers.contains(.control) { result.insert(.control) }
            return result
        }()
        
        selectionManager.handleContactTap(contact.phone, modifiers: eventModifiers)
    }
    
    private func addContactToCanvas() {
        let defaultPosition = CGPoint(x: 200, y: 200)
        globalCanvasService.addContactToCanvas(contact, at: defaultPosition)
    }
}

struct GroupCompactRowView: View {
    let group: ContactGroup
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    @EnvironmentObject var selectionManager: SelectionManager
    @StateObject private var groupEditingService: GroupEditingService
    @State private var showingDeleteAlert = false
    
    init(group: ContactGroup) {
        self.group = group
        self._groupEditingService = StateObject(wrappedValue: GroupEditingService())
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Group icon
            Circle()
                .fill(group.color)
                .frame(width: 24, height: 24)
                .overlay(
                    Text(String(group.name.prefix(1)).uppercased())
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                )
            
            // Group info
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text("\(group.memberCount) members")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(selectionManager.isGroupSelected(group.id) ? Color.accentColor.opacity(0.15) : Color.clear)
                .stroke(selectionManager.isGroupSelected(group.id) ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .draggable(group) {
            DragDropLogger.shared.log("Starting group drag from GroupsCompactView", operation: "GROUP_DRAG_START")
            return GroupDragPreview(group: group)
        }
        .dropDestination(for: Contact.self) { contacts, location in
            // Handle dropping contacts into this group
            print("🎯 DROP DESTINATION TRIGGERED for group: \(group.name) - received \(contacts.count) contacts")
            LogManager.shared.info("Drop destination triggered for group: \(group.name) - received \(contacts.count) contacts")
            for contact in contacts {
                print("📦 DROPPED CONTACT: \(contact.displayName) (\(contact.phone))")
                LogManager.shared.info("Dropped contact: \(contact.displayName) (\(contact.phone))")
                addContactToGroup(contact)
            }
            return true
        } isTargeted: { isTargeted in
            // Visual feedback when dragging over the group
            print("🎯 DROP TARGET STATE: \(isTargeted) for group: \(group.name)")
            LogManager.shared.info("Drop target state changed: \(isTargeted) for group: \(group.name)")
        }
        .onTapGesture {
            handleGroupSelection()
        }
        .onAppear {
            // Set the dataProvider for GroupEditingService
            groupEditingService.setDataProvider(dataProvider)
        }
    }
    
    private func handleGroupSelection() {
        let modifiers = NSEvent.modifierFlags
        let eventModifiers: EventModifiers = {
            var result: EventModifiers = []
            if modifiers.contains(.command) { result.insert(.command) }
            if modifiers.contains(.shift) { result.insert(.shift) }
            if modifiers.contains(.option) { result.insert(.option) }
            if modifiers.contains(.control) { result.insert(.control) }
            return result
        }()
        
        selectionManager.handleGroupTap(group.id, modifiers: eventModifiers)
    }
    
    private func addContactToGroup(_ contact: Contact) {
        print("🔄 addContactToGroup called for contact: \(contact.displayName) to group: \(group.name)")
        LogManager.shared.info("addContactToGroup called for contact: \(contact.displayName) to group: \(group.name)")
        
        // Check if contact is already in the group
        guard !group.memberPhones.contains(contact.phone) else {
            print("Contact \(contact.displayName) is already in group \(group.name)")
            LogManager.shared.info("Contact \(contact.displayName) is already in group \(group.name)")
            return
        }
        
        Task {
            do {
                print("🔧 Calling dataProvider.add for contact: \(contact.displayName)")
                LogManager.shared.info("Calling dataProvider.add for contact: \(contact.displayName)")
                try await dataProvider.add(phones: [contact.phone], to: group.id)
                print("✅ Successfully added contact \(contact.displayName) to group \(group.name)")
                LogManager.shared.info("Successfully added contact \(contact.displayName) to group \(group.name)")
                
                // Refresh the groups list to reflect the change
                await globalCanvasService.groupsViewModel.refreshGroups(from: dataProvider)
                print("✅ Groups refreshed after adding contact")
                LogManager.shared.info("Groups refreshed after adding contact")
            } catch {
                print("❌ Failed to add contact to group: \(error)")
                LogManager.shared.error("Failed to add contact to group: \(error)")
            }
        }
    }
}

struct NavigationSection: View {
    let title: String
    let items: [NavigationItem]
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var hotkeyManager: HotkeyManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section Header
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            // Section Items
            ForEach(items) { item in
                NavigationItemView(item: item)
            }
        }
    }
}

struct NavigationItem: Identifiable {
    let id = UUID()
    let page: Page
    let icon: String
    var isExpanded: Bool = false
    var children: [NavigationItem] = []
}

struct NavigationItemView: View {
    let item: NavigationItem
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded: Bool
    
    private var isSelected: Bool {
        appState.selectedPage == item.page
    }
    
    init(item: NavigationItem) {
        self.item = item
        self._isExpanded = State(initialValue: item.isExpanded)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Item
            Button(action: {
                hotkeyManager.enableNavHotkeys()
                
                if item.children.isEmpty {
                    appState.selectPage(item.page)
                } else {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: item.icon)
                        .frame(width: 20)
                        .foregroundColor(isSelected ? .primary : .secondary)
                    
                    Text(item.page.rawValue)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if !item.children.isEmpty {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? navSelectionHighlight(for: colorScheme) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            
            // Children
            if isExpanded && !item.children.isEmpty {
                ForEach(item.children) { child in
                    NavigationItemView(item: child)
                        .padding(.leading, 20)
                }
            }
        }
    }
}

#Preview {
    PageNavBarView()
        .environmentObject(AppState())
}
