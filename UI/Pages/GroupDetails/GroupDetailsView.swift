import SwiftUI

struct GroupDetailsView: View {
    let groupId: UUID
    @ObservedObject var groupEditingService: GroupEditingService
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    
    @State private var isEditingName: Bool = false
    @State private var editingName: String = ""
    @State private var showingColorPicker: Bool = false
    @State private var isUpdating: Bool = false
    @State private var errorMessage: String?
    @State private var showingError: Bool = false
    @State private var showingAddMembers: Bool = false
    @State private var currentGroup: ContactGroup?
    @State private var showingDeleteConfirmation: Bool = false
    @EnvironmentObject var appState: AppState
    
    init(groupId: UUID, groupEditingService: GroupEditingService) {
        self.groupId = groupId
        self.groupEditingService = groupEditingService
        self._currentGroup = State(initialValue: nil)
    }
    
    // Computed property to get the actual Contact objects for group members
    private var memberContacts: [Contact] {
        guard let currentGroup = currentGroup else { return [] }
        return currentGroup.memberPhones.compactMap { phone in
            dataProvider.contacts.first { $0.phone == phone }
        }
    }
    
    var body: some View {
        Group {
            if let currentGroup = currentGroup {
                VStack(spacing: 0) {
                    // Header Section
                    headerSection(for: currentGroup)
                    
                    Divider()
                    
                    // Group Members Section
                    membersSection(for: currentGroup)
                    
                    Spacer()
                }
                .navigationTitle("Group Details")
            } else {
                VStack {
                    Text("Loading group...")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    ProgressView()
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            updateCurrentGroup()
            if let currentGroup = currentGroup {
                editingName = currentGroup.name
            }
            // Set the dataProvider for GroupEditingService
            groupEditingService.setDataProvider(dataProvider)
        }
        .onChange(of: groupId) { _, _ in
            // When groupId changes (e.g., from toolbar selection), update the current group
            updateCurrentGroup()
            if let currentGroup = currentGroup {
                editingName = currentGroup.name
            }
        }
        .onChange(of: dataProvider.groups) { _, _ in
            updateCurrentGroup()
        }
        .onChange(of: currentGroup?.name) { _, newName in
            if let newName = newName {
                editingName = newName
            }
        }
        .sheet(isPresented: $showingAddMembers) {
            if let currentGroup = currentGroup {
                AddMembersToGroupView(group: currentGroup)
                    .environmentObject(dataProvider)
            }
        }
        .onKeyPress(.delete) {
            // Delete the currently viewed group
            if currentGroup != nil {
                showingDeleteConfirmation = true
                return .handled
            }
            return .ignored
        }
        .alert("Delete Group", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await deleteCurrentGroup()
                }
            }
        } message: {
            if let currentGroup = currentGroup {
                Text("Are you sure you want to delete '\(currentGroup.name)'? This action cannot be undone.")
            }
        }
    }
    
