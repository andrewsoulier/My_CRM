import SwiftUI
import UniformTypeIdentifiers
import Combine

struct ContactsBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var selectionManager: SelectionManager
    @EnvironmentObject var dragDropManager: DragDropManager
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    
    private let logger = LogManager.shared
    private let fuzzyMatcher = FuzzyMatcher()
    
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Contacts")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    appState.toggleContactsBar()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Search and Sort Controls
            VStack(spacing: 8) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search contacts...", text: $appState.searchTerm)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .onChange(of: appState.searchTerm) { _, newValue in
                            performSearch(query: newValue)
                        }
                        .onKeyPress(.escape) {
                            clearSearch()
                            return .handled
                        }
                    
                    // X button to clear search (only show when search is active)
                    if !appState.searchTerm.isEmpty {
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
                
                // Sort Controls
                HStack {
                    Picker("Sort by", selection: $appState.sortOption) {
                        ForEach(ContactFilter.ContactSortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: appState.sortOption) { _, newSortOption in
                        Task {
                            await globalCanvasService.contactsViewModel.loadContacts(from: dataProvider, sortOption: newSortOption)
                        }
                    }
                    
                    Spacer()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Contacts List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        let contactsToDisplay = appState.searchTerm.isEmpty ? globalCanvasService.contactsViewModel.displayedContacts : globalCanvasService.contactsViewModel.searchResults
                        
                        if contactsToDisplay.isEmpty && !globalCanvasService.contactsViewModel.isLoading {
                            VStack(spacing: 16) {
                                if globalCanvasService.contactsViewModel.isInitialLoadComplete {
                                    Image(systemName: appState.searchTerm.isEmpty ? "person.2.slash" : "magnifyingglass")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)
                                    
                                    Text(appState.searchTerm.isEmpty ? "No Contacts Found" : "No Search Results")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text(appState.searchTerm.isEmpty ? 
                                         "Your contacts list is empty. Import contacts using the Python scripts or check the database path in Settings." :
                                         "No contacts found matching '\(appState.searchTerm)'")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                    
                                    if appState.searchTerm.isEmpty {
                                        Button("Open Settings") {
                                            appState.showingSettings = true
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .padding(.top, 8)
                                    }
                                } else {
                                    ProgressView("Loading contacts...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(40)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ForEach(contactsToDisplay) { contact in
                                ContactRowView(contact: contact)
                                    .environmentObject(globalCanvasService)
                                    .id(contact.phone)
                            }
                            
                            if globalCanvasService.contactsViewModel.isLoading {
                                ProgressView()
                                    .padding()
                            }
                        }
                    }
                }
                .onChange(of: selectionManager.focusedContactIndex) { _, newIndex in
                    // Scroll to focused contact when navigating with keyboard
                    if !selectionManager.contactListContext.isEmpty && newIndex < selectionManager.contactListContext.count {
                        let focusedPhone = selectionManager.contactListContext[newIndex]
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(focusedPhone, anchor: .center)
                        }
                    }
                }
            }
            .onKeyPress { keyPress in
                return handleKeyPress(keyPress)
            }
            .onAppear {
                logger.info("🎯 ContactsBarView: onAppear triggered")
                logger.info("🎯 ContactsBarView: Current state - isInitialLoadComplete: \(globalCanvasService.contactsViewModel.isInitialLoadComplete), isLoading: \(globalCanvasService.contactsViewModel.isLoading)")
                logger.info("🎯 ContactsBarView: dataProvider.contacts.count = \(dataProvider.contacts.count)")
                logger.info("🎯 ContactsBarView: allContacts.count = \(globalCanvasService.contactsViewModel.allContacts.count), displayedContacts.count = \(globalCanvasService.contactsViewModel.displayedContacts.count)")
                logger.info("🎯 ContactsBarView: dataProvider.isConnectedToDatabase = \(dataProvider.isConnectedToDatabase)")
                
                // Only load contacts if not already loaded and not currently loading
                if !globalCanvasService.contactsViewModel.isInitialLoadComplete && 
                   !globalCanvasService.contactsViewModel.isLoading {
                    logger.info("🎯 ContactsBarView: Loading contacts for first time")
                    loadAllContacts()
                } else {
                    logger.info("🎯 ContactsBarView: Already loaded, skipping loadAllContacts()")
                }
                
                // Initialize focus to first contact if no selection exists
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if selectionManager.contactListContext.isEmpty && !globalCanvasService.contactsViewModel.displayedContacts.isEmpty {
                        let phones = globalCanvasService.contactsViewModel.displayedContacts.map { $0.phone }
                        selectionManager.updateContactListContext(phones)
                        selectionManager.focusedContactIndex = 0
                    }
                }
            }
            .refreshable {
                // Force refresh when user pulls down
                await Task {
                    await globalCanvasService.contactsViewModel.loadContacts(from: dataProvider, sortOption: appState.sortOption)
                }.value
            }
            .onChange(of: appState.searchTerm.isEmpty ? globalCanvasService.contactsViewModel.displayedContacts.count : globalCanvasService.contactsViewModel.searchResults.count) { _, _ in
                // Update selection manager context when contacts change
                let contactsToDisplay = appState.searchTerm.isEmpty ? globalCanvasService.contactsViewModel.displayedContacts : globalCanvasService.contactsViewModel.searchResults
                let phones = contactsToDisplay.map { $0.phone }
                selectionManager.updateContactListContext(phones)
                
                // Ensure focused index is valid after context update
                if selectionManager.focusedContactIndex >= phones.count {
                    selectionManager.focusedContactIndex = max(0, phones.count - 1)
                }
            }
            .onChange(of: globalCanvasService.currentCanvas) { oldCanvas, newCanvas in
                // Filter out canvas contacts when canvas changes (only when not searching)
                if appState.searchTerm.isEmpty {
                    // Only apply filter if the canvas actually changed (not just a reference update)
                    if oldCanvas?.elements.count != newCanvas?.elements.count {
                        globalCanvasService.contactsViewModel.filterCanvasContacts(canvasContactPhones: globalCanvasService.canvasContactPhones)
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(.separatorColor)),
            alignment: .trailing
        )
        .onTapGesture {
            // Unfocus search bar when clicking anywhere in the contacts bar
            isSearchFocused = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UnfocusSearchBar"))) { _ in
            // Unfocus search bar when clicking anywhere in the app
            isSearchFocused = false
        }
    }
    
    // MARK: - Private Methods
    
    private func loadAllContacts() {
        logger.info("📞 ContactsBarView: loadAllContacts() called")
        logger.info("📞 ContactsBarView: isLoading = \(globalCanvasService.contactsViewModel.isLoading)")
        print("🔍 DEBUG: ContactsBarView.loadAllContacts() called")
        
        guard !globalCanvasService.contactsViewModel.isLoading else { 
            logger.warning("📞 ContactsBarView: Already loading, skipping...")
            return 
        }
        
        logger.info("📞 ContactsBarView: Starting async load...")
        Task {
            await globalCanvasService.contactsViewModel.loadContacts(from: dataProvider, sortOption: appState.sortOption)
            // Don't apply canvas filter on initial load - let all contacts show
            // Filter will be applied when canvas actually changes via onChange handler
        }
    }
    
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            globalCanvasService.contactsViewModel.searchResults = []
            // When search is cleared, apply canvas filter to displayed contacts
            globalCanvasService.contactsViewModel.filterCanvasContacts(canvasContactPhones: globalCanvasService.canvasContactPhones)
            return
        }
        
        // Search through all loaded contacts
        guard !globalCanvasService.contactsViewModel.allContacts.isEmpty else {
            globalCanvasService.contactsViewModel.searchResults = []
            return
        }
        
        let results = fuzzyMatcher.search(query: query, in: globalCanvasService.contactsViewModel.allContacts)
        globalCanvasService.contactsViewModel.searchResults = results.map { $0.item }
    }
    
    private func clearSearch() {
        appState.searchTerm = ""
        isSearchFocused = false
        globalCanvasService.contactsViewModel.searchResults = []
        // Apply canvas filter to displayed contacts when search is cleared
        globalCanvasService.contactsViewModel.filterCanvasContacts(canvasContactPhones: globalCanvasService.canvasContactPhones)
    }
    
    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        // Handle keyboard navigation for contacts list
        // Only handle keys when search bar is not focused
        guard !isSearchFocused else {
            return .ignored
        }
        
        let modifiers = keyPress.modifiers
        let key = keyPress.key
        
        // Handle selection and navigation keys
        switch key {
        case .escape:
            selectionManager.clearAllSelections()
            return .handled
            
        case KeyEquivalent("a"):
            if modifiers.contains(.command) {
                selectionManager.selectAllContacts()
                return .handled
            }
            
        case .upArrow:
            selectionManager.moveFocusUp(modifiers: modifiers)
            return .handled
            
        case .downArrow:
            selectionManager.moveFocusDown(modifiers: modifiers)
            return .handled
            
        default:
            break
        }
        
        return .ignored
    }
}

