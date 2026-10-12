import SwiftUI

struct DeckBuilderView: View {
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var selectionManager: SelectionManager
    @EnvironmentObject var dragDropManager: DragDropManager
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    @State private var selectedDeckId: UUID?
    @State private var showingCreateDeck = false
    @State private var newDeckName = ""
    @StateObject private var groupEditingService = GroupEditingService()
    
    // Computed property to get the current group data from the dataProvider
    private var selectedDeck: ContactGroup? {
        // First try to get from appState.selectedDeck (set by GroupsToolbarView)
        if let appStateSelectedDeck = appState.selectedDeck {
            print("🔍 DeckBuilderView: Looking for group with appState.selectedDeck: \(appStateSelectedDeck)")
            print("🔍 DeckBuilderView: Available groups: \(dataProvider.groups.map { "\($0.name) (\($0.id))" })")
            let foundGroup = dataProvider.groups.first { $0.id == appStateSelectedDeck }
            print("🔍 DeckBuilderView: Found group: \(foundGroup?.name ?? "nil")")
            return foundGroup
        }
        // Fallback to local selectedDeckId
        guard let selectedDeckId = selectedDeckId else { 
            print("🔍 DeckBuilderView: No selectedDeckId, returning nil")
            return nil 
        }
        print("🔍 DeckBuilderView: Looking for group with selectedDeckId: \(selectedDeckId)")
        let foundGroup = dataProvider.groups.first { $0.id == selectedDeckId }
        print("🔍 DeckBuilderView: Found group: \(foundGroup?.name ?? "nil")")
        return foundGroup
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Groups Toolbar (collapsible)
            if appState.isGroupsBarVisible {
                GroupsToolbarView { deck in
                    selectedDeckId = deck?.id
                    // Also update appState.selectedDeck for consistency
                    appState.selectedDeck = deck?.id
                }
                .frame(width: 300)
                .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                // Icon to re-expand groups toolbar
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                appState.toggleGroupsBar()
                            }
                        }) {
                            Image(systemName: "person.2")
                                .font(.title2)
                                .foregroundColor(.primary)
                                .padding(12)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                        .padding(.top, 8)
                    }
                    Spacer()
                }
                .frame(width: 40)
                .background(Color(NSColor.controlBackgroundColor))
                .allowsHitTesting(true)
                .zIndex(1000) // Ensure it's above the content
            }
            
            // Main group content area
            if let selectedDeck = selectedDeck {
                GroupDetailsView(
                    groupId: selectedDeck.id,
                    groupEditingService: groupEditingService
                )
                .environmentObject(dataProvider)
                .onAppear {
                    // Set the dataProvider for GroupEditingService
                    groupEditingService.setDataProvider(dataProvider)
                }
            } else {
                VStack {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("Select a Group")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Choose a group from the groups toolbar to view and edit details")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isGroupsBarVisible)
        .sheet(isPresented: $showingCreateDeck) {
            CreateDeckView { deckName in
                createNewDeck(name: deckName)
            }
        }
        .onAppear {
            // Sync local selectedDeckId with appState.selectedDeck when view appears
            if let appStateSelectedDeck = appState.selectedDeck {
                selectedDeckId = appStateSelectedDeck
            }
        }
        .onChange(of: appState.selectedDeck) { _, newValue in
            // When appState.selectedDeck changes (e.g., from GroupsToolbarView), sync local state
            selectedDeckId = newValue
            print("🔍 DeckBuilderView: appState.selectedDeck changed to: \(newValue?.uuidString ?? "nil")")
        }
    }
    
    private func createNewDeck(name: String) {
        let newDeck = ContactGroup(
            id: UUID(),
            name: name,
            isDeck: true
        )
        
        Task {
            try await dataProvider.createGroup(newDeck)
            selectedDeckId = newDeck.id
        }
    }
}