    private func headerSection(for group: ContactGroup) -> some View {
        VStack(spacing: 16) {
            // Group Icon and Basic Info
            HStack(spacing: 16) {
                // Group Icon
                ZStack {
                    Circle()
                        .fill(group.color.opacity(0.2))
                        .stroke(group.color, lineWidth: 3)
                        .frame(width: 80, height: 80)
                    
                    Text(group.name.prefix(2).uppercased())
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(group.color)
                }
                
                // Group Info
                VStack(alignment: .leading, spacing: 8) {
                    // Editable Name
                    if isEditingName {
                        VStack(spacing: 12) {
                            TextField("Group name", text: $editingName)
                                .textFieldStyle(.roundedBorder)
                                .font(.title2)
                                .frame(minHeight: 40)
                                .onSubmit {
                                    saveNameChange()
                                }
                            
                            HStack(spacing: 12) {
                                Button("Save") {
                                    saveNameChange()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                
                                Button("Cancel") {
                                    cancelNameEdit()
                                }
                                .buttonStyle(.bordered)
                                
                                Spacer()
                            }
                        }
                    } else {
                        HStack {
                            Text(group.name)
                                .font(.title)
                                .fontWeight(.bold)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                            
                            Button(action: {
                                startEditingName()
                            }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Member Count
                    Text("\(group.memberCount) members")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Created Date
                    Text("Created \(group.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Color Picker Section
            HStack {
                Text("Color:")
                    .font(.headline)
                
                HStack {
                    // Clickable color circle
                    Button(action: {
                        showingColorPicker.toggle()
                    }) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(group.color)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: 1)
                                )
                            
                            Text(group.colorDisplayName)
                                .foregroundColor(.primary)
                                .font(.body)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                
                Spacer()
            }
            
            // Color Picker Popover
            if showingColorPicker {
                colorPickerPopover(for: group)
            }
        }
        .padding()
        .frame(width: 300, height: 200)
    }
    
    private func colorPickerPopover(for group: ContactGroup) -> some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                ForEach(GroupEditingService.availableColors, id: \.self) { color in
                    Button(action: {
                        updateGroupColor(color)
                        showingColorPicker = false
                    }) {
                        Circle()
                            .fill(color)
                            .stroke(color == group.color ? Color.primary : Color.clear, lineWidth: color == group.color ? 2 : 1)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private func membersSection(for group: ContactGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Members")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    showingAddMembers = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Members")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            
            if group.memberPhones.isEmpty {
                Text("No members in this group")
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.horizontal)
            } else {
                // Show member contact cards
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)
                    ], spacing: 16) {
                        ForEach(memberContacts, id: \.phone) { contact in
                            ContactCardView(contact: contact, group: group)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .dropDestination(for: Contact.self) { contacts, location in
            // Handle dropping contacts into this group
            LogManager.shared.info("Drop destination triggered in GroupDetailsView for group: \(group.name)")
            for contact in contacts {
                LogManager.shared.info("Dropped contact: \(contact.displayName) into group: \(group.name)")
                addContactToGroup(contact)
            }
            return true
        } isTargeted: { isTargeted in
            // Visual feedback when dragging over the group
            LogManager.shared.info("Drop target state changed in GroupDetailsView: \(isTargeted)")
        }
    }
    
    // MARK: - Actions
    
    private func updateCurrentGroup() {
        print("🔍 GroupDetailsView: updateCurrentGroup called for groupId: \(groupId)")
        print("🔍 GroupDetailsView: Available groups: \(dataProvider.groups.map { "\($0.name) (\($0.id))" })")
        if let updatedGroup = dataProvider.groups.first(where: { $0.id == groupId }) {
            print("🔍 GroupDetailsView: Found group: \(updatedGroup.name)")
            currentGroup = updatedGroup
        } else {
            print("🔍 GroupDetailsView: Group not found - may have been deleted")
            currentGroup = nil
            // Clear the selected deck in appState since group no longer exists
            if appState.selectedDeck == groupId {
                appState.selectedDeck = nil
            }
        }
    }
    
    private func startEditingName() {
        isEditingName = true
        if let currentGroup = currentGroup {
            editingName = currentGroup.name
        }
    }
    
    private func cancelNameEdit() {
        isEditingName = false
        if let currentGroup = currentGroup {
            editingName = currentGroup.name
        }
        errorMessage = nil
        showingError = false
    }
    
    private func saveNameChange() {
        guard !editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Group name cannot be empty"
            showingError = true
            return
        }
        
        Task {
            await updateGroupName()
        }
    }
    
    private func updateGroupName() async {
        guard let currentGroup = currentGroup else { return }
        isUpdating = true
        errorMessage = nil
        showingError = false
        
        do {
            try await groupEditingService.updateGroupName(currentGroup.id, newName: editingName)
            isEditingName = false
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        
        isUpdating = false
    }
    
    private func updateGroupColor(_ newColor: Color) {
        Task {
            await performColorUpdate(newColor)
        }
    }
    
    private func performColorUpdate(_ newColor: Color) async {
        guard let currentGroup = currentGroup else { return }
        isUpdating = true
        errorMessage = nil
        showingError = false
        
        do {
            try await groupEditingService.updateGroupColor(currentGroup.id, newColor: newColor)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        
        isUpdating = false
    }
    
    private func addContactToGroup(_ contact: Contact) {
        guard let currentGroup = currentGroup else { return }
        LogManager.shared.info("addContactToGroup called for contact: \(contact.displayName) to group: \(currentGroup.name)")
        
        // Check if contact is already in the group
        guard !currentGroup.memberPhones.contains(contact.phone) else {
            LogManager.shared.info("Contact \(contact.displayName) is already in group \(currentGroup.name)")
            return
        }
        
        Task {
            do {
                LogManager.shared.info("Calling dataProvider.add for contact: \(contact.displayName)")
                // For Group Details page addition, add with Group Details source
                try await dataProvider.addContactWithSource(
                    contactPhone: contact.phone, 
                    contactName: contact.displayName,
                    contactUUID: contact.id.uuidString,
                    to: currentGroup.id, 
                    sourceType: "Group Details",
                    sourceUUID: currentGroup.id.uuidString // Use group ID as source UUID for Group Details
                )
                LogManager.shared.info("Successfully added contact \(contact.displayName) to group \(currentGroup.name) with Group Details source")
                
                // Add a small delay to ensure database save is complete
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                
                // Update the current group to reflect the changes
                updateCurrentGroup()
                
            } catch {
                LogManager.shared.error("Failed to add contact to group: \(error)")
            }
        }
    }
    
    private func deleteCurrentGroup() async {
        guard let currentGroup = currentGroup else { return }
        
        do {
            LogManager.shared.info("Deleting current group from GroupDetailsView: \(currentGroup.name)")
            
            // Delete the group from the database
            try await dataProvider.deleteGroup(currentGroup.id)
            
            // Remove from all canvases
            try await removeGroupFromAllCanvases(currentGroup.id)
            
            // Clear the selection in appState
            await MainActor.run {
                appState.selectedDeck = nil
                // The view will automatically update when currentGroup becomes nil
            }
            
            LogManager.shared.info("Successfully deleted group: \(currentGroup.name)")
        } catch {
            LogManager.shared.error("Failed to delete group: \(error)")
            errorMessage = "Failed to delete group: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func removeGroupFromAllCanvases(_ groupId: UUID) async throws {
        LogManager.shared.info("🧹 Removing group \(groupId) from all canvases")
        
        // Get the global canvas service
        let globalCanvasService = GlobalCanvasService.shared
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

// MARK: - Contact Card View

struct ContactCardView: View {
    let contact: Contact
    let group: ContactGroup
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Contact Avatar
                if let profileImage = contact.profileImage {
                    Image(nsImage: profileImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(contact.initials)
                                .font(.headline)
                                .foregroundColor(.accentColor)
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(contact.phone)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button(action: {
                    removeContactFromGroup()
                }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func removeContactFromGroup() {
        Task {
            do {
                // For Group Details page removal, remove the participant entirely regardless of source count
                // This uses a different approach than canvas overlap detection which only removes specific sources
                try await dataProvider.removeParticipantEntirely(contactPhone: contact.phone, from: group.id)
                LogManager.shared.info("Successfully removed contact \(contact.displayName) from group \(group.name) entirely (Group Details removal)")
            } catch {
                LogManager.shared.error("Failed to remove contact from group: \(error)")
            }
        }
    }
}

// MARK: - Add Members to Group View

struct AddMembersToGroupView: View {
    let group: ContactGroup
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var selectedContacts: Set<UUID> = []
    
    private var availableContacts: [Contact] {
        let filtered = dataProvider.contacts.filter { contact in
            !group.memberPhones.contains(contact.phone) &&
            (searchText.isEmpty || contact.displayName.localizedCaseInsensitiveContains(searchText))
        }
        return filtered.sorted { $0.displayName < $1.displayName }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search contacts...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                // Contacts List
                List(availableContacts, id: \.id) { contact in
                    AddMemberContactRowView(contact: contact, isSelected: selectedContacts.contains(contact.id))
                        .onTapGesture {
                            if selectedContacts.contains(contact.id) {
                                selectedContacts.remove(contact.id)
                            } else {
                                selectedContacts.insert(contact.id)
                            }
                        }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Add Members to \(group.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedContacts.count) Members") {
                        addSelectedContacts()
                    }
                    .disabled(selectedContacts.isEmpty)
                }
            }
        }
        .frame(width: 500, height: 600)
    }
    
    private func addSelectedContacts() {
        let selectedContactObjects = dataProvider.contacts.filter { selectedContacts.contains($0.id) }
        let phoneNumbers = selectedContactObjects.map { $0.phone }
        
        Task {
            do {
                try await dataProvider.add(phones: phoneNumbers, to: group.id)
                LogManager.shared.info("Successfully added \(phoneNumbers.count) contacts to group \(group.name)")
                dismiss()
            } catch {
                LogManager.shared.error("Failed to add contacts to group: \(error)")
            }
        }
    }
}

struct AddMemberContactRowView: View {
    let contact: Contact
    let isSelected: Bool
    
    var body: some View {
        HStack {
            // Contact Avatar
            if let profileImage = contact.profileImage {
                Image(nsImage: profileImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(contact.initials)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.body)
                    .lineLimit(1)
                
                Text(contact.phone)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
    }
}

// MARK: - Preview

struct GroupDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        let dataProvider = SQLiteDataProvider()
        let groupEditingService = GroupEditingService()
        let sampleGroup = ContactGroup(name: "Sample Group", color: .blue)
        
        return GroupDetailsView(
            groupId: sampleGroup.id,
            groupEditingService: groupEditingService
        )
        .environmentObject(dataProvider)
    }
}