struct ContactRowView: View {
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
    
    private var displayText: String {
        contact.displayName.isEmpty || contact.displayName == contact.phone ? "no name saved" : contact.displayName
    }
    
    private var isNoName: Bool {
        contact.displayName.isEmpty || contact.displayName == contact.phone
    }
    
    private var isInCanvas: Bool {
        globalCanvasService.canvasContactPhones.contains(contact.phone)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile Image/Initials
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                if let profileImage = contact.profileImage {
                    Image(nsImage: profileImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .onAppear {
                            print("🖼️ Displaying profile image for contact: \(contact.displayName) (\(contact.phone))")
                        }
                } else {
                    Text(contact.initials)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                        .onAppear {
                            print("🔤 Displaying initials '\(contact.initials)' for contact: \(contact.displayName) (\(contact.phone))")
                        }
                }
            }
            
            // Contact Info
            VStack(alignment: .leading, spacing: 2) {
                Text(displayText)
                    .font(.system(size: 14, weight: .medium))
                    .italic(isNoName)
                    .foregroundColor(isNoName ? .secondary : .primary)
                    .lineLimit(1)
                
                Text(contact.phone)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let business = contact.business, !business.isEmpty {
                    Text(business)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let email = contact.email, !email.isEmpty {
                    Text(email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Canvas indicator (only show in search results)
            if isInCanvas {
                Image(systemName: "rectangle.3.group")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.trailing, 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selectionManager.isContactSelected(contact.phone) ? Color.accentColor.opacity(0.15) : Color.clear)
                .stroke(selectionManager.isContactSelected(contact.phone) ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                .overlay(
                    // Focus indicator
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: isFocused ? 2 : 0)
                        .animation(.easeInOut(duration: 0.1), value: isFocused)
                )
        )
        .contentShape(Rectangle()) // Makes entire area clickable
        .onTapGesture {
            handleContactSelection()
        }
        .draggable(contact) {
            DragDropLogger.shared.logDragStart(contact: contact, source: "ContactsBarView")
            DragDropLogger.shared.logProviderCreation(contact: contact, typeIdentifier: UTType.vCard.identifier)
            
            // Use SwiftUI's Transferable system
            DragDropLogger.shared.log("Using SwiftUI Transferable for drag", operation: "TRANSFERABLE")
            return DragPreview(count: 1)
        }
        .contextMenu {
            Button("Add to Canvas") {
                addContactToCanvas()
            }
            
            Button("Add to Group") {
                // TODO: Implement add to group
            }
            
            Button("Add Tag") {
                // TODO: Implement add tag
            }
            
            Button("Start Deck") {
                // TODO: Implement start deck
            }
            
            Divider()
            
            Button("Open in Contacts") {
                // TODO: Implement open in contacts
            }
            
            Button("Copy Phone") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(contact.phone, forType: .string)
            }
            
            if let email = contact.email {
                Button("Copy Email") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(email, forType: .string)
                }
            }
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
        // Add contact to canvas using the global service
        GlobalCanvasService.shared.addContactToCanvas(contact)
    }
}

#Preview {
    ContactsBarView()
        .environmentObject(AppState())
        .environmentObject(SQLiteDataProvider())
        .environmentObject(SelectionManager())
        .environmentObject(DragDropManager())
}