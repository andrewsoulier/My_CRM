import SwiftUI

struct RecipientSearchField: View {
    @Binding var searchText: String
    let dataProvider: SQLiteDataProvider
    let onContactSelected: (Contact) -> Void
    let onGroupSelected: (ContactGroup) -> Void
    
    @State private var showingSuggestions = false
    @State private var filteredContacts: [Contact] = []
    @State private var filteredGroups: [ContactGroup] = []
    @FocusState private var isSearchFocused: Bool
    
    // Creation modal states
    @State private var showingContactCreationModal = false
    @State private var showingGroupCreationModal = false
    @State private var pendingContactName: String = ""
    @State private var pendingGroupName: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search contacts or groups...", text: $searchText)
                    .focused($isSearchFocused)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _, _ in
                        updateSuggestions()
                    }
                    .onChange(of: isSearchFocused) { _, _ in
                        // Do not strictly gate by focus; visibility handled by results
                        updateSuggestions()
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        showingSuggestions = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
            
            // Suggestions dropdown
            if showingSuggestions {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            // Contact suggestions
                            if !filteredContacts.isEmpty {
                                suggestionSectionHeader("Contacts")
                                
                                ForEach(filteredContacts.prefix(5), id: \.id) { contact in
                                    ContactSuggestionRow(contact: contact) {
                                        onContactSelected(contact)
                                        searchText = ""
                                        showingSuggestions = false
                                        isSearchFocused = false
                                    }
                                }
                            }
                            
                            // Group suggestions
                            if !filteredGroups.isEmpty {
                                if !filteredContacts.isEmpty {
                                    Divider()
                                        .padding(.vertical, 4)
                                }
                                
                                suggestionSectionHeader("Groups")
                                
                                ForEach(filteredGroups.prefix(5), id: \.id) { group in
                                    GroupSuggestionRow(group: group) {
                                        onGroupSelected(group)
                                        searchText = ""
                                        showingSuggestions = false
                                        isSearchFocused = false
                                    }
                                }
                            }
                            
                            // Create new options when no matches found
                            if filteredContacts.isEmpty && filteredGroups.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Divider()
                                    .padding(.vertical, 4)
                                
                                suggestionSectionHeader("Create New")
                                
                                // Create new contact option
                                CreateNewSuggestionRow(
                                    icon: "person.badge.plus",
                                    title: "Create Contact: \"\(searchText)\"",
                                    subtitle: "Add as new contact",
                                    color: .blue
                                ) {
                                    pendingContactName = searchText
                                    showingContactCreationModal = true
                                    showingSuggestions = false
                                }
                                
                                // Create new group option
                                CreateNewSuggestionRow(
                                    icon: "person.3.badge.plus",
                                    title: "Create Group: \"\(searchText)\"",
                                    subtitle: "Add as new group",
                                    color: .green
                                ) {
                                    pendingGroupName = searchText
                                    showingGroupCreationModal = true
                                    showingSuggestions = false
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .zIndex(10)
            }
        }
        .onAppear {
            updateSuggestions()
        }
        .sheet(isPresented: $showingContactCreationModal) {
            ContactCreationModal(
                initialName: pendingContactName,
                isPresented: $showingContactCreationModal,
                onContactCreated: { contact in
                    onContactSelected(contact)
                    searchText = ""
                    pendingContactName = ""
                }
            )
            .environmentObject(dataProvider)
        }
        .sheet(isPresented: $showingGroupCreationModal) {
            GroupCreationModal(
                initialName: pendingGroupName,
                isPresented: $showingGroupCreationModal,
                onGroupCreated: { group in
                    onGroupSelected(group)
                    searchText = ""
                    pendingGroupName = ""
                }
            )
            .environmentObject(dataProvider)
        }
    }
    
    private func suggestionSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
    
    private func updateSuggestions() {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedSearch.isEmpty {
            showingSuggestions = false
            filteredContacts = []
            filteredGroups = []
            return
        }
        
        // Filter contacts
        filteredContacts = dataProvider.contacts.filter { contact in
            contact.displayName.localizedCaseInsensitiveContains(trimmedSearch) ||
            contact.phone.localizedCaseInsensitiveContains(trimmedSearch) ||
            (contact.email?.localizedCaseInsensitiveContains(trimmedSearch) == true) ||
            (contact.business?.localizedCaseInsensitiveContains(trimmedSearch) == true)
        }.sorted { $0.displayName < $1.displayName }
        
        // Filter groups
        filteredGroups = dataProvider.groups.filter { group in
            group.name.localizedCaseInsensitiveContains(trimmedSearch)
        }.sorted { $0.name < $1.name }
        
        // Show suggestions if we have matches OR if we have search text (to show create options)
        showingSuggestions = (!filteredContacts.isEmpty || !filteredGroups.isEmpty || !trimmedSearch.isEmpty)
    }
}

struct CreateNewSuggestionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundColor(color)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .font(.caption)
                    .foregroundColor(color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
        )
    }
}

struct ContactSuggestionRow: View {
    let contact: Contact
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar or icon
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(contact.displayName.prefix(1).uppercased())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(contact.phone)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if let business = contact.business, !business.isEmpty {
                        Text(business)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
        )
        .onHover { hovering in
            // Add hover effect if needed
        }
    }
}

struct GroupSuggestionRow: View {
    let group: ContactGroup
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Group icon
                Circle()
                    .fill(group.color.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.3.fill")
                            .font(.caption)
                            .foregroundColor(group.color)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(group.memberPhones.count) members")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "person.3.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
        )
        .onHover { hovering in
            // Add hover effect if needed
        }
    }
}