struct DeckListItemView: View {
    let deck: ContactGroup
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: "rectangle.stack")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(deck.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Text("\(deck.memberPhones.count) cards")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct DeckContentView: View {
    let deck: ContactGroup
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @State private var showingAddCards = false
    private let logger = LogManager.shared
    
    var body: some View {
        VStack {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("\(deck.memberPhones.count) cards")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    showingAddCards = true
                }) {
                    Label("Add Cards", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            // Cards grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)
                ], spacing: 16) {
                    ForEach(Array(deck.memberPhones), id: \.self) { phone in
                        if let contact = dataProvider.contacts.first(where: { $0.phone == phone }) {
                            CardView(contact: contact, deck: deck)
                        }
                    }
                }
                .padding()
            }
        }
        .dropDestination(for: Contact.self) { contacts, location in
            // Handle dropping contacts into this deck
            for contact in contacts {
                addContactToDeck(contact)
            }
            return true
        } isTargeted: { isTargeted in
            // Visual feedback when dragging over the deck content area
        }
        .sheet(isPresented: $showingAddCards) {
            AddCardsToDeckView(deck: deck)
        }
    }
    
    private func addContactToDeck(_ contact: Contact) {
        // Check if contact is already in the deck
        guard !deck.memberPhones.contains(contact.phone) else {
            logger.info("Contact \(contact.displayName) is already in deck \(deck.name)")
            return
        }
        
        Task {
            do {
                try await dataProvider.add(phones: [contact.phone], to: deck.id)
                logger.info("Added contact \(contact.displayName) to deck \(deck.name)")
            } catch {
                logger.error("Failed to add contact to deck: \(error)")
            }
        }
    }
}

struct CardView: View {
    let contact: Contact
    let deck: ContactGroup
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    private let logger = LogManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Contact Photo/Initials on the left
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                if let profileImage = contact.profileImage {
                    Image(nsImage: profileImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 46, height: 46)
                        .clipShape(Circle())
                } else {
                    Text(contact.initials)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            
            // Contact Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(contact.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Button(action: {
                        removeContactFromDeck()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                }
                
                // Email (always show space, even if empty)
                Text(contact.email?.isEmpty == false ? contact.email! : " ")
                    .font(.caption)
                    .foregroundColor(contact.email?.isEmpty == false ? .secondary : .clear)
                    .lineLimit(1)
                
                // Phone (always show)
                Text(contact.phone)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
        .frame(height: 80) // Fixed height for all cards
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
    }
    
    private func removeContactFromDeck() {
        Task {
            do {
                try await dataProvider.remove(phones: [contact.phone], from: deck.id)
                logger.info("Removed contact \(contact.displayName) from deck \(deck.name)")
            } catch {
                logger.error("Failed to remove contact from deck: \(error)")
            }
        }
    }
}

struct CreateDeckView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deckName = ""
    let onCreate: (String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Deck")
                .font(.title2)
                .fontWeight(.bold)
            
            TextField("Deck Name", text: $deckName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Create") {
                    if !deckName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onCreate(deckName.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(deckName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

struct AddCardsToDeckView: View {
    let deck: ContactGroup
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @Environment(\.dismiss) private var dismiss
    @State private var selectedContacts: Set<String> = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Cards to \(deck.name)")
                .font(.title2)
                .fontWeight(.bold)
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(dataProvider.contacts, id: \.phone) { contact in
                        ContactSelectionRow(
                            contact: contact,
                            isSelected: selectedContacts.contains(contact.phone),
                            onToggle: { isSelected in
                                if isSelected {
                                    selectedContacts.insert(contact.phone)
                                } else {
                                    selectedContacts.remove(contact.phone)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 400)
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Add Selected") {
                    // Add selected contacts to deck
                    Task {
                        for phone in selectedContacts {
                            try await dataProvider.add(phones: [phone], to: deck.id)
                        }
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedContacts.isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 600)
    }
}

struct ContactSelectionRow: View {
    let contact: Contact
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        Button(action: {
            onToggle(!isSelected)
        }) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text(contact.phone)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DeckBuilderView()
        .environmentObject(SQLiteDataProvider())
        .environmentObject(AppState())
        .environmentObject(SelectionManager())
        .environmentObject(DragDropManager())
        .environmentObject(GlobalCanvasService.shared)
}
