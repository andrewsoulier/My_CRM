import SwiftUI
import UniformTypeIdentifiers
import Combine

enum GroupSortOption: String, CaseIterable {
    case recentlyUpdated = "Recently Updated"
    case dateCreated = "Date Created"
    case name = "Name"
    case size = "Size"
    
    var displayName: String {
        return self.rawValue
    }
}

struct GroupsToolbarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var selectionManager: SelectionManager
    @EnvironmentObject var dragDropManager: DragDropManager
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    
    private let logger = LogManager.shared
    
    @State private var groupsSearchTerm = ""
    @State private var showingCreateGroup = false
    @State private var newGroupName = ""
    @State private var selectedDeck: ContactGroup?
    @FocusState private var isSearchFocused: Bool
    @State private var refreshTrigger = UUID()
    @State private var isRefreshing = false
    @State private var selectedSortOption: GroupSortOption = .recentlyUpdated
    
    // Groups view model for managing groups data (using GlobalCanvasService)
    // Access the groupsViewModel directly from the globalCanvasService to avoid StateObject issues
    
    // Callback for deck selection
    let onDeckSelected: ((ContactGroup?) -> Void)?
    
    init(onDeckSelected: ((ContactGroup?) -> Void)? = nil) {
        self.onDeckSelected = onDeckSelected
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Groups")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    appState.toggleGroupsBar()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Search and Create Controls
            VStack(spacing: 8) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search groups...", text: $groupsSearchTerm)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .onChange(of: groupsSearchTerm) { _, newValue in
                            globalCanvasService.groupsViewModel.performSearch(query: newValue, dataProvider: dataProvider)
                        }
                        .onKeyPress(.escape) {
                            clearSearch()
                            return .handled
                        }
                    
                    // X button to clear search (only show when search is active)
                    if !groupsSearchTerm.isEmpty {
                        Button(action: clearSearch) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlColor))
                .cornerRadius(8)
                
                // Sort Dropdown
                HStack {
                    Text("Sort by:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Sort Groups", selection: $selectedSortOption) {
                        ForEach(GroupSortOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                    .onChange(of: selectedSortOption) { _, newValue in
                        applySorting(newValue)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                
                // Create Group Button
                HStack {
                    Button(action: {
                        showingCreateGroup = true
                    }) {
                        Label("Create Group", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Groups List
            ScrollView {
                LazyVStack(spacing: 0) {
                    let groupsToDisplay = groupsSearchTerm.isEmpty ? globalCanvasService.groupsViewModel.displayedGroups : globalCanvasService.groupsViewModel.searchResults
                    
                    if groupsToDisplay.isEmpty && !globalCanvasService.groupsViewModel.isLoading {
                        VStack(spacing: 16) {
                            if globalCanvasService.groupsViewModel.isInitialLoadComplete {
                                Image(systemName: groupsSearchTerm.isEmpty ? "person.2.slash" : "magnifyingglass")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                
                                Text(groupsSearchTerm.isEmpty ? "No Groups Found" : "No Search Results")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text(groupsSearchTerm.isEmpty ? 
                                     "Create your first group to organize contacts." :
                                     "No groups found matching '\(groupsSearchTerm)'")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                
                                if groupsSearchTerm.isEmpty {
                                    Button("Create Group") {
                                        showingCreateGroup = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .padding(.top, 8)
                                }
                            } else {
                                ProgressView("Loading groups...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(40)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ForEach(groupsToDisplay) { group in
                            GroupRowView(
                                group: group,
                                isSelected: selectedDeck?.id == group.id,
                                onSelect: {
                                    print("🔍 GroupsToolbarView: Group selected: \(group.name) with ID: \(group.id)")
                                    selectedDeck = group
                                    onDeckSelected?(group)
                                    // Navigate to DeckBuilderView to show group details
                                    print("🔍 GroupsToolbarView: Navigating to DeckBuilderView and setting selectedDeck to: \(group.id)")
                                    appState.selectPage(Page.deckBuilder)
                                    appState.selectedDeck = group.id
                                    print("🔍 GroupsToolbarView: appState.selectedDeck is now: \(appState.selectedDeck?.uuidString ?? "nil")")
                                },
                                onGroupDeleted: {
                                    // Force UI refresh by updating the refresh trigger
                                    refreshTrigger = UUID()
                                }
                            )
                            .environmentObject(globalCanvasService)
                        }
                        
                        if globalCanvasService.groupsViewModel.isLoading {
                            ProgressView()
                                .padding()
                        }
                    }
                }
            }
        .onAppear {
            logger.info("🎯 GroupsToolbarView: onAppear triggered")
            logger.info("🎯 GroupsToolbarView: Current state - isInitialLoadComplete: \(globalCanvasService.groupsViewModel.isInitialLoadComplete), isLoading: \(globalCanvasService.groupsViewModel.isLoading)")
            logger.info("🎯 GroupsToolbarView: dataProvider.groups.count = \(dataProvider.groups.count)")
            logger.info("🎯 GroupsToolbarView: allGroups.count = \(globalCanvasService.groupsViewModel.allGroups.count), displayedGroups.count = \(globalCanvasService.groupsViewModel.displayedGroups.count)")
            logger.info("🎯 GroupsToolbarView: dataProvider.isConnectedToDatabase = \(dataProvider.isConnectedToDatabase)")
            
            // Only refresh groups data if not already loaded to avoid infinite loops
            if !globalCanvasService.groupsViewModel.isInitialLoadComplete {
                logger.info("🎯 GroupsToolbarView: Initial load not complete - calling refreshGroupsData()")
                refreshGroupsData()
            } else {
                logger.info("🎯 GroupsToolbarView: Already loaded, skipping refresh")
            }
        }
            .refreshable {
                // Force refresh when user pulls down
                await Task {
                    await globalCanvasService.groupsViewModel.refreshGroups(from: dataProvider)
                }.value
            }
            .onTapGesture {
                // Unfocus search bar when clicking anywhere in the groups bar
                isSearchFocused = false
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UnfocusSearchBar"))) { _ in
                // Unfocus search bar when clicking anywhere in the app
                isSearchFocused = false
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(.separatorColor)),
            alignment: .trailing
        )
        .onKeyPress { keyPress in
            return handleKeyPress(keyPress)
        }
        .sheet(isPresented: $showingCreateGroup) {
            CreateGroupView { groupName in
                createNewGroup(name: groupName)
            }
        }
        .id(refreshTrigger) // Force view refresh when needed
    }
    
    private func loadAllGroups() {
        logger.info("👥 GroupsToolbarView: loadAllGroups() called")
        logger.info("👥 GroupsToolbarView: isLoading = \(globalCanvasService.groupsViewModel.isLoading)")
        
        guard !globalCanvasService.groupsViewModel.isLoading else { 
            logger.warning("👥 GroupsToolbarView: Already loading, skipping...")
            return 
        }
        
        logger.info("👥 GroupsToolbarView: Starting async load...")
        Task {
            await globalCanvasService.groupsViewModel.loadGroups(from: dataProvider)
        }
    }
    
    private func refreshGroupsData() {
        logger.info("🔄 GroupsToolbarView: refreshGroupsData() called")
        
        // Only update refresh trigger if we're not already loading to avoid infinite loops
        guard !globalCanvasService.groupsViewModel.isLoading else {
            logger.warning("🔄 GroupsToolbarView: Already loading, skipping refresh trigger update")
            return
        }
        
        // Prevent recursive calls by checking if we're already refreshing
        guard !isRefreshing else {
            logger.warning("🔄 GroupsToolbarView: Already refreshing, skipping to prevent infinite loop")
            return
        }
        
        isRefreshing = true
        
        // Refresh the groups view model with current data
        Task {
            await globalCanvasService.groupsViewModel.refreshGroups(from: dataProvider)
            // Reset the flag after refresh completes
            await MainActor.run {
                isRefreshing = false
            }
        }
    }
    
    private func clearSearch() {
        groupsSearchTerm = ""
        isSearchFocused = false
        globalCanvasService.groupsViewModel.clearSearch()
    }
    
    private func applySorting(_ sortOption: GroupSortOption) {
        Task {
            await globalCanvasService.groupsViewModel.sortGroups(by: sortOption)
        }
    }
    
    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        // Handle delete key for group deletion
        if keyPress.key == .delete {
            // First check if there are any groups selected in SelectionManager
            if !selectionManager.selectedGroups.isEmpty {
                deleteSelectedGroups(Array(selectionManager.selectedGroups))
                return .handled
            }
            // Fallback to deleting the currently viewed group if no multi-selection
            else if let selectedDeck = selectedDeck {
                deleteSelectedGroup(selectedDeck)
                return .handled
            }
        }
        
        // Handle key presses for group navigation
        return .ignored
    }
    
    private func createNewGroup(name: String) {
        let newGroup = ContactGroup(
            id: UUID(),
            name: name,
            isDeck: false
        )
        
        Task {
            try await dataProvider.createGroup(newGroup)
            // Refresh groups after creating a new one
            await globalCanvasService.groupsViewModel.refreshGroups(from: dataProvider)
        }
    }
    
    private func deleteSelectedGroup(_ group: ContactGroup) {
        logger.info("🗑️ Deleting group: \(group.name) (ID: \(group.id))")
        
        Task {
            do {
                // Delete the group from the database
                try await dataProvider.deleteGroup(group.id)
                
                // Remove the group from all canvases
                try await removeGroupFromAllCanvases(group.id)
                
                // Clear selection if the deleted group was selected
                if selectedDeck?.id == group.id {
                    selectedDeck = nil
                    onDeckSelected?(nil)
                }
                
                // Refresh groups list
                await globalCanvasService.groupsViewModel.refreshGroups(from: dataProvider)
                
                logger.info("✅ Successfully deleted group: \(group.name)")
            } catch {
                logger.error("❌ Failed to delete group \(group.name): \(error)")
            }
        }
    }
    
    private func deleteSelectedGroups(_ groupIds: [UUID]) {
        logger.info("🗑️ Deleting \(groupIds.count) selected groups")
        
        Task {
            var deletedCount = 0
            for groupId in groupIds {
                do {
                    // Delete from database
                    try await dataProvider.deleteGroup(groupId)
                    
                    // Remove from all canvases
                    try await removeGroupFromAllCanvases(groupId)
                    
                    deletedCount += 1
                    logger.info("✅ Deleted group: \(groupId)")
                } catch {
                    logger.error("❌ Failed to delete group \(groupId): \(error)")
                }
            }
            
            // Clear selection and refresh UI
            await MainActor.run {
                // Clear all group selections
                selectionManager.clearGroupSelection()
                
                // Clear selected deck if it was deleted
                if let selectedDeck = appState.selectedDeck, groupIds.contains(selectedDeck) {
                    appState.selectedDeck = nil
                }
                
                // Refresh the groups list
                Task {
                    await globalCanvasService.groupsViewModel.refreshGroups(from: dataProvider)
                }
            }
            
            logger.info("✅ Successfully deleted \(deletedCount) of \(groupIds.count) groups")
        }
    }
    
    private func removeGroupFromAllCanvases(_ groupId: UUID) async throws {
        logger.info("🧹 Removing group \(groupId) from all canvases")
        
        // Get all canvases
        let allCanvases = globalCanvasService.canvasService.getAllCanvases()
        
        for canvas in allCanvases {
            // Convert canvas ID from String to UUID
            guard let canvasUUID = UUID(uuidString: canvas.id) else {
                logger.warning("⚠️ Invalid canvas ID format: \(canvas.id)")
                continue
            }
            
            // Remove the group from this canvas
            try await dataProvider.removeGroupFromCanvas(groupId: groupId, canvasId: canvasUUID)
            
            // Also remove the group from canvas elements
            try await dataProvider.removeGroupFromCanvasElements(groupId: groupId, canvasId: canvasUUID)
            
            logger.info("✅ Removed group from canvas: \(canvas.name)")
        }
    }
}

struct GroupRowView: View {
    let group: ContactGroup
    let isSelected: Bool
    let onSelect: () -> Void
    let onGroupDeleted: (() -> Void)?
    @EnvironmentObject var selectionManager: SelectionManager
    @EnvironmentObject var dragDropManager: DragDropManager
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    @EnvironmentObject var appState: AppState
    // @StateObject private var groupEditingService: GroupEditingService // Temporarily commented out
    @State private var showingDeleteAlert = false
    
    init(group: ContactGroup, isSelected: Bool, onSelect: @escaping () -> Void, onGroupDeleted: (() -> Void)? = nil) {
        self.group = group
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onGroupDeleted = onGroupDeleted
        // self._groupEditingService = StateObject(wrappedValue: GroupEditingService()) // Temporarily commented out
    }
    
    private var isFocused: Bool {
        // TODO: Implement focus logic similar to ContactRowView
        false
    }
    
    // Check if this group is selected in SelectionManager (for multi-selection)
    private var isSelectedInManager: Bool {
        selectionManager.isGroupSelected(group.id)
    }
    
    // Show highlight if either: currently viewed group OR selected in SelectionManager
    private var shouldHighlight: Bool {
        isSelected || isSelectedInManager
    }
    
    private var memberContacts: [Contact] {
        group.memberPhones.compactMap { phone in
            dataProvider.contacts.first { $0.phone == phone }
        }
    }
    
    var body: some View {
        // Temporary simplified body to fix compilation issue
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Group Icon/Color
                ZStack {
                    Circle()
                        .fill(group.color.opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: group.isDeck ? "rectangle.stack" : "person.2")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(group.color)
                }
                
                // Group Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(group.memberCount) members")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if group.isDeck {
                        Text("Deck")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            
            // Member preview (show first few members)
            if !memberContacts.isEmpty {
                HStack(spacing: 4) {
                    ForEach(memberContacts.prefix(3), id: \.phone) { contact in
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.2))
                                .frame(width: 20, height: 20)
                            
                            if let profileImage = contact.profileImage {
                                Image(nsImage: profileImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 18, height: 18)
                                    .clipShape(Circle())
                            } else {
                                Text(contact.initials)
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    
                    if memberContacts.count > 3 {
                        Text("+\(memberContacts.count - 3)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(shouldHighlight ? Color.accentColor.opacity(0.15) : Color.clear)
                .stroke(shouldHighlight ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                .overlay(
                    // Focus indicator
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: isFocused ? 2 : 0)
                        .animation(.easeInOut(duration: 0.1), value: isFocused)
                )
        )
        .contentShape(Rectangle()) // Makes entire area clickable
        .onTapGesture {
            handleGroupSelection()
        }
        .draggable(group) {
            DragDropLogger.shared.log("Starting group drag from GroupsToolbarView", operation: "GROUP_DRAG_START")
            return GroupDragPreview(group: group)
        }
        .onDrop(of: [UTType.vCard.identifier, UTType.crmContactList.identifier], isTargeted: nil) { providers in
            handleContactDrop(providers: providers, targetGroup: group)
        }
        .contextMenu {
            Button("Delete Group") {
                showingDeleteAlert = true
            }
            .foregroundColor(.red)
        }
        .alert("Delete Group", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await deleteGroup()
                }
            }
        } message: {
            Text("Are you sure you want to delete '\(group.name)'? This action cannot be undone.")
        }
        .onAppear {
            // groupEditingService.updateDataProvider(dataProvider) // Temporarily commented out
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
        
        // Handle multi-selection with Command/Shift
        if eventModifiers.contains(.command) || eventModifiers.contains(.shift) {
            // Toggle selection in SelectionManager
            selectionManager.handleGroupTap(group.id, modifiers: eventModifiers)
            
            // If this group is now selected and no group is currently viewed, view it
            if selectionManager.isGroupSelected(group.id) && appState.selectedDeck == nil {
                onSelect()
            }
        } else {
            // Single selection - clear other selections and select this one
            selectionManager.clearGroupSelection()
            selectionManager.handleGroupTap(group.id, modifiers: eventModifiers)
            onSelect()
        }
    }
    
    private func navigateToGroupDetails() {
        // Navigate to Group Details page
        print("Navigate to group details for: \(group.name)")
        
        // Set the selected page to deckBuilder and select this group
        appState.selectPage(Page.deckBuilder)
        appState.selectedDeck = group.id
    }
    
    private func deleteGroup() async {
        // Find the corresponding ContactGroup in the database by UUID first, then by name as fallback
        do {
            let allGroups = try await dataProvider.fetchGroups()
            
            // First try to find by UUID (most reliable)
            var databaseGroup = allGroups.first(where: { $0.id == group.id })
            
            // If not found by UUID, try by name as fallback
            if databaseGroup == nil {
                databaseGroup = allGroups.first(where: { $0.name == group.name })
                if databaseGroup != nil {
                    LogManager.shared.info("Found database group by name for deletion: \(group.name)")
                }
            } else {
                LogManager.shared.info("Found database group by UUID for deletion: \(group.id)")
            }
            
            guard let foundGroup = databaseGroup else {
                LogManager.shared.error("Could not find database group for toolbar group deletion: \(group.name) (ID: \(group.id))")
                LogManager.shared.error("Available groups: \(allGroups.map { "\($0.name) (ID: \($0.id))" }.joined(separator: ", "))")
                return
            }
            
            try await dataProvider.deleteGroup(foundGroup.id)
            
            // Remove the group from all canvases
            try await removeGroupFromAllCanvases(foundGroup.id)
            
            // Refresh groups list to update the UI on the main actor
            await MainActor.run {
                // Clear selected deck in appState if this was the selected group
                if appState.selectedDeck == foundGroup.id {
                    appState.selectedDeck = nil
                }
                
                // Clear from SelectionManager if selected
                if selectionManager.isGroupSelected(foundGroup.id) {
                    selectionManager.deselectGroup(foundGroup.id)
                }
                
                // Notify parent view to trigger UI refresh
                onGroupDeleted?()
                
                // Refresh the groups view model
                Task {
                    await globalCanvasService.groupsViewModel.refreshGroups(from: dataProvider)
                }
            }
            
            LogManager.shared.info("Successfully deleted toolbar group: \(group.name)")
        } catch {
            LogManager.shared.error("Failed to delete toolbar group: \(error)")
        }
    }
    
    private func handleContactDrop(providers: [NSItemProvider], targetGroup: ContactGroup) -> Bool {
        DragDropLogger.shared.log("GroupRowView handleContactDrop called for group: \(targetGroup.name)", operation: "GROUP_DROP_START")
        
        Task {
            do {
                // Use DragDropManager to decode the providers
                guard let dragItem = try await dragDropManager.decodeProviders(providers) else {
                    DragDropLogger.shared.log("Failed to decode contact drag item", operation: "GROUP_DROP_ERROR")
                    return
                }
                
                DragDropLogger.shared.log("Successfully decoded drag item with \(dragItem.phones.count) contacts for group: \(targetGroup.name)", operation: "GROUP_DROP_SUCCESS")
                
                // Use DragDropManager to perform the drop operation
                try await dragDropManager.performDrop(
                    item: dragItem,
                    to: .group(id: targetGroup.id),
                    copy: false, // Don't copy, just add to group
                    dataProvider: dataProvider,
                    undo: nil // TODO: Add undo support
                )
                
                DragDropLogger.shared.log("Successfully added contacts to group: \(targetGroup.name)", operation: "GROUP_DROP_COMPLETE")
                
                // Refresh the groups data to show updated member counts
                await globalCanvasService.groupsViewModel.refreshGroups(from: dataProvider)
                
            } catch {
                DragDropLogger.shared.log("Error handling contact drop: \(error)", operation: "GROUP_DROP_ERROR")
                LogManager.shared.error("Failed to add contacts to group \(targetGroup.name): \(error)")
            }
        }
        
        return true
    }
    
    private func removeGroupFromAllCanvases(_ groupId: UUID) async throws {
        LogManager.shared.info("🧹 Removing group \(groupId) from all canvases")
        
        // Get all canvases
        let allCanvases = globalCanvasService.canvasService.getAllCanvases()
        
        for canvas in allCanvases {
            // Convert canvas ID from String to UUID
            guard let canvasUUID = UUID(uuidString: canvas.id) else {
                LogManager.shared.warning("⚠️ Invalid canvas ID format: \(canvas.id)")
                continue
            }
            
            // Remove the group from this canvas
            try await dataProvider.removeGroupFromCanvas(groupId: groupId, canvasId: canvasUUID)
            
            // Also remove the group from canvas elements
            try await dataProvider.removeGroupFromCanvasElements(groupId: groupId, canvasId: canvasUUID)
            
            LogManager.shared.info("✅ Removed group from canvas: \(canvas.name)")
        }
    }
}

struct GroupDragPreview: View {
    let group: ContactGroup
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(group.color.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Image(systemName: group.isDeck ? "rectangle.stack" : "person.2")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(group.color)
            }
            
            Text(group.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(radius: 4)
        )
    }
}

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    @State private var isDeck = false
    let onCreate: (String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Group")
                .font(.title2)
                .fontWeight(.bold)
            
            TextField("Group Name", text: $groupName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            
            Toggle("Create as Deck", isOn: $isDeck)
                .frame(width: 300)
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Create") {
                    if !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onCreate(groupName.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

#Preview {
    GroupsToolbarView { deck in
        print("Selected deck: \(deck?.name ?? "None")")
    }
    .environmentObject(AppState())
    .environmentObject(SQLiteDataProvider())
    .environmentObject(SelectionManager())
    .environmentObject(DragDropManager())
}
