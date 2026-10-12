import SwiftUI
import Combine

@MainActor
class GroupsMapViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var contacts: [ContactNode] = []
    @Published var groups: [GroupCircle] = []
    @Published var canvasState: CanvasState = CanvasState()
    @Published var currentMapId: UUID = UUID()
    @Published var isLoading: Bool = false // Add loading flag to prevent saves during canvas switching
    @Published var isDragging: Bool = false // Add dragging flag to prevent saves during drag operations
    private var isUpdatingZoom: Bool = false // Flag to prevent recursive zoom updates
    
    // MARK: - Private Properties
    private let repository: CanvasRepository
    private var dataProvider: SQLiteDataProvider?
    private let groupManager = GroupManager()
    private var saveDebounceTimer: Timer?
    private var dragMonitorTimer: Timer?
    private var lastSaveTime: Date = Date()
    private var undoManager: UndoManager?
    private let minimumSaveInterval: TimeInterval = 0.5 // Minimum 500ms between saves
    private var wasDragging: Bool = false // Track previous dragging state
    private var canvasLoadingRetryCount: Int = 0 // Track retry attempts
    private let maxCanvasLoadingRetries: Int = 10 // Maximum retry attempts
    
    // MARK: - App State Access
    @Published var appState: AppState?
    
    // MARK: - Selection State
    @Published var selectedContacts: Set<UUID> = []
    @Published var selectedGroups: Set<UUID> = []
    

    
    // MARK: - Mode State
    @Published var isSelectionMode = true // V key
    @Published var isGroupAddMode = false // G key
    
    // MARK: - Computed Properties
    var isHandMode: Bool {
        return canvasState.mode == .hand
    }
    
    // Show transform handles only when exactly one group is selected and no contacts are selected
    var shouldShowTransformHandles: Bool {
        return selectedGroups.count == 1 && selectedContacts.isEmpty
    }
    
    // Get the single selected group for transform operations
    var selectedGroupForTransforms: GroupCircle? {
        guard shouldShowTransformHandles else { return nil }
        return groups.first { selectedGroups.contains($0.id) }
    }
    
    // Debug settings access
    var debugSettings: DebugSettings {
        return appState?.debugSettings ?? DebugSettings()
    }
    
    // MARK: - Initialization
    init(repository: CanvasRepository = DatabaseCanvasRepository(), undoManager: UndoManager? = nil, appState: AppState? = nil, dataProvider: SQLiteDataProvider? = nil) {
        print("🚨 GroupsMapViewModel.init() called!")
        self.repository = repository
        self.undoManager = undoManager
        self.appState = appState
        self.dataProvider = dataProvider
        
        // Defer database loading to prevent blocking the main thread during initialization
        DispatchQueue.main.async {
            self.loadInitialCanvas()
        }
    }
    
    // MARK: - Data Provider Management
    func setDataProvider(_ dataProvider: SQLiteDataProvider?) {
        self.dataProvider = dataProvider
        print("🔧 GroupsMapViewModel: DataProvider set")
    }
    
    private func loadInitialCanvas() {
        // Try to load existing canvas from database first
        if let dbRepository = repository as? DatabaseCanvasRepository {
            print("🔧 Checking for existing canvases...")
            let allCanvases = dbRepository.getAllCanvases(type: .groupMap)
            print("🔧 Found \(allCanvases.count) existing canvases")
            
            // Get dataProvider from the passed parameter or try to get it from GlobalCanvasService as fallback
            let dataProvider = self.dataProvider ?? self.dataProvider
            print("🔧 DataProvider available: \(dataProvider != nil)")
            
            // CRITICAL: Check if dataProvider is available and connected
            if let dataProvider = dataProvider, dataProvider.isConnectedToDatabase {
                print("✅ DataProvider is available and connected to database")
                print("📊 DataProvider has \(dataProvider.contacts.count) contacts loaded")
                
                if let lastEditedCanvas = dbRepository.getLastEditedCanvas(type: .groupMap) {
                    // Use the existing canvas
                    currentMapId = UUID(uuidString: lastEditedCanvas.id) ?? UUID()
                    loadCanvasFromDatabase(lastEditedCanvas, dataProvider: dataProvider)
                    print("🔧 Loaded existing canvas: \(lastEditedCanvas.name) with ID: \(lastEditedCanvas.id)")
                    print("🔧 Canvas has \(lastEditedCanvas.elements.count) elements")
                } else {
                    print("🔧 No last edited canvas found")
                    // Only create a new canvas if there are NO canvases at all
                    if allCanvases.isEmpty {
                        print("🔧 No canvases exist, creating new one")
                        // Create a new canvas in the database
                        var newCanvasState = CanvasState()
                        newCanvasState.mode = .select // Ensure default mode is selection
                        let newCanvas = Canvas(
                            id: currentMapId.uuidString,
                            name: "Default Canvas",
                            elements: [],
                            canvasType: .groupMap,
                            canvasState: newCanvasState
                        )
                        let success = dbRepository.createCanvas(newCanvas)
                        if success {
                            print("🔧 Created new canvas in database: \(newCanvas.name)")
                        } else {
                            print("❌ Failed to create new canvas in database")
                        }
                    } else {
                        print("🔧 Using first available canvas")
                        // Use the first available canvas
                        let firstCanvas = allCanvases.first!
                        currentMapId = UUID(uuidString: firstCanvas.id) ?? UUID()
                        loadCanvasFromDatabase(firstCanvas, dataProvider: dataProvider)
                        print("🔧 Loaded first available canvas: \(firstCanvas.name) with ID: \(firstCanvas.id)")
                    }
                }
            } else {
                print("⚠️ DataProvider not available or not connected - delaying canvas loading")
                print("⚠️ DataProvider available: \(dataProvider != nil)")
                if let dataProvider = dataProvider {
                    print("⚠️ DataProvider connected: \(dataProvider.isConnectedToDatabase)")
                    print("⚠️ DataProvider contact count: \(dataProvider.contacts.count)")
                }
                
                // Delay canvas loading until dataProvider is available
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.retryCanvasLoading()
                }
            }
        } else {
            // No database repository available
            print("❌ No database repository available")
        }
        
        print("🚨 GroupsMapViewModel.init() completed!")
    }
    
    private func retryCanvasLoading() {
        canvasLoadingRetryCount += 1
        print("🔄 Retrying canvas loading... (attempt \(canvasLoadingRetryCount)/\(maxCanvasLoadingRetries))")
        
        // Check if we've exceeded maximum retries
        if canvasLoadingRetryCount > maxCanvasLoadingRetries {
            print("❌ Maximum canvas loading retries exceeded - giving up")
            print("❌ Canvas will remain empty until manual refresh")
            return
        }
        
        // Get dataProvider from the instance property
        let dataProvider = self.dataProvider
        
        // Check if dataProvider is now available and connected
        if let dataProvider = dataProvider, dataProvider.isConnectedToDatabase {
            print("✅ DataProvider is now available and connected - loading canvas")
            print("📊 DataProvider has \(dataProvider.contacts.count) contacts loaded")
            
            // Load the canvas now that dataProvider is available
            let dbRepository = DatabaseCanvasRepository()
            let allCanvases = dbRepository.getGroupMapCanvasesOrdered()
            
            if let lastEditedCanvas = dbRepository.getLastEditedCanvas(type: .groupMap) {
                currentMapId = UUID(uuidString: lastEditedCanvas.id) ?? UUID()
                loadCanvasFromDatabase(lastEditedCanvas, dataProvider: dataProvider)
                print("🔧 Loaded existing canvas: \(lastEditedCanvas.name) with ID: \(lastEditedCanvas.id)")
            } else if !allCanvases.isEmpty {
                let firstCanvas = allCanvases.first!
                currentMapId = UUID(uuidString: firstCanvas.id) ?? UUID()
                loadCanvasFromDatabase(firstCanvas, dataProvider: dataProvider)
                print("🔧 Loaded first available canvas: \(firstCanvas.name) with ID: \(firstCanvas.id)")
            }
        } else {
            print("⚠️ DataProvider still not available - will retry again in 2 seconds")
            print("⚠️ DataProvider available: \(dataProvider != nil)")
            if let dataProvider = dataProvider {
                print("⚠️ DataProvider connected: \(dataProvider.isConnectedToDatabase)")
            }
            
            // Retry again with a longer delay to avoid infinite rapid retries
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.retryCanvasLoading()
            }
        }
    }
    
    /// Refresh contact data when dataProvider becomes available
    func refreshContactData() {
        print("🔄 Refreshing contact data...")
        
        // Get the current canvas and dataProvider
        let dataProvider = self.dataProvider
        guard let dataProvider = dataProvider, dataProvider.isConnectedToDatabase else {
            print("⚠️ Cannot refresh contact data - dataProvider not available or not connected")
            return
        }
        
        print("✅ DataProvider is available for contact refresh")
        print("📊 DataProvider has \(dataProvider.contacts.count) contacts loaded")
        
        // Refresh each contact node with database data
        var updatedContacts: [ContactNode] = []
        
        for contact in contacts {
            print("🔄 Refreshing contact: \(contact.name) (\(contact.phone))")
            
            if let dbContact = dataProvider.getContact(by: contact.phone) {
                // Update contact with fresh data from database
                var updatedContact = contact
                updatedContact.name = dbContact.displayName
                updatedContact.phone = dbContact.phone
                updatedContact.profilePhotoData = dbContact.profilePhotoData
                updatedContacts.append(updatedContact)
                print("✅ Updated contact: \(dbContact.displayName) (\(dbContact.phone))")
            } else {
                print("⚠️ Contact not found in database: \(contact.phone)")
                updatedContacts.append(contact) // Keep original if not found
            }
        }
        
        // Update the contacts array
        contacts = updatedContacts
        print("✅ Contact data refresh completed - updated \(updatedContacts.count) contacts")
    }
    
    deinit {
        dragMonitorTimer?.invalidate()
        dragMonitorTimer = nil
    }
    

    

    
    private func saveCanvasToDatabase() {
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "SAVE_CANVAS_TO_DATABASE_CALLED",
            details: "saveCanvasToDatabase() called for canvas ID: \(currentMapId) with \(contacts.count) contacts and \(groups.count) groups",
            success: true
        )
        
        print("🔧 saveCanvasToDatabase() called")
        print("🔧 Converting \(contacts.count) contacts and \(groups.count) groups to canvas elements")
        
        // Always save canvas state, even if empty - this ensures zoom, pan, and other state is preserved
        let totalElements = contacts.count + groups.count
        if totalElements == 0 {
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "SAVE_CANVAS_TO_DATABASE_EMPTY_CANVAS",
                details: "Saving empty canvas with state only (contacts: \(contacts.count), groups: \(groups.count))",
                success: true
            )
            print("🔧 Saving empty canvas with state only (contacts: \(contacts.count), groups: \(groups.count))")
        }
        
        // Convert current state to Canvas format
        let canvasElements = contacts.map { $0.toCanvasElement() } + groups.compactMap { $0.toCanvasElement() }
        
        print("🔧 Created \(canvasElements.count) canvas elements")
        
        // Debug: Print element details
        for (index, element) in canvasElements.enumerated() {
            print("🔧 Canvas Element \(index): ID=\(element.id), Type=\(element.elementType.rawValue), Location=\(element.location)")
        }
        
        // Check if the canvas exists in the database
        let canvasIdString = currentMapId.uuidString
        let dbRepository = DatabaseCanvasRepository()
        if let existingCanvas = dbRepository.getCanvas(id: canvasIdString) {
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "SAVE_CANVAS_TO_DATABASE_UPDATE",
                details: "Updating existing canvas: \(existingCanvas.name) (ID: \(canvasIdString)) with \(canvasElements.count) elements",
                success: true
            )
            
            print("🔧 Canvas exists in database, updating: \(existingCanvas.name)")
            print("🔧 Existing canvas had \(existingCanvas.elements.count) elements")
            
            // Preserve the existing canvas name and timestamps
            var updatedCanvas = Canvas(
                id: canvasIdString,
                name: existingCanvas.name, // Preserve existing name
                elements: canvasElements,
                canvasType: existingCanvas.canvasType,
                canvasState: canvasState
            )
            // Preserve existing timestamps but update lastSaved
            updatedCanvas.dateCreated = existingCanvas.dateCreated
            updatedCanvas.dateUpdated = existingCanvas.dateUpdated
            updatedCanvas.lastSaved = Date() // Set current timestamp for save operation
            
            let success = dbRepository.updateCanvas(updatedCanvas)
            
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "SAVE_CANVAS_TO_DATABASE_UPDATE_RESULT",
                details: "Canvas update result: \(success ? "SUCCESS" : "FAILED") for \(updatedCanvas.name) (ID: \(canvasIdString))",
                success: success
            )
            
            print("🔧 Canvas update result: \(success ? "SUCCESS" : "FAILED")")
            
            // Update GlobalCanvasService with the new canvas state to trigger contact filter updates
            // DISABLED: This was causing infinite loops by triggering objectWillChange.send()
            // if success {
            //     GlobalCanvasService.shared.updateCurrentCanvasState(updatedCanvas)
            // }
            
        } else {
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "SAVE_CANVAS_TO_DATABASE_CREATE",
                details: "Creating new canvas with ID: \(canvasIdString) and \(canvasElements.count) elements",
                success: true
            )
            
            print("🔧 Canvas does not exist in database, creating new one")
            
            var newCanvas = Canvas(
                id: canvasIdString,
                name: "Group Map Canvas",
                elements: canvasElements,
                canvasType: .groupMap,
                canvasState: canvasState
            )
            // Set lastSaved timestamp for new canvas
            newCanvas.lastSaved = Date()
        
            let success = dbRepository.createCanvas(newCanvas)
            
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "SAVE_CANVAS_TO_DATABASE_CREATE_RESULT",
                details: "Canvas creation result: \(success ? "SUCCESS" : "FAILED") for new canvas (ID: \(canvasIdString))",
                success: success
            )
            
            print("🔧 Canvas creation result: \(success ? "SUCCESS" : "FAILED")")
            
            // Update GlobalCanvasService with the new canvas state to trigger contact filter updates
            // DISABLED: This was causing infinite loops by triggering objectWillChange.send()
            // if success {
            //     GlobalCanvasService.shared.updateCurrentCanvasState(newCanvas)
            // }
        }
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "SAVE_CANVAS_TO_DATABASE_COMPLETED",
            details: "Canvas save to database completed for ID: \(canvasIdString) with \(canvasElements.count) elements",
            success: true
        )
    }
    
    func saveImmediately() {
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "SAVE_IMMEDIATELY_CALLED",
            details: "saveImmediately() called with \(contacts.count) contacts and \(groups.count) groups",
            success: true
        )
        
        print("🔧 saveImmediately() called")
        print("🔍 DEBUG: saveImmediately() called - contacts: \(contacts.count), groups: \(groups.count), isLoading: \(isLoading), isDragging: \(isDragging)")
        print("🔧 Current state: \(contacts.count) contacts, \(groups.count) groups, isLoading=\(isLoading), isDragging=\(isDragging)")
        
        // Guard 1: Prevent saving during loading/canvas switching
        guard !isLoading else {
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "SAVE_IMMEDIATELY_SKIPPED_LOADING",
                details: "Save skipped - Currently loading canvas (isLoading=\(isLoading))",
                success: false
            )
            print("🚫 saveImmediately() SKIPPED - Currently loading canvas")
            return
        }
        
        // Guard 2: Prevent saving during drag operations
        guard !isDragging else {
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "SAVE_IMMEDIATELY_SKIPPED_DRAGGING",
                details: "Save skipped - Currently dragging (isDragging=\(isDragging))",
                success: false
            )
            print("🚫 saveImmediately() SKIPPED - Currently dragging")
            return
        }
        
        // Guard 3: Prevent saving if no elements exist (prevents clearing canvas)
        let totalElements = contacts.count + groups.count
        guard totalElements > 0 else {
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "SAVE_IMMEDIATELY_SKIPPED_EMPTY",
                details: "Save skipped - No elements to save (contacts: \(contacts.count), groups: \(groups.count))",
                success: false
            )
            print("🚫 saveImmediately() SKIPPED - No elements to save (contacts: \(contacts.count), groups: \(groups.count))")
            
            // Even when save is skipped, update GlobalCanvasService to ensure contact filter updates
            updateGlobalCanvasServiceForEmptyCanvas()
            return
        }
        
        // Guard 4: Rate limiting - prevent excessive saves
        let timeSinceLastSave = Date().timeIntervalSince(lastSaveTime)
        guard timeSinceLastSave >= minimumSaveInterval else {
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "SAVE_IMMEDIATELY_SKIPPED_RATE_LIMIT",
                details: "Save skipped - Rate limited (last save was \(String(format: "%.2f", timeSinceLastSave))s ago, minimum interval: \(minimumSaveInterval)s)",
                success: false
            )
            print("🚫 saveImmediately() SKIPPED - Rate limited (last save was \(String(format: "%.2f", timeSinceLastSave))s ago)")
            return
        }
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "SAVE_IMMEDIATELY_PROCEEDING",
            details: "Save proceeding with \(totalElements) elements after \(String(format: "%.2f", timeSinceLastSave))s",
            success: true
        )
        
        print("✅ saveImmediately() proceeding with \(totalElements) elements")
        updateStateFromSelection()
        saveCanvasToDatabase()
        lastSaveTime = Date()
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "SAVE_IMMEDIATELY_COMPLETED",
            details: "Save completed successfully with \(totalElements) elements",
            success: true
        )
    }
    
    /// Update GlobalCanvasService when canvas becomes empty (to ensure contact filter updates)
    private func updateGlobalCanvasServiceForEmptyCanvas() {
        let emptyCanvas = Canvas(
            id: currentMapId.uuidString,
            name: "Group Map Canvas",
            elements: [],
            canvasType: .groupMap,
            canvasState: canvasState
        )
        // DISABLED: This was causing infinite loops by triggering objectWillChange.send()
        // GlobalCanvasService.shared.updateCurrentCanvasState(emptyCanvas)
    }
    
    // MARK: - Selection Management
    private func updateSelectionFromState() {
        selectedContacts = Set(contacts.filter { canvasState.selection.contains($0.id) }.map { $0.id })
        selectedGroups = Set(groups.filter { canvasState.selection.contains($0.id) }.map { $0.id })
    }
    
    func updateStateFromSelection() {
        canvasState.selection = selectedContacts.union(selectedGroups)
    }
    
    func selectContact(_ contactId: UUID, addToSelection: Bool = false) {
        if addToSelection {
            selectedContacts.insert(contactId)
        } else {
            selectedContacts = [contactId]
            selectedGroups.removeAll()
        }
        updateStateFromSelection()
        // REMOVED: saveImmediately() - selection changes should not trigger saves
    }
    
    func selectGroup(_ groupId: UUID, addToSelection: Bool = false) {
        print("🔧 GroupsMapViewModel: selectGroup called for group \(groupId), addToSelection: \(addToSelection)")
        
        if addToSelection {
            selectedGroups.insert(groupId)
            print("🔧 GroupsMapViewModel: Added group to selection, total selected: \(selectedGroups.count)")
        } else {
            selectedGroups = [groupId]
            selectedContacts.removeAll()
            print("🔧 GroupsMapViewModel: Single group selection, selected groups: \(selectedGroups.count), selected contacts: \(selectedContacts.count)")
        }
        
        // Log transform handles state
        print("🔧 GroupsMapViewModel: shouldShowTransformHandles: \(shouldShowTransformHandles)")
        
        updateStateFromSelection()
        // REMOVED: saveImmediately() - selection changes should not trigger saves
    }
    
    func clearSelection() {
        selectedContacts.removeAll()
        selectedGroups.removeAll()
        updateStateFromSelection()
        // REMOVED: saveImmediately() - selection changes should not trigger saves
    }
    
    func toggleContactSelection(_ contactId: UUID) {
        if selectedContacts.contains(contactId) {
            selectedContacts.remove(contactId)
        } else {
            selectedContacts.insert(contactId)
        }
        updateStateFromSelection()
        // REMOVED: saveImmediately() - selection changes should not trigger saves
    }
    
    func toggleGroupSelection(_ groupId: UUID) {
        if selectedGroups.contains(groupId) {
            selectedGroups.remove(groupId)
        } else {
            selectedGroups.insert(groupId)
        }
        updateStateFromSelection()
        // REMOVED: saveImmediately() - selection changes should not trigger saves
    }
    
    // MARK: - Zoom Management
    func setZoom(_ zoom: CGFloat, viewSize: CGSize? = nil, anchorInView anchor: CGPoint? = nil) {
        // Set zoom limits: minimum 2% (0.02), maximum 3.0x
        // Additional safety check for NaN or infinite values
        let safeZoom = zoom.isFinite ? zoom : 1.0
        let clampedZoom = max(0.02, min(3.0, safeZoom))
        
        // Only update if the value actually changed to prevent infinite loops
        guard abs(canvasState.zoom - clampedZoom) > 0.001 else { return }
        guard !isUpdatingZoom else { return }
        isUpdatingZoom = true
        
        var updatedPan = canvasState.pan
        
        if let viewSize {
            // Determine the anchor point we should preserve in view coordinates.
            let anchorPoint = anchor ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
            
            // Convert the anchor to canvas coordinates using the current transform
            let currentCanvasAnchor = viewToCanvas(anchorPoint, viewSize: viewSize)
            
            // Convert values to the top-left coordinate system used by CanvasTransform
            let anchorCanvasTopLeft = CGPoint(x: currentCanvasAnchor.x, y: -currentCanvasAnchor.y)
            let anchorViewTopLeft = CGPoint(x: anchorPoint.x, y: viewSize.height - anchorPoint.y)
            
            // Compute the pan needed to keep the anchor fixed after zooming
            let scaledAnchor = CGPoint(
                x: anchorCanvasTopLeft.x * clampedZoom,
                y: anchorCanvasTopLeft.y * clampedZoom
            )
            
            let desiredPan = CGPoint(
                x: anchorViewTopLeft.x - scaledAnchor.x,
                y: anchorViewTopLeft.y - scaledAnchor.y
            )
            
            updatedPan = applyBoundsToPan(desiredPan, viewSize: viewSize)
        }
        
        canvasState.zoom = clampedZoom
        canvasState.pan = updatedPan
        print("🔧 Zoom updated to: \(clampedZoom) with pan: \(updatedPan)")
        
        // Save canvas state when zoom changes (essential save)
        saveImmediately()
        
        // Reset flag after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isUpdatingZoom = false
        }
    }
    
    func getCanvasBounds() -> CGRect {
        // Define the total canvas bounds as specified by user
        // Canvas with corner coordinates: {(-300, -300), (400, -300), (400, 400), (-300, 400)}
        return CGRect(x: -300, y: -300, width: 700, height: 700)
    }
    
    func zoomIn(viewSize: CGSize? = nil) {
        let effectiveViewSize = viewSize ?? CGSize(width: 800, height: 600)
        setZoom(canvasState.zoom * 1.2, viewSize: effectiveViewSize)
    }
    
    func zoomOut(viewSize: CGSize? = nil) {
        let effectiveViewSize = viewSize ?? CGSize(width: 800, height: 600)
        setZoom(canvasState.zoom * 0.8, viewSize: effectiveViewSize)
    }
    
    func resetZoom(viewSize: CGSize? = nil) {
        let effectiveViewSize = viewSize ?? CGSize(width: 800, height: 600)
        setZoom(1.0, viewSize: effectiveViewSize)
    }
    
    // MARK: - Center-based Zoom Methods
    
    func zoomInFromCenter(viewSize: CGSize) {
        let newZoom = canvasState.zoom * 1.2
        zoomFromCenter(to: newZoom, viewSize: viewSize)
    }
    
    func zoomOutFromCenter(viewSize: CGSize) {
        let newZoom = canvasState.zoom * 0.8
        zoomFromCenter(to: newZoom, viewSize: viewSize)
    }
    
    func resetZoomFromCenter(viewSize: CGSize) {
        zoomFromCenter(to: 1.0, viewSize: viewSize)
    }
    
    private func zoomFromCenter(to newZoom: CGFloat, viewSize: CGSize) {
        setZoom(newZoom, viewSize: viewSize)
    }
    
    private func viewToCanvasWithState(_ point: CGPoint, viewSize: CGSize, canvasState: CanvasState) -> CGPoint {
        let transform = CanvasTransform(zoom: canvasState.zoom, pan: canvasState.pan)
        // Convert bottom-left view coordinates to top-left for the transform
        let topLeftViewPoint = CGPoint(
            x: point.x,
            y: viewSize.height - point.y
        )
        let topLeftCanvasPoint = transform.viewToCanvas(topLeftViewPoint)
        // Convert to bottom-left canvas coordinates
        return CGPoint(
            x: topLeftCanvasPoint.x,
            y: -topLeftCanvasPoint.y
        )
    }
    
    // MARK: - Pan Management
    func setPan(_ pan: CGPoint) {
        canvasState.pan = pan
        // Re-enabled: Save canvas state when pan changes (essential save)
        saveImmediately()
    }
    
    func panBy(_ delta: CGPoint, viewSize: CGSize? = nil) {
        // Pan delta represents how much the user drags the canvas
        // When user drags right, X should increase; when user drags down, Y should decrease
        let newPan = CGPoint(
            x: canvasState.pan.x + delta.x, // User drags right = X increases
            y: canvasState.pan.y - delta.y  // User drags down = Y decreases
        )
        
        // Apply bounds checking with dynamic bounds
        let boundedPan = applyBoundsToPan(newPan, viewSize: viewSize)
        canvasState.pan = boundedPan
        // Re-enabled: Save canvas state when pan changes (essential save)
        saveImmediately()
    }
    
    private func applyBoundsToPan(_ pan: CGPoint, viewSize: CGSize? = nil) -> CGPoint {
        // Remove all pan limits - allow free movement
        return pan
    }
    
    // MARK: - Grid Management
    func toggleGrid() {
        canvasState.gridEnabled.toggle()
        // DISABLED: saveImmediately() was causing infinite loops
        // saveImmediately()
    }
    
    func toggleSnapToGrid() {
        canvasState.snapToGrid.toggle()
        // DISABLED: saveImmediately() was causing infinite loops
        // saveImmediately()
    }
    
    func setGridSize(_ size: CGFloat) {
        canvasState.gridSize = max(4.0, min(32.0, size))
        // DISABLED: saveImmediately() was causing infinite loops
        // saveImmediately()
    }
    
    // MARK: - Contact Management
    func addContact(_ contact: ContactNode) {
        contacts.append(contact)
        
        // NEW TRIGGER: New contact node created - recalculate group memberships
        recalculateGroupMemberships(for: contact)
        
        saveImmediately()
    }
    
    func updateContact(_ contact: ContactNode) {
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "UPDATE_CONTACT_CALLED",
            details: "Updating contact: \(contact.id) at position \(contact.position)",
            success: true
        )
        
        print("🔧 GroupsMapViewModel.updateContact() called")
        print("🔧 Contact ID: \(contact.id)")
        print("🔧 Contact position: \(contact.position)")
        
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[index] = contact
            print("🔧 Updated contact at index \(index)")
            
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "UPDATE_CONTACT_SUCCESS",
                details: "Successfully updated contact: \(contact.id) at index \(index)",
                success: true
            )
            
            saveImmediately()
        } else {
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "UPDATE_CONTACT_NOT_FOUND",
                details: "Contact not found for update: \(contact.id)",
                success: false
            )
            
            print("❌ Contact not found for update: \(contact.id)")
        }
    }
    
    func removeContact(_ contactId: UUID) {
        guard let contact = contacts.first(where: { $0.id == contactId }) else { return }
        
        // Register undo action
        undoManager?.registerUndo(withTarget: self) { viewModel in
            Task { @MainActor in
                viewModel.addContact(contact)
            }
        }
        
        // Remove contact from all groups before deleting
        removeContactFromAllGroups(contactId)
        
        // Remove contact from canvas database
        removeContactFromCanvas(contactId: contact.phone, canvasId: currentMapId.uuidString)
        
        contacts.removeAll { $0.id == contactId }
        selectedContacts.remove(contactId)
        updateStateFromSelection()
        // REMOVED: saveImmediately() - element removal should not trigger saves (database already updated)
    }
    
    // Removed conflicting moveContact(to:) method - use moveContact(by:) with unified movement system instead
    
    // Old moveContact method removed - will implement new drag system
    
    // MARK: - Performance Optimization Properties (Old drag system removed)
    
    // MARK: - Element Movement (New Simple System)
    
    /// Update contact position directly
    func updateContactPosition(_ contactId: UUID, to newPosition: CGPoint) {
        if let index = contacts.firstIndex(where: { $0.id == contactId }) {
            contacts[index].position = newPosition
            print("🎯 Updated contact \(contactId) position to \(newPosition)")
        }
    }
    
    /// Update group position directly
    func updateGroupPosition(_ groupId: UUID, to newPosition: CGPoint) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            groups[index].center = newPosition
            print("🎯 Updated group \(groupId) position to \(newPosition)")
        }
    }
    
    /// Update multiple element positions
    func updateElementPositions(_ positions: [UUID: CGPoint]) {
        for (elementId, position) in positions {
            // Try to update as contact first
            if let index = contacts.firstIndex(where: { $0.id == elementId }) {
                contacts[index].position = position
            }
            // If not found as contact, try as group
            else if let index = groups.firstIndex(where: { $0.id == elementId }) {
                groups[index].center = position
            }
        }
    }
    
    /// Save all current positions to database
    func saveElementPositions() {
        print("🎯 Saving all element positions to database")
        
        // Save contact positions
        for contact in contacts {
            updateContact(contact)
        }
        
        // Save group positions  
        for group in groups {
            updateGroup(group)
        }
        
        // Save canvas state
        saveImmediately()
    }
    
    // MARK: - Canvas Element Position Updates
    
    /// Update canvas element positions for given UUIDs (sync only, no delta applied)
    func updateCanvasElementPositionsOnly(elementUUIDs: [UUID]) {
        // Convert UUIDs to strings for lookup
        let uuidStrings = elementUUIDs.map { $0.uuidString }
        
        // Update canvas elements in GlobalCanvasService to match current positions
        for uuidString in uuidStrings {
            if let canvas = GlobalCanvasService.shared.currentCanvas,
               let elementIndex = canvas.elements.firstIndex(where: { element in
                   // Check both contact_uuid and group_uuid
                   element.contactUUID == uuidString || element.groupUUID == uuidString
               }) {
                
                var updatedElement = canvas.elements[elementIndex]
                
                // Find the current position from our in-memory arrays
                if let contact = contacts.first(where: { $0.id.uuidString == uuidString }) {
                    updatedElement.location = contact.position
                } else if let group = groups.first(where: { $0.id.uuidString == uuidString }) {
                    updatedElement.location = group.center
                }
                
                print("🔧 updateCanvasElementPositionsOnly: Synced element \(updatedElement.id) location to \(updatedElement.location)")
                
                // Update in GlobalCanvasService
                GlobalCanvasService.shared.updateElementPosition(
                    elementId: updatedElement.id, 
                    to: updatedElement.location
                )
            } else {
                print("⚠️ updateCanvasElementPositionsOnly: Element with UUID \(uuidString) not found in canvas elements")
            }
        }
    }
    
    /// Update canvas element positions for given UUIDs (with delta applied)
    func updateCanvasElementPositions(elementUUIDs: [UUID], delta: CGPoint) {
        // Convert UUIDs to strings for lookup
        let uuidStrings = elementUUIDs.map { $0.uuidString }
        
        // Update canvas elements in GlobalCanvasService
        for uuidString in uuidStrings {
            if let canvas = GlobalCanvasService.shared.currentCanvas,
               let elementIndex = canvas.elements.firstIndex(where: { element in
                   // Check both contact_uuid and group_uuid
                   element.contactUUID == uuidString || element.groupUUID == uuidString
               }) {
                
                var updatedElement = canvas.elements[elementIndex]
                updatedElement.location.x += delta.x
                updatedElement.location.y += delta.y
                
                print("🔧 updateCanvasElementPositions: Updated element \(updatedElement.id) location to \(updatedElement.location)")
                
                // Update in GlobalCanvasService
                GlobalCanvasService.shared.updateElementPosition(
                    elementId: updatedElement.id, 
                    to: updatedElement.location
                )
            } else {
                print("⚠️ updateCanvasElementPositions: Element with UUID \(uuidString) not found in canvas elements")
            }
        }
    }
    
    /// Unified method to update positions of specific elements by UUID
    func updateElementPositions(elementUUIDs: [UUID], delta: CGPoint) {
        print("🔧 updateElementPositions: Updating \(elementUUIDs.count) elements with delta \(delta)")
        
        // Update in-memory arrays
        for uuid in elementUUIDs {
            // Update contacts
            if let contactIndex = contacts.firstIndex(where: { $0.id == uuid }) {
                contacts[contactIndex].position.x += delta.x
                contacts[contactIndex].position.y += delta.y
                print("🔧 updateElementPositions: Updated contact \(uuid) position to \(contacts[contactIndex].position)")
            }
            
            // Update groups
            if let groupIndex = groups.firstIndex(where: { $0.id == uuid }) {
                groups[groupIndex].center.x += delta.x
                groups[groupIndex].center.y += delta.y
                print("🔧 updateElementPositions: Updated group \(uuid) center to \(groups[groupIndex].center)")
            }
        }
        
        // Update canvas elements
        updateCanvasElementPositions(elementUUIDs: elementUUIDs, delta: delta)
        
        // Recalculate group memberships for all affected elements
        recalculateGroupMemberships()
        
        // Save changes
        if !isDragging {
            saveImmediately()
        }
    }
    
    // MARK: - Legacy Movement Methods (for backward compatibility)
    
    // Old movement methods removed - use new drag system
    
    // MARK: - Drag State Management
    
    func startDragging() {
        isDragging = true
        wasDragging = true
        print("🔧 Started dragging - saves will be deferred")
        
        // Start monitoring drag state every 1/30 seconds
        startDragMonitor()
    }
    
    func endDragging() {
        isDragging = false
        wasDragging = true
        print("🔧 Ended dragging - saves will be re-enabled")
        
        // Stop monitoring drag state
        stopDragMonitor()
    }
    
    // MARK: - Drag State Monitoring
    
    private func startDragMonitor() {
        // DISABLED: Drag monitor timer was causing infinite loops
        // Stop any existing monitor
        stopDragMonitor()
        
        // Start monitoring every 1/30 seconds (33.33ms)
        // DISABLED: This timer was causing continuous CPU usage
        // dragMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
        //     DispatchQueue.main.async {
        //         print("🔍 DEBUG: Drag monitor timer triggered")
        //         self?.checkDragState()
        //     }
        // }
        print("🔧 Drag monitor timer DISABLED to prevent infinite loops")
    }
    
    private func stopDragMonitor() {
        dragMonitorTimer?.invalidate()
        dragMonitorTimer = nil
        print("🔧 Stopped drag monitor timer")
    }
    
    private func checkDragState() {
        // Check if dragging state changed from true to false
        if wasDragging && !isDragging {
            print("🔧 Drag state changed from true to false - final state saved by individual element updates")
            print("🔍 DEBUG: checkDragState() - no save needed, individual element updates already saved")
            wasDragging = false
            // REMOVED: saveImmediately() - individual element position changes already save
            stopDragMonitor()
        }
    }
    
    // MARK: - Drag and Drop Support
    
    /// Adjusts drop position by accounting for UI element widths and heights
    /// - Warning: DEPRECATED - This method is legacy code and should not be used.
    ///   All drop coordinates are now properly converted by viewToCanvas() or localToCanvas()
    ///   before reaching addContactFromDrop/addGroupFromDrop.
    @available(*, deprecated, message: "Use viewToCanvas or localToCanvas for coordinate conversion instead")
    private func adjustDropPosition(_ originalPosition: CGPoint) -> CGPoint {
        // Get current UI state dynamically from the main window
        var totalXOffset: CGFloat = 0
        var totalYOffset: CGFloat = 0
        
        // Find the main window and calculate UI element dimensions
        if let mainWindow = NSApp.windows.first(where: { $0.isKeyWindow }) {
            let windowFrame = mainWindow.frame
            let windowSize = windowFrame.size
            
            // Calculate UI element dimensions dynamically
            // We'll use the window's content view to determine actual UI layout
            if let contentView = mainWindow.contentView {
                let contentFrame = contentView.frame
                
                // Calculate X offset based on actual UI layout
                // The difference between window width and content width gives us the sidebar widths
                let sidebarWidth = windowSize.width - contentFrame.width
                totalXOffset = sidebarWidth
                
                // Calculate Y offset based on actual UI layout
                // The difference between window height and content height gives us the toolbar height
                let toolbarHeight = windowSize.height - contentFrame.height
                totalYOffset = toolbarHeight
                
                print("🔧 Dynamic UI calculation:")
                print("  - Window size: \(windowSize)")
                print("  - Content frame: \(contentFrame)")
                print("  - Calculated sidebar width: \(sidebarWidth)")
                print("  - Calculated toolbar height: \(toolbarHeight)")
            } else {
                // Fallback to static values if content view is not available
                totalXOffset = 600 // Default sidebar width
                totalYOffset = 80  // Default toolbar height
                print("🔧 Using fallback UI dimensions: X=\(totalXOffset), Y=\(totalYOffset)")
            }
        } else {
            // Fallback if no window is found
            totalXOffset = 600
            totalYOffset = 80
            print("🔧 No main window found, using fallback dimensions: X=\(totalXOffset), Y=\(totalYOffset)")
        }
        
        // Adjust position: subtract X offsets (move left), add Y offset (move down)
        let adjustedPosition = CGPoint(
            x: originalPosition.x - totalXOffset,
            y: originalPosition.y + totalYOffset
        )
        
        print("🔧 Drop position adjustment: original=\(originalPosition), adjusted=\(adjustedPosition)")
        print("🔧 Dynamic UI offsets: X=\(totalXOffset), Y=\(totalYOffset)")
        
        return adjustedPosition
    }
    
    func addContactFromDrop(_ contact: Contact, at position: CGPoint) {
        // Position is already in canvas coordinates (converted by viewToCanvas or localToCanvas)
        // No adjustment needed - the coordinate transformation is already done by the caller
        let adjustedPosition = position
        
        DragDropLogger.shared.log("addContactFromDrop called for \(contact.name) with phone: \(contact.phone) at \(position) (already in canvas coordinates)", operation: "CONTACT_ADD")
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "ADD_CONTACT_FROM_DROP_CALLED",
            details: "Adding contact from drop: \(contact.name) with phone: \(contact.phone) at position \(position) (adjusted to \(adjustedPosition))",
            success: true
        )
        
        // CRITICAL FIX: Check for duplicate contact on canvas before creating
        if let existingContact = contacts.first(where: { $0.phone == contact.phone }) {
            print("⚠️ Contact \(contact.name) (\(contact.phone)) already exists on canvas with ID: \(existingContact.id)")
            print("💡 Skipping duplicate creation - moving existing contact to drop position instead")
            LogManager.shared.warning("⚠️ Contact \(contact.name) (\(contact.phone)) already exists on canvas with ID: \(existingContact.id)")
            LogManager.shared.warning("💡 Skipping duplicate creation - moving existing contact to drop position instead")
            
            // Update position of existing contact instead of creating duplicate
            if let index = contacts.firstIndex(where: { $0.id == existingContact.id }) {
                contacts[index].position = adjustedPosition
                print("✅ Moved existing contact to new position: \(adjustedPosition)")
                LogManager.shared.info("✅ Moved existing contact to new position: \(adjustedPosition)")
                
                // Save the position update
                saveImmediately()
                
                // Recalculate memberships for moved contact
                recalculateGroupMemberships(for: contacts[index])
            }
            return
        }
        
        // Pull the latest contact data from database to ensure we have the most up-to-date information
        let contactToUse: Contact
        let dataProvider = self.dataProvider
        if let latestContact = dataProvider?.getContact(by: contact.phone) {
            // Use the latest data from database
            contactToUse = latestContact
            print("✅ Using latest contact data from database: \(latestContact.displayName) (\(latestContact.phone))")
        } else {
            // Fallback to dropped contact if not found in database
            contactToUse = contact
            print("⚠️ Contact not found in database, using dropped contact data: \(contact.name) (\(contact.phone))")
        }
        
        // Create tags from contact information
        var tags: [String] = []
        if let business = contactToUse.business, !business.isEmpty {
            tags.append(business)
        }
        if let contactGroup = contactToUse.contactGroup, !contactGroup.isEmpty {
            tags.append(contactGroup)
        }
        
        let contactNode = ContactNode(
            id: UUID(), // Generate new UUID for UI purposes
            name: contactToUse.displayName, // Use displayName for consistency
            phone: contactToUse.phone, // Use phone as the primary identifier for database operations
            contactUUID: contactToUse.id, // Store the original contact UUID
            profilePhotoData: contactToUse.profilePhotoData, // Include profile photo data
            position: adjustedPosition, // Use adjusted position
            size: CGSize(width: 60, height: 80),
            isSelected: false,
            tags: tags
        )
        
        contacts.append(contactNode)
        DragDropLogger.shared.log("Added contact node with ID: \(contactNode.id), name: \(contactToUse.displayName), phone: \(contactToUse.phone), total contacts: \(contacts.count)", operation: "CONTACT_ADD")
        
        // Add contact to canvas elements field using UUID, phone number as ID, name, and position
        let canvasElement = contactNode.toCanvasElement()
        DragDropLogger.shared.log("Created canvas element for contact: ID=\(canvasElement.id), Type=\(canvasElement.elementType.rawValue), Location=\(canvasElement.location)", operation: "CONTACT_ADD")
        
        // Add contact to canvas (following same pattern as groups)
        addContactToCanvas(contactId: contactToUse.phone, canvasId: currentMapId.uuidString)
        
        // Save canvas to database (following same pattern as groups)
        saveImmediately()
        
        // Calculate group memberships for the new contact (this checks group boundaries and refreshes UI)
        recalculateGroupMemberships(for: contactNode)
        
        // Update database with group membership changes
        updateGroupMembershipsInDatabase(for: contactNode)
        
        DragDropLogger.shared.log("Contact drop processing completed successfully", operation: "CONTACT_ADD")
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "ADD_CONTACT_FROM_DROP_SUCCESS",
            details: "Successfully added contact: \(contactToUse.name) with phone: \(contactToUse.phone), node ID: \(contactNode.id) and updated group memberships",
            success: true
        )
    }
    
    func addGroupFromDrop(_ group: ContactGroup, at position: CGPoint) {
        // Position is already in canvas coordinates (converted by viewToCanvas or localToCanvas)
        // No adjustment needed - the coordinate transformation is already done by the caller
        let adjustedPosition = position
        
        DragDropLogger.shared.log("addGroupFromDrop called for \(group.name) at \(position) (already in canvas coordinates)", operation: "GROUP_ADD")
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "ADD_GROUP_FROM_DROP_CALLED",
            details: "Adding group from drop: \(group.name) at position \(position) (adjusted to \(adjustedPosition))",
            success: true
        )
        
        // Create a GroupCircle from the ContactGroup
        let groupCircle = GroupCircle(
            id: group.id,
            name: group.name,
            center: adjustedPosition,
            radius: 50.0, // Default radius
            color: group.color,
            members: Set<UUID>(), // Will be populated when contacts are added
            databaseId: nil // Will be set when we look up the group in database
        )
        
        // Add the group to the canvas (this will handle database ID lookup/creation)
        addGroup(groupCircle)
        
        // Add the group to the current canvas in the database
        Task {
            do {
                if let dataProvider = self.dataProvider {
                    try await dataProvider.addCanvasToGroup(groupId: group.id, canvasId: currentMapId)
                    DragDropLogger.shared.log("Successfully added group to canvas in database", operation: "GROUP_ADD")
                } else {
                    DragDropLogger.shared.log("DataProvider not available", operation: "ERROR")
                }
            } catch {
                DragDropLogger.shared.log("Failed to add group to canvas in database: \(error)", operation: "ERROR")
            }
        }
        
        DragDropLogger.shared.log("Group drop processing completed successfully", operation: "GROUP_ADD")
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "ADD_GROUP_FROM_DROP_SUCCESS",
            details: "Successfully added group: \(group.name) with ID: \(group.id)",
            success: true
        )
    }
    
    
    // MARK: - Database Group Membership Updates
    private func updateGroupMembershipsInDatabase(for contact: ContactNode) {
        print("🔧 Updating group memberships in database for contact: \(contact.id)")
        
        // Get the contact's database ID by phone number
        guard let contactId = getContactDatabaseId(phone: contact.name) else {
            print("❌ Could not find contact database ID for: \(contact.name)")
            return
        }
        
        // For each group, check if the contact is a member and update the database
        for group in groups {
            let distance = contact.position.distance(to: group.center)
            let isInGroup = distance <= group.averageRadius
            
            // Get the group's database ID
            guard let groupId = getGroupDatabaseId(name: group.name) else {
                print("❌ Could not find group database ID for: \(group.name)")
                continue
            }
            
            if isInGroup {
                // Contact is in this group - add to database
                updateGroupMembershipInDatabase(contactId: contactId, groupId: groupId, operation: "add")
                print("✅ Added contact \(contact.name) to group \(group.name) in database")
            } else {
                // Contact is not in this group - remove from database
                updateGroupMembershipInDatabase(contactId: contactId, groupId: groupId, operation: "remove")
                print("✅ Removed contact \(contact.name) from group \(group.name) in database")
            }
        }
    }
    
    private func getContactDatabaseId(phone: String) -> Int? {
        // This would need to query the contacts table to get the database ID
        // For now, we'll use a placeholder - this should be implemented based on your contact data structure
        return 1 // Placeholder - should query database for actual contact ID
    }
    
    private func getGroupDatabaseId(name: String) -> Int? {
        print("🔍 Looking up database ID for group: \(name)")
        
        if let groupData = groupManager.getGroupByName(name: name),
           let groupIdString = groupData["id"] as? String,
           let groupId = Int(groupIdString) {
            print("✅ Found group database ID: \(groupId) for group: \(name)")
            return groupId
        }
        
        print("⚠️ Could not find database ID for group: \(name)")
        return nil
    }
    
    private func updateGroupMembershipInDatabase(contactId: Int, groupId: Int, operation: String) {
        guard let process = ScriptPathResolver.createPythonProcess(scriptName: "canvas_manager.py", arguments: [
            "update_group_membership",
            "--contact-id", String(contactId),
            "--group-id", String(groupId),
            "--operation", operation
        ]) else {
            print("❌ Failed to create process for group membership update")
            return
        }
        
        // Set up output pipes
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                print("✅ Successfully updated group membership: contact \(contactId) \(operation)ed to group \(groupId)")
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if let errorString = String(data: errorData, encoding: .utf8) {
                    print("❌ Failed to update group membership: \(errorString)")
                }
            }
        } catch {
            print("Error updating group membership: \(error)")
        }
    }
    
    // MARK: - Group Management
    func addGroup(_ group: GroupCircle) {
        // Ensure the group has a database ID before adding to canvas
        if group.databaseId == nil {
            print("⚠️ Group \(group.name) has no database ID - creating in database first")
            
            // Create ContactGroup for database
            var newContactGroup = ContactGroup(
                name: group.name,
                color: group.color
            )
            newContactGroup.canvases.insert(currentMapId)
            
            // Create the group in the database using SQLiteDataProvider
            Task {
                do {
                    try await dataProvider?.createGroup(newContactGroup)
                    print("✅ Group created in database via SQLiteDataProvider")
                    
                    // Extract database ID from the created group
                    if let createdGroup = dataProvider?.groups.first(where: { $0.name == group.name }) {
                        let dbId = extractDatabaseId(from: createdGroup.id)
                        
                        // Update the group with the database ID and add to canvas
                        await MainActor.run {
                            var updatedGroup = group
                            updatedGroup.databaseId = dbId
                            groups.append(updatedGroup)
                            print("✅ Group \(group.name) now has database ID: \(dbId)")
                            
                            // Calculate initial membership for the new group
                            calculateInitialGroupMembership(for: updatedGroup)
                            
                            // Save the canvas
                            saveImmediately()
                        }
                    }
                } catch {
                    print("❌ Failed to create group in database: \(error)")
                }
            }
        } else {
            // Group already has a databaseId, add to canvas and save immediately
            groups.append(group)
            calculateInitialGroupMembership(for: group)
            saveImmediately()
        }
    }
    
    func updateGroup(_ group: GroupCircle) {
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "UPDATE_GROUP_CALLED",
            details: "Updating group: \(group.id) at center \(group.center)",
            success: true
        )
        
        print("🔧 GroupsMapViewModel.updateGroup() called")
        print("🔧 Group ID: \(group.id)")
        print("🔧 Group center: \(group.center)")
        
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
            print("🔧 Updated group at index \(index)")
            
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "UPDATE_GROUP_SUCCESS",
                details: "Successfully updated group: \(group.id) at index \(index)",
                success: true
            )
            
            saveImmediately()
        } else {
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "UPDATE_GROUP_NOT_FOUND",
                details: "Group not found for update: \(group.id)",
                success: false
            )
            
            print("❌ Group not found for update: \(group.id)")
        }
    }
    
    func removeGroup(_ groupId: UUID) {
        guard let group = groups.first(where: { $0.id == groupId }) else { return }
        
        // Register undo action
        undoManager?.registerUndo(withTarget: self) { viewModel in
            Task { @MainActor in
                viewModel.addGroup(group)
            }
        }
        
        groups.removeAll { $0.id == groupId }
        selectedGroups.remove(groupId)
        updateStateFromSelection()
        // REMOVED: saveImmediately() - element removal should not trigger saves (database already updated)
    }
    
    // Removed conflicting moveGroup(to:) method - use moveGroup(by:) with unified movement system instead
    
    // Old moveGroup method removed - use new drag system
    
    func resizeGroup(_ groupId: UUID, width: CGFloat, height: CGFloat) {
        print("🔧 GroupsMapViewModel: resizeGroup called for group \(groupId) with width: \(width), height: \(height)")
        
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            var group = groups[index]
            print("🔧 GroupsMapViewModel: Found group at index \(index), current size: \(group.width) x \(group.height)")
            
            group.width = width
            group.height = height
            group.updateRadius() // Update radius for backward compatibility
            
            print("🔧 GroupsMapViewModel: Updated group size to: \(group.width) x \(group.height), radius: \(group.radius)")
            
            groups[index] = group
            recalculateGroupMemberships()
            saveImmediately()
            
            print("🔧 GroupsMapViewModel: Group resize completed successfully")
        } else {
            print("❌ GroupsMapViewModel: Group not found for resize: \(groupId)")
        }
    }
    
    // Backward compatibility method
    func resizeGroup(_ groupId: UUID, to radius: CGFloat) {
        resizeGroup(groupId, width: radius * 2, height: radius * 2)
    }
    
    /// Resize and reposition a group (used for anchor-point-based scaling)
    /// Lightweight version - only updates in-memory state for smooth real-time dragging
    func resizeAndRepositionGroup(_ groupId: UUID, width: CGFloat, height: CGFloat, center: CGPoint) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            var group = groups[index]
            group.width = width
            group.height = height
            group.center = center
            group.updateRadius() // Update radius for backward compatibility
            
            groups[index] = group
            // Note: We do NOT recalculate memberships or save during drag
            // This happens in commitGroupTransform() on drag end
        }
    }
    
    /// Commit group transform changes (called on drag end)
    func commitGroupTransform(_ groupId: UUID) {
        print("🔧 GroupsMapViewModel: Committing transform for group \(groupId)")
        recalculateGroupMemberships()
        saveImmediately()
        print("🔧 GroupsMapViewModel: Transform committed successfully")
    }
    
    func rotateGroup(_ groupId: UUID, by angle: CGFloat) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            var group = groups[index]
            group.rotation = angle
            groups[index] = group
            saveImmediately()
        }
    }
    
    func updateGroupColor(_ groupId: UUID, to color: Color) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            var group = groups[index]
            group.color = color
            groups[index] = group
            
            // Save the group color change to the database
            Task {
                do {
                    if let dataProvider = self.dataProvider {
                        // Find the corresponding ContactGroup in the database by UUID first, then by name as fallback
                        let allGroups = try await dataProvider.fetchGroups()
                        
                        // First try to find by UUID (most reliable)
                        var databaseGroup = allGroups.first(where: { $0.id == groupId })
                        
                        // If not found by UUID, try by name as fallback
                        if databaseGroup == nil {
                            databaseGroup = allGroups.first(where: { $0.name == group.name })
                        }
                        
                        guard let foundGroup = databaseGroup else {
                            print("❌ Could not find database group for color update: \(group.name) (ID: \(groupId))")
                            return
                        }
                        
                        // Update the group color in the database
                        var updatedGroup = foundGroup
                        updatedGroup.color = color
                        try await dataProvider.updateGroup(updatedGroup)
                        
                        print("✅ Successfully updated group color in database: \(group.name) to \(color)")
                        LogManager.shared.info("✅ Successfully updated group color in database: \(group.name) to \(color)")
                    } else {
                        print("❌ DataProvider not available for group color update")
                        LogManager.shared.error("❌ DataProvider not available for group color update")
                    }
                } catch {
                    print("❌ Failed to update group color in database: \(error)")
                    LogManager.shared.error("❌ Failed to update group color in database: \(error)")
                }
            }
            
            // Don't call saveImmediately() here as it would overwrite the database changes
            // The database has already been updated through the proper channel above
        }
    }
    
    func updateGroupName(_ groupId: UUID, to name: String) {
        if let index = groups.firstIndex(where: { $0.id == groupId }) {
            var group = groups[index]
            group.name = name
            groups[index] = group
            
            // Save the group name change to the database
            Task {
                do {
                    if let dataProvider = self.dataProvider {
                        // Find the corresponding ContactGroup in the database by UUID first, then by name as fallback
                        let allGroups = try await dataProvider.fetchGroups()
                        
                        // First try to find by UUID (most reliable)
                        var databaseGroup = allGroups.first(where: { $0.id == groupId })
                        
                        // If not found by UUID, try by the old name as fallback
                        if databaseGroup == nil {
                            databaseGroup = allGroups.first(where: { $0.name == group.name })
                        }
                        
                        guard let foundGroup = databaseGroup else {
                            print("❌ Could not find database group for name update: \(group.name) (ID: \(groupId))")
                            return
                        }
                        
                        // Update the group name in the database
                        var updatedGroup = foundGroup
                        updatedGroup.name = name
                        try await dataProvider.updateGroup(updatedGroup)
                        
                        print("✅ Successfully updated group name in database: \(group.name) to \(name)")
                        LogManager.shared.info("✅ Successfully updated group name in database: \(group.name) to \(name)")
                    } else {
                        print("❌ DataProvider not available for group name update")
                        LogManager.shared.error("❌ DataProvider not available for group name update")
                    }
                } catch {
                    print("❌ Failed to update group name in database: \(error)")
                    LogManager.shared.error("❌ Failed to update group name in database: \(error)")
                }
            }
            
            // Don't call saveImmediately() here as it would overwrite the database changes
            // The database has already been updated through the proper channel above
        }
    }
    
    // MARK: - Group Data Synchronization
    
    /// Refresh group data from the database after changes made through GroupEditingService
    func refreshGroupDataFromDatabase(groupId: UUID) {
        print("🔄 GroupsMapViewModel: Refreshing group data from database for group ID: \(groupId)")
        LogManager.shared.info("🔄 GroupsMapViewModel: Refreshing group data from database for group ID: \(groupId)")
        
        Task {
            do {
                guard let dataProvider = self.dataProvider else {
                    print("❌ DataProvider not available for group data refresh")
                    return
                }
                
                // Refresh groups from database to get latest data
                try await dataProvider.refreshGroupsFromDatabase()
                let allGroups = try await dataProvider.fetchGroups()
                
                // Find the updated group in the database
                guard let databaseGroup = allGroups.first(where: { $0.id == groupId }) else {
                    print("❌ Could not find group in database for refresh: \(groupId)")
                    return
                }
                
                // Find the corresponding GroupCircle in the canvas
                guard let canvasGroupIndex = groups.firstIndex(where: { $0.id == groupId }) else {
                    print("❌ Could not find group in canvas for refresh: \(groupId)")
                    return
                }
                
                // Update the canvas group with the latest data from database
                var updatedCanvasGroup = groups[canvasGroupIndex]
                updatedCanvasGroup.name = databaseGroup.name
                updatedCanvasGroup.color = databaseGroup.color
                
                await MainActor.run {
                    groups[canvasGroupIndex] = updatedCanvasGroup
                    print("✅ Successfully refreshed group data in canvas: \(databaseGroup.name)")
                    LogManager.shared.info("✅ Successfully refreshed group data in canvas: \(databaseGroup.name)")
                    
                    // Save the updated canvas to the database to persist the group metadata changes
                    saveImmediately()
                    print("✅ Canvas saved to database with updated group metadata")
                    LogManager.shared.info("✅ Canvas saved to database with updated group metadata")
                    
                    // Trigger UI update by notifying observers
                    objectWillChange.send()
                }
                
            } catch {
                print("❌ Failed to refresh group data from database: \(error)")
                LogManager.shared.error("❌ Failed to refresh group data from database: \(error)")
            }
        }
    }
    

    

    
    func loadCanvasFromDatabase(_ canvas: Canvas, dataProvider: SQLiteDataProvider? = nil) {
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "LOAD_CANVAS_INTO_VIEWMODEL",
            details: "Loading canvas into ViewModel: \(canvas.name) (ID: \(canvas.id)) with \(canvas.elements.count) elements",
            success: true
        )
        
        print("🔧 GroupsMapViewModel.loadCanvasFromDatabase() called")
        print("🔧 Loading canvas from database: \(canvas.name)")
        print("🔧 Canvas ID: \(canvas.id)")
        print("🔧 Canvas has \(canvas.elements.count) elements")
        
        // Set loading flag to prevent saves during loading
        isLoading = true
        print("🔧 Set isLoading = true to prevent saves during loading")
        
        // Debug: Print all element details
        for (index, element) in canvas.elements.enumerated() {
            print("🔧 Element \(index): ID=\(element.id), Type=\(element.elementType), Location=\(element.location)")
        }
        
        // Clean up canvas elements - remove references to deleted groups
        // DISABLED: Cleanup is too aggressive and removes valid groups during race conditions
        // TODO: Re-enable cleanup only when explicitly needed (e.g., after group deletion)
        print("🔧 ========== CANVAS CLEANUP DISABLED ==========")
        print("🔧 Skipping cleanupCanvasElements to prevent race condition group removal")
        let cleanedCanvas = canvas // Use original canvas without cleanup
        print("🔧 ========== CANVAS CLEANUP SKIPPED ==========")
        
        // Convert cleaned canvas elements back to contacts and groups
        let canvasContacts = cleanedCanvas.elements.filter { $0.elementType == .contact }
        let canvasGroups = cleanedCanvas.elements.filter { $0.elementType == .group }
        
        print("🔧 Found \(canvasContacts.count) contact elements and \(canvasGroups.count) group elements after cleanup")
        
        // Log the difference between original and cleaned canvas
        if canvas.elements.count != cleanedCanvas.elements.count {
            print("⚠️ WARNING: Canvas cleanup removed elements!")
            print("⚠️   Original elements: \(canvas.elements.count)")
            print("⚠️   Cleaned elements: \(cleanedCanvas.elements.count)")
            print("⚠️   Elements removed: \(canvas.elements.count - cleanedCanvas.elements.count)")
        } else {
            print("✅ Canvas cleanup: No elements were removed")
        }
        
        // Load contact data from database to get proper names and photos
        let convertedContacts = loadContactsFromDatabase(canvasContacts: canvasContacts, dataProvider: dataProvider)
        
        // Load group data from database to get proper names and colors
        let convertedGroups = loadGroupsFromDatabase(canvasGroups: canvasGroups)
        
        print("🔧 Successfully converted \(convertedContacts.count) contacts and \(convertedGroups.count) groups")
        
        // Update the current map ID
        if let canvasId = UUID(uuidString: canvas.id) {
            currentMapId = canvasId
            print("🔧 Updated currentMapId to: \(canvasId)")
        }
        
        // Update the canvas state
        canvasState = cleanedCanvas.canvasState
        print("🔧 Updated canvas state: zoom=\(canvasState.zoom), pan=\(canvasState.pan), mode=\(canvasState.mode)")
        
        // Update the contacts and groups arrays
        contacts = convertedContacts
        groups = convertedGroups
        
        print("🔧 Updated contacts array with \(contacts.count) contacts")
        print("🔧 Updated groups array with \(groups.count) groups")
        
        // Update selection state
        updateSelectionFromState()
        print("🔧 Updated selection state")
        
        // Clear loading flag after a short delay to ensure UI updates are complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isLoading = false
            print("🔧 Set isLoading = false after loading delay")
            
            // Note: Removed circular call to GlobalCanvasService.updateCurrentCanvasState() 
            // to prevent infinite loops during initialization. The canvas state is already
            // managed by the GlobalCanvasService.setCurrentCanvas() call chain.
            
            // If the canvas was cleaned (elements removed), save the cleaned version to database
            // This ensures deleted group references are permanently removed
            if cleanedCanvas.elements.count != canvas.elements.count {
                print("🔧 Canvas was cleaned during loading - saving cleaned version to database")
                let dbRepository = DatabaseCanvasRepository()
                let success = dbRepository.updateCanvas(cleanedCanvas)
                if success {
                    print("✅ Successfully saved cleaned canvas to database")
                } else {
                    print("❌ Failed to save cleaned canvas to database")
                }
            }
            
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "LOAD_CANVAS_INTO_VIEWMODEL_COMPLETED",
                details: "Canvas loading into ViewModel completed: \(canvas.name) (ID: \(canvas.id)) with \(self.contacts.count) contacts and \(self.groups.count) groups",
                success: true
            )
            
            // Recalculate group memberships after canvas load completes
            // This runs AFTER isLoading is false to prevent infinite loops
            print("🔄 Running group membership recalculation after canvas load")
            self.recalculateGroupMemberships()
            print("✅ Group membership recalculation completed after canvas load")
        }
    }
    

    
    // MARK: - Group Membership Logic
    func recalculateGroupMemberships(for contact: ContactNode? = nil) {
        // Guard: Don't recalculate during canvas loading to prevent infinite loops
        guard !isLoading else {
            print("⚠️ Skipping group membership recalculation - canvas is still loading")
            return
        }
        
        let logger = GroupBehaviorLogger.shared
        
        if let contact = contact {
            // Recalculate for specific contact
            recalculateSingleContactMembership(contact: contact, logger: logger)
        } else {
            // Recalculate for all contacts
            logger.logRecalculationStart(contactCount: contacts.count, groupCount: groups.count)
            
            logger.log("🔄 Recalculating group memberships for all \(contacts.count) contacts", level: "MEMBERSHIP_RECALC", operation: "START_ALL")
            
            for contact in contacts {
                recalculateSingleContactMembership(contact: contact, logger: logger)
            }
            
            // Update all groups' participants in database
            for group in groups {
                updateGroupParticipantsInDatabase(group: group)
            }
            
            logger.log("✅ Completed group membership recalculation for all contacts", level: "MEMBERSHIP_RECALC", operation: "COMPLETE_ALL")
            logger.logRecalculationComplete(contactCount: contacts.count, groupCount: groups.count)
        }
    }
    
    private func recalculateSingleContactMembership(contact: ContactNode, logger: GroupBehaviorLogger) {
        logger.logRecalculationStart(contactCount: 1, groupCount: groups.count, specificContact: contact)
        
        logger.log("🔄 Recalculating group memberships for contact: \(contact.name) (ID: \(contact.id), Phone: \(contact.phone))", level: "MEMBERSHIP_RECALC", contact: contact, operation: "START")
        
        for groupIndex in groups.indices {
            let group = groups[groupIndex]
            // Use alternative ellipse overlap detection if group has valid ellipse parameters
            let isInside = detectOverlapWithEllipse(contact: contact, group: group)
            let wasMember = group.members.contains(contact.id)
            
            // Calculate distance for logging purposes
            let distance = contact.position.distance(to: group.center)
            logger.logOverlapDetection(contact: contact, group: group, distance: distance, isInside: isInside)
            
            logger.log("📍 Contact position: \(contact.position), Group center: \(group.center), Distance: \(distance), Average Radius: \(group.averageRadius)", level: "MEMBERSHIP_RECALC", contact: contact, group: group, operation: "POSITION_CHECK")
            
            if isInside {
                // Contact is inside group
                if !wasMember {
                    logger.log("🎯 CONTACT ENTERED GROUP: \(contact.name) entered \(group.name)", level: "MEMBERSHIP_CHANGE", contact: contact, group: group, operation: "ENTERED_GROUP")
                    
                    var updatedGroup = group
                    updatedGroup.members.insert(contact.id)
                    groups[groupIndex] = updatedGroup
                    
                    logger.logMembershipChange(contact: contact, group: group, action: "ADD", wasMember: wasMember, isMember: true)
                    
                    // Update group participants in database using source-based approach
                    logger.log("💾 Triggering database update for group: \(group.name) after contact entered", level: "DATABASE_TRIGGER", contact: contact, group: group, operation: "CONTACT_ENTERED")
                    
                    // Get database ID for the group
                    var databaseId = group.databaseId
                    if databaseId == nil {
                        databaseId = getGroupDatabaseId(name: group.name)
                    }
                    
                    if let dbId = databaseId {
                        addParticipantToGroup(
                            contact: contact,
                            groupDatabaseId: dbId,
                            sourceType: "Canvas Group Circle",
                            sourceUUID: group.id.uuidString, // This is the Group Circle UUID (UI element ID)
                            logger: logger
                        )
                    }
                } else {
                    logger.log("✅ Contact already a member - no change needed", level: "MEMBERSHIP", contact: contact, group: group, operation: "NO_CHANGE")
                }
            } else {
                // Contact is outside group
                if wasMember {
                    logger.log("🚪 CONTACT LEFT GROUP: \(contact.name) left \(group.name)", level: "MEMBERSHIP_CHANGE", contact: contact, group: group, operation: "LEFT_GROUP")
                    
                    var updatedGroup = group
                    updatedGroup.members.remove(contact.id)
                    groups[groupIndex] = updatedGroup
                    
                    logger.logMembershipChange(contact: contact, group: group, action: "REMOVE", wasMember: wasMember, isMember: false)
                    
                    // Update group participants in database using source-based approach
                    logger.log("💾 Triggering database update for group: \(group.name) after contact left", level: "DATABASE_TRIGGER", contact: contact, group: group, operation: "CONTACT_LEFT")
                    
                    // Get database ID for the group
                    var databaseId = group.databaseId
                    if databaseId == nil {
                        databaseId = getGroupDatabaseId(name: group.name)
                    }
                    
                    if let dbId = databaseId {
                        removeParticipantFromGroup(
                            contact: contact,
                            groupDatabaseId: dbId,
                            sourceType: "Canvas Group Circle",
                            sourceUUID: group.id.uuidString, // This is the Group Circle UUID (UI element ID)
                            logger: logger
                        )
                    }
                } else {
                    logger.log("✅ Contact not a member - no change needed", level: "MEMBERSHIP", contact: contact, group: group, operation: "NO_CHANGE")
                }
            }
        }
        
        logger.log("✅ Completed group membership recalculation for contact: \(contact.name)", level: "MEMBERSHIP_RECALC", contact: contact, operation: "COMPLETE")
        logger.logRecalculationComplete(contactCount: 1, groupCount: groups.count)
    }
    
    private func removeContactFromAllGroups(_ contactId: UUID) {
        let logger = GroupBehaviorLogger.shared
        
        // Find the contact for logging
        let contact = contacts.first { $0.id == contactId }
        logger.log("Removing contact from all groups", level: "REMOVE_FROM_ALL", contact: contact, operation: "START")
        
        var removedFromGroups = 0
        
        // Remove the contact from all groups
        for groupIndex in groups.indices {
            var group = groups[groupIndex]
            if group.members.contains(contactId) {
                group.members.remove(contactId)
                groups[groupIndex] = group
                
                if let contact = contact {
                    logger.logMembershipChange(contact: contact, group: group, action: "REMOVE_FROM_ALL", wasMember: true, isMember: false)
                }
                removedFromGroups += 1
                
                // Update group participants in database
                updateGroupParticipantsInDatabase(group: group)
            }
        }
        
        logger.log("Removed contact from \(removedFromGroups) groups", level: "REMOVE_FROM_ALL", contact: contact, operation: "COMPLETE")
    }
    
    // MARK: - Ellipse Overlap Detection
    
    /// Alternative overlap detection using ellipse parameters (position, width, height, rotation)
    /// Falls back to circular overlap detection if ellipse parameters are not valid
    private func detectOverlapWithEllipse(contact: ContactNode, group: GroupCircle) -> Bool {
        // Check if group has valid ellipse parameters (width != height or rotation != 0)
        let hasEllipseParams = group.width != group.height || group.rotation != 0
        
        if hasEllipseParams {
            return detectEllipseOverlap(contact: contact, group: group)
        } else {
            // Fall back to circular overlap detection for backward compatibility
            let distance = contact.position.distance(to: group.center)
            return distance <= group.averageRadius
        }
    }
    
    /// Ellipse overlap detection algorithm
    private func detectEllipseOverlap(contact: ContactNode, group: GroupCircle) -> Bool {
        let contactCenter = contact.position
        let ellipseCenter = group.center
        let ellipseWidth = group.width
        let ellipseHeight = group.height
        let rotation = group.rotation
        
        // Translate contact position relative to ellipse center
        let translatedPoint = CGPoint(
            x: contactCenter.x - ellipseCenter.x,
            y: contactCenter.y - ellipseCenter.y
        )
        
        // Rotate point by negative ellipse rotation to align with ellipse axes
        let cosTheta = cos(-rotation)
        let sinTheta = sin(-rotation)
        let rotatedPoint = CGPoint(
            x: translatedPoint.x * cosTheta - translatedPoint.y * sinTheta,
            y: translatedPoint.x * sinTheta + translatedPoint.y * cosTheta
        )
        
        // Check if point is inside ellipse using standard ellipse equation
        // (x/a)² + (y/b)² <= 1
        let a = ellipseWidth / 2  // Semi-major axis
        let b = ellipseHeight / 2 // Semi-minor axis
        
        let ellipseEquation = (rotatedPoint.x * rotatedPoint.x) / (a * a) + 
                             (rotatedPoint.y * rotatedPoint.y) / (b * b)
        
        return ellipseEquation <= 1.0
    }
    
    private func calculateInitialGroupMembership(for group: GroupCircle) {
        let logger = GroupBehaviorLogger.shared
        logger.log("🆕 Calculating initial group membership for new group: \(group.name)", level: "INITIAL_MEMBERSHIP", group: group, operation: "START")
        
        // Calculate which contacts are initially inside this group
        var memberPhones: [String] = []
        
        for contact in contacts {
            // Use alternative ellipse overlap detection if group has valid ellipse parameters
            let isInside = detectOverlapWithEllipse(contact: contact, group: group)
            let distance = contact.position.distance(to: group.center) // For logging
            
            logger.logOverlapDetection(contact: contact, group: group, distance: distance, isInside: isInside)
            
            if isInside {
                // Contact is inside the new group
                logger.log("🎯 INITIAL CONTACT ADDED TO GROUP: \(contact.name) is inside new group \(group.name)", level: "INITIAL_MEMBERSHIP", contact: contact, group: group, operation: "CONTACT_ADDED")
                
                memberPhones.append(contact.phone)
                
                // Update the group in the groups array UI state
                if let groupIndex = groups.firstIndex(where: { $0.id == group.id }) {
                    groups[groupIndex].members.insert(contact.id)
                }
                
                logger.logMembershipChange(contact: contact, group: group, action: "INITIAL_ADD", wasMember: false, isMember: true)
            } else {
                logger.log("✅ Contact \(contact.name) is outside new group \(group.name) - no action needed", level: "INITIAL_MEMBERSHIP", contact: contact, group: group, operation: "CONTACT_OUTSIDE")
            }
        }
        
        logger.log("✅ Initial group membership calculation complete - Found \(memberPhones.count) contacts in \(group.name)", level: "INITIAL_MEMBERSHIP", group: group, operation: "COMPLETE")
        
        // Update group members in database using SQLiteDataProvider (if group has been saved)
        if !memberPhones.isEmpty {
            Task {
                // Find the ContactGroup in dataProvider by name
                if let contactGroup = dataProvider?.groups.first(where: { $0.name == group.name }) {
                    do {
                        try await dataProvider?.updateGroupMembers(groupId: contactGroup.id, members: memberPhones)
                        print("✅ Updated group members in database via SQLiteDataProvider: \(memberPhones.count) members")
                        logger.log("✅ Database update complete for \(group.name) - \(memberPhones.count) members", level: "SUCCESS", group: group, operation: "DATABASE_UPDATE_COMPLETE")
                    } catch {
                        print("❌ Failed to update group members: \(error)")
                        logger.log("❌ Failed to update group members: \(error)", level: "ERROR", group: group, operation: "DATABASE_UPDATE_FAILED")
                    }
                }
            }
        }
    }
    
    private func updateGroupParticipantsInDatabase(group: GroupCircle) {
        let logger = GroupBehaviorLogger.shared
        
        logger.log("🔄 Starting database update for group: \(group.name) (ID: \(group.id))", level: "DATABASE_UPDATE", group: group, operation: "START")
        logger.log("📊 Current group members count: \(group.members.count)", level: "DATABASE_UPDATE", group: group, operation: "MEMBER_COUNT")
        
        // Get the group's database ID for database operations
        var databaseId = group.databaseId
        if databaseId == nil {
            logger.log("⚠️ Group has no database ID, looking up by name: \(group.name)", level: "WARNING", group: group, operation: "LOOKUP_DATABASE_ID")
            print("⚠️ Group \(group.name) has no database ID, looking up by name")
            databaseId = getGroupDatabaseId(name: group.name)
        }
        
        guard let finalDatabaseId = databaseId else {
            logger.log("❌ Could not find database ID for group: \(group.name)", level: "ERROR", group: group, operation: "NO_DATABASE_ID")
            print("❌ Could not find database ID for group: \(group.name)")
            return
        }
        
        logger.log("✅ Using database ID: \(finalDatabaseId) for group: \(group.name)", level: "DATABASE_UPDATE", group: group, operation: "DATABASE_ID_FOUND")
        print("✅ Using database ID: \(finalDatabaseId) for group: \(group.name)")
        
        // For each contact in the group, add them with Canvas Group Circle source
        for contactId in group.members {
            guard let contact = contacts.first(where: { $0.id == contactId }) else {
                logger.log("⚠️ Could not find contact with ID: \(contactId)", level: "WARNING", group: group, operation: "CONTACT_NOT_FOUND")
                continue
            }
            
            addParticipantToGroup(
                contact: contact, 
                groupDatabaseId: finalDatabaseId, 
                sourceType: "Canvas Group Circle", 
                sourceUUID: group.id.uuidString, // This is the Group Circle UUID (UI element ID)
                logger: logger
            )
        }
        
        // TODO: Add canvasCleanup() function call here to help clean up the canvas when needed later
        // This should remove participants with no active sources
    }
    
    // MARK: - Source-Based Participant Management
    
    /// Add a participant to a group with a specific source
    /// - Parameters:
    ///   - contact: The contact to add
    ///   - groupDatabaseId: The integer database ID from the groups table
    ///   - sourceType: The type of source (e.g., "Canvas Group Circle", "Group Tool Bar")
    ///   - sourceUUID: The UUID of the UI element that represents this source (Group Circle UUID, not group ID)
    private func addParticipantToGroup(
        contact: ContactNode, 
        groupDatabaseId: Int, 
        sourceType: String, 
        sourceUUID: String, 
        logger: GroupBehaviorLogger
    ) {
        logger.log("📝 Adding participant: \(contact.name) to group \(groupDatabaseId) with source \(sourceType): \(sourceUUID)", 
                  level: "DATABASE_UPDATE", operation: "ADD_PARTICIPANT")
        
        // Create participant with source information using Swift GroupParticipant struct
        let participantSource = GroupParticipant.ParticipantSource(
            Type: sourceType,
            UUID: sourceUUID
        )
        
        let participant = GroupParticipant(
            id: contact.phone,
            name: contact.name,
            UUID: contact.contactUUID?.uuidString ?? contact.id.uuidString,
            Source: [participantSource]
        )
        
        // Use Swift GroupManager instead of Python script
        let groupManager = GroupManager()
        let success = groupManager.updateGroupParticipants(
            groupId: String(groupDatabaseId),
            participants: [participant]
        )
        
        if success {
            logger.log("✅ Successfully added participant to group using Swift GroupManager", level: "SUCCESS", operation: "ADD_PARTICIPANT")
            print("✅ Successfully added participant \(contact.name) to group \(groupDatabaseId)")
        } else {
            logger.log("❌ Failed to add participant using Swift GroupManager", level: "ERROR", operation: "ADD_PARTICIPANT_FAILED")
            print("❌ Failed to add participant \(contact.name) to group \(groupDatabaseId)")
        }
    }
    
    /// Remove a participant from a group by removing the specific source
    /// - Parameters:
    ///   - contact: The contact to remove
    ///   - groupDatabaseId: The integer database ID from the groups table
    ///   - sourceType: The type of source to remove (e.g., "Canvas Group Circle", "Group Tool Bar")
    ///   - sourceUUID: The UUID of the UI element that represents this source (Group Circle UUID, not group ID)
    private func removeParticipantFromGroup(
        contact: ContactNode, 
        groupDatabaseId: Int, 
        sourceType: String, 
        sourceUUID: String, 
        logger: GroupBehaviorLogger
    ) {
        logger.log("📝 Removing participant: \(contact.name) from group \(groupDatabaseId) by removing source \(sourceType): \(sourceUUID)", 
                  level: "DATABASE_UPDATE", operation: "REMOVE_PARTICIPANT")
        
        // Create participant with source information to remove using Swift GroupParticipant struct
        let participantSource = GroupParticipant.ParticipantSource(
            Type: sourceType,
            UUID: sourceUUID
        )
        
        let participantToRemove = GroupParticipant(
            id: contact.phone,
            name: contact.name,
            UUID: contact.contactUUID?.uuidString ?? contact.id.uuidString,
            Source: [participantSource]
        )
        
        // Use Swift GroupManager instead of Python script
        let groupManager = GroupManager()
        let success = groupManager.removeGroupParticipantSource(
            groupId: String(groupDatabaseId),
            participantsToRemove: [participantToRemove]
        )
        
        if success {
            logger.log("✅ Successfully removed participant source from group using Swift GroupManager", level: "SUCCESS", operation: "REMOVE_PARTICIPANT")
            print("✅ Successfully removed participant \(contact.name) from group \(groupDatabaseId)")
        } else {
            logger.log("❌ Failed to remove participant source using Swift GroupManager", level: "ERROR", operation: "REMOVE_PARTICIPANT_FAILED")
            print("❌ Failed to remove participant \(contact.name) from group \(groupDatabaseId)")
        }
    }
    
    // -- Old -- Deprecated function that used Python scripts
    // Replaced by direct GroupManager calls in addParticipantToGroup() and removeParticipantFromGroup()
    // This function is no longer used as of the Swift migration completion
    
    // -- Old -- Replaced by SQLiteDataProvider.createGroup()
    private func OLD_createGroupInDatabase(group: GroupCircle, completion: @escaping (Int?) -> Void) {
        let logger = GroupBehaviorLogger.shared
        
        logger.log("🆕 Looking up or creating group in database: \(group.name)", level: "CREATE_GROUP", group: group, operation: "START")
        
        // First, try to find the group by name in the database
        let existingGroupId = getGroupDatabaseId(name: group.name)
        if let existingId = existingGroupId {
            logger.log("✅ Found existing group in database with ID: \(existingId)", level: "SUCCESS", group: group, operation: "FOUND_EXISTING")
            completion(existingId)
            return
        }
        
        // Group doesn't exist, create it
        logger.log("🆕 Group not found, creating new group in database: \(group.name)", level: "CREATE_GROUP", group: group, operation: "CREATE_NEW")
        
        // Use the OLD synchronous createGroupInDatabase method (now prefixed with OLD_)
        let databaseGroupId = OLD_createGroupInDatabase(groupId: group.id.uuidString, name: group.name, color: group.color.toHexString(), canvasId: currentMapId.uuidString)
        if let dbId = databaseGroupId {
            logger.log("✅ Successfully created group in database with ID: \(dbId)", level: "SUCCESS", group: group, operation: "CREATE_GROUP")
            completion(dbId)
        } else {
            logger.log("❌ Failed to create group in database", level: "ERROR", group: group, operation: "CREATE_GROUP")
            completion(nil)
        }
    }
    
    private func refreshGroupsToolbar() async {
        let logger = GroupBehaviorLogger.shared
        logger.log("🔄 Refreshing groups toolbar after group changes", level: "TOOLBAR_REFRESH", operation: "START")
        
        // Get the data provider and refresh groups
        if let dataProvider = self.dataProvider {
            // Reload groups from database
            print("🔍 DEBUG: refreshGroupsToolbar() calling loadDataFromDatabase()")
            await dataProvider.loadDataFromDatabase()
            
            // Refresh the groups view model
            print("🔍 DEBUG: refreshGroupsToolbar() calling refreshGroups()")
            await GlobalCanvasService.shared.groupsViewModel.refreshGroups(from: dataProvider)
            
            logger.log("✅ Successfully refreshed groups toolbar", level: "SUCCESS", operation: "TOOLBAR_REFRESH")
        } else {
            logger.log("❌ No data provider available for toolbar refresh", level: "ERROR", operation: "TOOLBAR_REFRESH")
        }
    }
    
    // MARK: - Coordinate Conversion
    
    private func viewToCanvas(_ point: CGPoint, viewSize: CGSize) -> CGPoint {
        let transform = CanvasTransform(zoom: canvasState.zoom, pan: canvasState.pan)
        // Convert bottom-left view coordinates to top-left for the transform
        let topLeftViewPoint = CGPoint(
            x: point.x,
            y: viewSize.height - point.y
        )
        let topLeftCanvasPoint = transform.viewToCanvas(topLeftViewPoint)
        // Convert to bottom-left canvas coordinates
        return CGPoint(
            x: topLeftCanvasPoint.x,
            y: -topLeftCanvasPoint.y
        )
    }
    
    // MARK: - Hit Testing
    func hitTest(at point: CGPoint, in viewSize: CGSize) -> HitTestResult? {
        let canvasPoint = viewToCanvas(point, viewSize: viewSize)
        
        // Test contacts first (they're on top)
        for contact in contacts.reversed() {
            let contactRect = CGRect(
                x: contact.position.x - contact.size.width / 2,
                y: contact.position.y - contact.size.height / 2,
                width: contact.size.width,
                height: contact.size.height
            )
            
            if contactRect.contains(canvasPoint) {
                return .contact(contact.id)
            }
        }
        
        // Test groups
        for group in groups.reversed() {
            let distance = canvasPoint.distance(to: group.center)
            if distance <= group.averageRadius {
                return .group(group.id)
            }
        }
        
        return nil
    }
    
    // MARK: - Mode Switching
    func toggleSelectionMode() {
        isSelectionMode = true
        canvasState.mode = .select
        isGroupAddMode = false
    }
    
    func toggleHandMode() {
        if isHandMode {
            // Currently in hand mode, switch to selection mode
            canvasState.mode = .select
            isSelectionMode = true
        } else {
            // Currently not in hand mode, switch to hand mode
            canvasState.mode = .hand
            isSelectionMode = false
        }
        isGroupAddMode = false
    }
    
    func toggleGroupAddMode() {
        print("🔧 GroupsMapViewModel: toggleGroupAddMode called - activating group add mode")
        isGroupAddMode = true
        isSelectionMode = false
        canvasState.mode = .addGroup
        print("🔧 GroupsMapViewModel: Group add mode activated - isGroupAddMode: \(isGroupAddMode), isSelectionMode: \(isSelectionMode)")
    }
    
    func exitGroupAddMode() {
        print("🔧 GroupsMapViewModel: exitGroupAddMode called - deactivating group add mode")
        isGroupAddMode = false
        isSelectionMode = true
        canvasState.mode = .select
        print("🔧 GroupsMapViewModel: Group add mode deactivated - isGroupAddMode: \(isGroupAddMode), isSelectionMode: \(isSelectionMode)")
    }
    
    // MARK: - Mode Management
    func setMode(_ mode: CanvasMode) {
        canvasState.mode = mode
        // REMOVED: saveImmediately() - mode changes should not trigger saves
    }
    
    func createGroupFromSelection() {
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "CREATE_GROUP_FROM_SELECTION_CALLED",
            details: "Creating group from selection with \(selectedContacts.count) contacts and \(selectedGroups.count) groups",
            success: true
        )
        
        print("🔧 GroupsMapViewModel.createGroupFromSelection() called")
        print("🔧 Selected contacts: \(selectedContacts.count)")
        print("🔧 Selected groups: \(selectedGroups.count)")
        
        // Check if we have selected items
        let hasSelection = !selectedContacts.isEmpty || !selectedGroups.isEmpty
        guard hasSelection else { 
            print("❌ No selection to create group from")
            return 
        }
        
        // Calculate bounds of selected items
        var minX: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude
        
        // Include selected contacts
        for contactId in selectedContacts {
            if let contact = contacts.first(where: { $0.id == contactId }) {
                let contactRect = CGRect(
                    x: contact.position.x - contact.size.width / 2,
                    y: contact.position.y - contact.size.height / 2,
                    width: contact.size.width,
                    height: contact.size.height
                )
                minX = min(minX, contactRect.minX)
                maxX = max(maxX, contactRect.maxX)
                minY = min(minY, contactRect.minY)
                maxY = max(maxY, contactRect.maxY)
            }
        }
        
        // Include selected groups
        for groupId in selectedGroups {
            if let group = groups.first(where: { $0.id == groupId }) {
                let groupRect = CGRect(
                    x: group.center.x - group.radius,
                    y: group.center.y - group.radius,
                    width: group.radius * 2,
                    height: group.radius * 2
                )
                minX = min(minX, groupRect.minX)
                maxX = max(maxX, groupRect.maxX)
                minY = min(minY, groupRect.minY)
                maxY = max(maxY, groupRect.maxY)
            }
        }
        
        // Calculate center and radius
        let center = CGPoint(
            x: (minX + maxX) / 2,
            y: (minY + maxY) / 2
        )
        
        let boundsWidth = maxX - minX
        let boundsHeight = maxY - minY
        let diagonal = sqrt(boundsWidth * boundsWidth + boundsHeight * boundsHeight)
        let radius = max(100, diagonal / 2 + 50) // Minimum 100 radius, plus padding
        let groupWidth = radius * 2
        let groupHeight = radius * 2
        
        print("🔧 Calculated group center: \(center)")
        print("🔧 Calculated group radius: \(radius)")
        
        // Get next group name
        let nextGroupName = getNextGroupName()
        
        // Step 1: Create the UI GroupCircle first
        let newGroupCircle = GroupCircle(
            id: UUID(),
            name: nextGroupName,
            center: center,
            radius: radius,
            color: .blue,
            isSelected: false,
            databaseId: nil // Will be set after database creation
        )
        var updatedGroupCircle = newGroupCircle
        updatedGroupCircle.width = groupWidth
        updatedGroupCircle.height = groupHeight
        
        // Step 2: Create ContactGroup for database (using SQLiteDataProvider)
        var newContactGroup = ContactGroup(
            name: nextGroupName,
            color: .blue
        )
        newContactGroup.canvases.insert(currentMapId)
        
        // Get member phones from selected contacts
        let memberPhones = selectedContacts.compactMap { contactId in
            contacts.first(where: { $0.id == contactId })?.phone
        }
        newContactGroup.memberPhones = Set(memberPhones)
        
        print("🔧 Creating ContactGroup in database: \(newContactGroup.name) with \(memberPhones.count) members")
        
        // Step 3: Create group in database using SQLiteDataProvider
        Task {
            do {
                try await dataProvider?.createGroup(newContactGroup)
                print("✅ Group created in database via SQLiteDataProvider")
                
                // Extract database ID from the UUID that was created
                if let createdGroup = dataProvider?.groups.first(where: { $0.name == nextGroupName }) {
                    let dbId = extractDatabaseId(from: createdGroup.id)
                    
                    // Update the GroupCircle with the database ID
                    await MainActor.run {
                        updatedGroupCircle.databaseId = dbId
                        groups.append(updatedGroupCircle)
                        print("🔧 Added GroupCircle to canvas with database ID: \(dbId)")
                        print("🔧 Total groups now: \(groups.count)")
                    }
                    
                    // Save canvas immediately
                    await MainActor.run {
                        saveImmediately()
                    }
                }
                
                DatabaseLogger.shared.logDatabaseOperation(
                    operation: "CREATE_GROUP_FROM_SELECTION_SUCCESS",
                    details: "Successfully created group from selection: \(newContactGroup.id) at center \(center)",
                    success: true
                )
            } catch {
                print("❌ Failed to create group: \(error)")
                DatabaseLogger.shared.logDatabaseOperation(
                    operation: "CREATE_GROUP_FROM_SELECTION_FAILED",
                    details: "Failed to create group: \(error.localizedDescription)",
                    success: false
                )
            }
        }
        
        // Clear selection and exit group add mode
        clearSelection()
        exitGroupAddMode()
    }
    
    func addNewGroupAtPosition(_ position: CGPoint) {
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "ADD_NEW_GROUP_AT_POSITION_CALLED",
            details: "Adding new group at position \(position)",
            success: true
        )
        
        print("🔧 GroupsMapViewModel.addNewGroupAtPosition() called")
        print("🔧 Position: \(position)")
        
        // Get next group name
        let nextGroupName = getNextGroupName()
        
        // Step 1: Create the UI GroupCircle first
        let newGroupCircle = GroupCircle(
            id: UUID(),
            name: nextGroupName,
            center: position,
            radius: 100,
            color: .blue,
            isSelected: false,
            databaseId: nil // Will be set after database creation
        )
        var updatedGroupCircle = newGroupCircle
        updatedGroupCircle.width = 200
        updatedGroupCircle.height = 200
        
        // Step 2: Create ContactGroup for database (using SQLiteDataProvider)
        var newContactGroup = ContactGroup(
            name: nextGroupName,
            color: .blue
        )
        newContactGroup.canvases.insert(currentMapId)
        
        print("🔧 Creating ContactGroup in database: \(newContactGroup.name)")
        
        // Step 3: Create group in database using SQLiteDataProvider
        Task {
            do {
                try await dataProvider?.createGroup(newContactGroup)
                print("✅ Group created in database via SQLiteDataProvider")
                
                // Extract database ID from the UUID that was created
                if let createdGroup = dataProvider?.groups.first(where: { $0.name == nextGroupName }) {
                    let dbId = extractDatabaseId(from: createdGroup.id)
                    
                    // Update the GroupCircle with the database ID
                    await MainActor.run {
                        updatedGroupCircle.databaseId = dbId
                        groups.append(updatedGroupCircle)
                        print("🔧 Added GroupCircle to canvas with database ID: \(dbId)")
                        print("🔧 Total groups now: \(groups.count)")
                        
                        // Calculate initial membership for the new group
                        calculateInitialGroupMembership(for: updatedGroupCircle)
                        
                        // Save canvas immediately
                        saveImmediately()
                    }
                }
                
                DatabaseLogger.shared.logDatabaseOperation(
                    operation: "ADD_NEW_GROUP_AT_POSITION_SUCCESS",
                    details: "Successfully added new group: \(newContactGroup.id) at position \(position)",
                    success: true
                )
            } catch {
                print("❌ Failed to create group: \(error)")
                DatabaseLogger.shared.logDatabaseOperation(
                    operation: "ADD_NEW_GROUP_AT_POSITION_FAILED",
                    details: "Failed to create group: \(error.localizedDescription)",
                    success: false
                )
            }
        }
        
        // Clear selection and exit group add mode
        clearSelection()
        exitGroupAddMode()
    }
    
    /// Extract database ID from UUID (reverse of UUID generation in SQLiteDataProvider)
    /// The UUID format is: "00000000-0000-0000-0000-%012d"
    private func extractDatabaseId(from uuid: UUID) -> Int {
        let uuidString = uuid.uuidString
        let last12Chars = String(uuidString.suffix(12))
        return Int(last12Chars) ?? 0
    }
    
    private func getNextGroupName() -> String {
        return groupManager.getNextGroupName()
    }
    
    // -- Old -- Replaced by SQLiteDataProvider.createGroup()
    private func OLD_createGroupInDatabase(groupId: String, name: String, color: String, canvasId: String) -> Int? {
        guard let process = ScriptPathResolver.createPythonProcess(scriptName: "canvas_manager.py", arguments: [
            "create_group",
            "--name", name,
            "--color", color
        ]) else {
            print("❌ Failed to create process for group creation")
            return nil
        }
        
        // Set up output pipes
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                print("✅ Created group in database: \(name)")
                
                // Get the created group's ID directly from the output
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if let outputString = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !outputString.isEmpty {
                    if let data = try? JSONSerialization.jsonObject(with: outputData) as? [String: Any],
                       let groupId = data["id"] as? Int {
                        print("✅ Got group ID directly from creation: \(groupId)")
                        return groupId
                    }
                }
                
                // Fallback to old method if direct ID retrieval fails
                print("⚠️ Direct ID retrieval failed, falling back to name lookup")
                return getGroupIdByName(name: name)
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if let errorString = String(data: errorData, encoding: .utf8) {
                    print("❌ Failed to create group in database: \(errorString)")
                } else {
                    print("❌ Failed to create group in database: Unknown error")
                }
                return nil
            }
        } catch {
            print("Error creating group in database: \(error)")
            return nil
        }
    }
    
    private func getGroupIdByName(name: String) -> Int? {
        guard let process = ScriptPathResolver.createPythonProcess(scriptName: "canvas_manager.py", arguments: [
            "get_all_groups"
        ]) else {
            return nil
        }
        
        // Set up output pipes
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if let outputString = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !outputString.isEmpty {
                    if let data = try? JSONSerialization.jsonObject(with: outputData) as? [[String: Any]] {
                        // Find the most recent group with this name
                        for group in data {
                            if let groupName = group["name"] as? String,
                               groupName == name,
                               let groupId = group["id"] as? Int {
                                return groupId
                            }
                        }
                    }
                }
            }
        } catch {
            print("Error getting group ID by name: \(error)")
        }
        
        return nil
    }
    
    /// Clean up canvas elements by removing references to deleted groups
    /// This should only be called when explicitly needed (e.g., after group deletion)
    /// to avoid race conditions during normal canvas loading
    func cleanupCanvasElementsExplicit(canvas: Canvas) -> Canvas {
        print("🔧 ========== EXPLICIT CANVAS CLEANUP REQUESTED ==========")
        return cleanupCanvasElements(canvas: canvas)
    }
    
    private func cleanupCanvasElements(canvas: Canvas) -> Canvas {
        print("🔧 ========== CANVAS CLEANUP STARTED ==========")
        print("🔧 Canvas ID: \(canvas.id)")
        print("🔧 Canvas Name: \(canvas.name)")
        print("🔧 Total canvas elements before cleanup: \(canvas.elements.count)")
        
        // Log all current canvas elements
        print("🔧 Current canvas elements:")
        for (index, element) in canvas.elements.enumerated() {
            print("🔧   Element \(index): ID='\(element.id)', Type=\(element.elementType.rawValue), Location=\(element.location)")
            if element.elementType == .group {
                print("🔧     Group UUID: \(element.groupUUID ?? "nil")")
            }
        }
        
        // Get all existing groups from database
        guard let process = ScriptPathResolver.createPythonProcess(scriptName: "canvas_manager.py", arguments: [
            "get_all_groups"
        ]) else {
            print("❌ Failed to create process for getting groups during cleanup")
            return canvas
        }
        
        // Set up output pipes
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if let outputString = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !outputString.isEmpty {
                    if let groupsData = try? JSONSerialization.jsonObject(with: outputData) as? [[String: Any]] {
                        
                        print("🔧 Raw groups data from database: \(groupsData.count) groups")
                        
                        // Create set of existing group IDs
                        let existingGroupIds = Set(groupsData.compactMap { groupData in
                            groupData["id"] as? String
                        })
                        
                        print("🔧 Found \(existingGroupIds.count) existing groups in database")
                        print("🔧 Database group IDs: \(Array(existingGroupIds).sorted())")
                        
                        // Log detailed group information
                        for groupData in groupsData {
                            if let groupId = groupData["id"] as? String,
                               let groupName = groupData["name"] as? String {
                                print("🔧   Database Group: ID='\(groupId)', Name='\(groupName)'")
                            }
                        }
                        
                        // Filter out canvas elements that reference non-existent groups
                        let validElements = canvas.elements.filter { element in
                            if element.elementType == .group {
                                let groupExists = existingGroupIds.contains(element.id)
                                print("🔍 DEBUG: Checking group element ID '\(element.id)' against database groups")
                                print("🔍 DEBUG: Database group IDs: \(Array(existingGroupIds).sorted())")
                                print("🔍 DEBUG: Group exists in database: \(groupExists)")
                                print("🔍 DEBUG: Element groupUUID: \(element.groupUUID ?? "nil")")
                                
                                if !groupExists {
                                    print("🗑️ REMOVING canvas element for missing group: \(element.id)")
                                    print("🗑️   Element location: \(element.location)")
                                    print("🗑️   Element groupUUID: \(element.groupUUID ?? "nil")")
                                } else {
                                    print("✅ KEEPING canvas element for existing group: \(element.id)")
                                }
                                return groupExists
                            } else {
                                print("✅ KEEPING non-group element: \(element.id) (type: \(element.elementType.rawValue))")
                                return true
                            }
                        }
                        
                        let removedCount = canvas.elements.count - validElements.count
                        print("🔧 Cleanup results:")
                        print("🔧   Original elements: \(canvas.elements.count)")
                        print("🔧   Valid elements: \(validElements.count)")
                        print("🔧   Removed elements: \(removedCount)")
                        
                        if removedCount > 0 {
                            print("🔧 Removed \(removedCount) canvas elements for deleted groups")
                            
                            // Log what elements were removed
                            let removedElements = canvas.elements.filter { element in
                                !validElements.contains { $0.id == element.id }
                            }
                            print("🔧 Removed elements:")
                            for element in removedElements {
                                print("🔧   Removed: ID='\(element.id)', Type=\(element.elementType.rawValue), Location=\(element.location)")
                            }
                            
                            // Create cleaned canvas but don't save it immediately
                            // This prevents overwriting recent changes with cached data
                            let cleanedCanvas = Canvas(
                                id: canvas.id,
                                name: canvas.name,
                                elements: validElements,
                                canvasType: canvas.canvasType,
                                canvasState: canvas.canvasState
                            )
                            
                            print("🔧 Created cleaned canvas with \(validElements.count) elements (removed \(removedCount) deleted group references)")
                            print("🔧 Note: Cleaned canvas will be saved through normal save process to preserve recent changes")
                            print("🔧 ========== CANVAS CLEANUP COMPLETED ==========")
                            
                            return cleanedCanvas
                        } else {
                            print("🔧 No elements needed to be removed - canvas is clean")
                        }
                    } else {
                        print("❌ Failed to parse groups data as JSON")
                        print("❌ Raw output: \(outputString)")
                    }
                } else {
                    print("❌ No groups data received from database")
                }
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if let errorString = String(data: errorData, encoding: .utf8) {
                    print("❌ Failed to get groups during cleanup (exit code: \(process.terminationStatus))")
                    print("❌ Error: \(errorString)")
                }
            }
        } catch {
            print("❌ Error during canvas cleanup: \(error)")
        }
        
        print("🔧 ========== CANVAS CLEANUP COMPLETED (NO CHANGES) ==========")
        // Return original canvas if cleanup failed or no changes needed
        return canvas
    }
    
    private func loadContactsFromDatabase(canvasContacts: [CanvasElement], dataProvider: SQLiteDataProvider?) -> [ContactNode] {
        print("🔧 Loading contacts from canvas elements...")
        print("🔧 DataProvider available: \(dataProvider != nil)")
        print("🔧 DataProvider connected: \(dataProvider?.isConnectedToDatabase ?? false)")
        print("🔧 DataProvider contact count: \(dataProvider?.contacts.count ?? 0)")
        var loadedContacts: [ContactNode] = []
        
        for element in canvasContacts {
            print("🔧 Processing contact element: \(element.id)")
            print("🔧 Element contactUUID: \(element.contactUUID ?? "nil")")
            
            // Create a contact node from the canvas element with dataProvider for contact lookup
            let contactNode = ContactNode.fromCanvasElement(element, dataProvider: dataProvider)
            
            print("✅ Loaded contact data: \(contactNode.name) (\(contactNode.phone))")
            print("✅ Contact has profile photo: \(contactNode.profilePhotoData != nil)")
            loadedContacts.append(contactNode)
        }
        
        print("✅ Loaded \(loadedContacts.count) contacts from database")
        return loadedContacts
    }
    
    private func loadGroupsFromDatabase(canvasGroups: [CanvasElement]) -> [GroupCircle] {
        var loadedGroups: [GroupCircle] = []
        
        print("🔧 loadGroupsFromDatabase: Loading \(canvasGroups.count) group elements from canvas")
        
        // Get all groups from dataProvider (no Python scripts needed!)
        guard let dataProvider = self.dataProvider else {
            print("❌ No dataProvider available for loading groups")
            print("⚠️ Falling back to canvas element data for groups")
            return canvasGroups.compactMap { GroupCircle.fromCanvasElement($0, dataProvider: nil) }
        }
        
        print("✅ DataProvider available with \(dataProvider.groups.count) groups")
        
        // For each canvas group element, find the corresponding ContactGroup from database
        for canvasGroup in canvasGroups {
            // Get database integer ID from canvas element
            guard let dbId = Int(canvasGroup.id) else {
                print("⚠️ Invalid database ID in canvas element: \(canvasGroup.id)")
                continue
            }
            
            print("🔧 Looking for group with database ID: \(dbId)")
            
            // Find ContactGroup by database integer ID (not UUID!)
            guard let contactGroup = dataProvider.groups.first(where: { $0.databaseId == dbId }) else {
                print("⚠️ No group found for database ID: \(dbId)")
                print("   Available groups: \(dataProvider.groups.map { "\($0.name) (dbId: \($0.databaseId ?? -1))" }.joined(separator: ", "))")
                continue
            }
            
            print("✅ Found group '\(contactGroup.name)' with color \(contactGroup.color) for database ID: \(dbId)")
            
            // Create GroupCircle with real name and color from database
            let group = GroupCircle(
                id: UUID(),  // Generate new UUID (separate from database ID)
                name: contactGroup.name,  // Real name from database!
                center: canvasGroup.location,
                radius: canvasGroup.width / 2,
                color: contactGroup.color,  // Real color from database!
                rotation: canvasGroup.rotation,
                databaseId: dbId  // Store database ID for future lookups
            )
            var updatedGroup = group
            updatedGroup.width = canvasGroup.width
            updatedGroup.height = canvasGroup.height
            loadedGroups.append(updatedGroup)
        }
        
        print("✅ Loaded \(loadedGroups.count) groups from database")
        return loadedGroups
    }
    
    private func addContactToCanvas(contactId: String, canvasId: String) {
        guard let process = ScriptPathResolver.createPythonProcess(scriptName: "canvas_manager.py", arguments: [
            "add_contact_to_canvas",
            "--contact-id", contactId,
            "--canvas-id", canvasId
        ]) else {
            print("❌ Failed to create process for adding contact to canvas")
            return
        }
        
        // Set up output pipes
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                print("✅ Added contact \(contactId) to canvas \(canvasId)")
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if let errorString = String(data: errorData, encoding: .utf8) {
                    print("❌ Failed to add contact to canvas: \(errorString)")
                } else {
                    print("❌ Failed to add contact to canvas: Unknown error")
                }
            }
        } catch {
            print("Error adding contact to canvas: \(error)")
        }
    }
    
    private func removeContactFromCanvas(contactId: String, canvasId: String) {
        guard let process = ScriptPathResolver.createPythonProcess(scriptName: "canvas_manager.py", arguments: [
            "remove_element",
            "--canvas-id", canvasId,
            "--element-id", contactId
        ]) else {
            print("❌ Failed to create process for removing contact from canvas")
            return
        }
        
        // Set up output pipes
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                print("✅ Removed contact \(contactId) from canvas \(canvasId)")
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if let errorString = String(data: errorData, encoding: .utf8) {
                    print("❌ Failed to remove contact from canvas: \(errorString)")
                } else {
                    print("❌ Failed to remove contact from canvas: Unknown error")
                }
            }
        } catch {
            print("Error removing contact from canvas: \(error)")
        }
    }
    
    // -- Old -- Replaced by SQLiteDataProvider.addCanvasToGroup()
    private func OLD_addGroupToCanvas(groupId: String, canvasId: String) {
        guard let process = ScriptPathResolver.createPythonProcess(scriptName: "canvas_manager.py", arguments: [
            "add_group_to_canvas",
            "--group-id", groupId,
            "--canvas-id", canvasId
        ]) else {
            print("❌ Failed to create process for adding group to canvas")
            return
        }
        
        // Set up output pipes
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                print("✅ Added group \(groupId) to canvas \(canvasId)")
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if let errorString = String(data: errorData, encoding: .utf8) {
                    print("❌ Failed to add group to canvas: \(errorString)")
                } else {
                    print("❌ Failed to add group to canvas: Unknown error")
                }
            }
        } catch {
            print("Error adding group to canvas: \(error)")
        }
    }
    
    // MARK: - Utility Functions
    func findAvailablePosition(near position: CGPoint) -> CGPoint {
        var testPosition = position
        var offset = 1
        
        while contacts.contains(where: { $0.position == testPosition }) {
            testPosition = CGPoint(
                x: position.x + CGFloat(offset),
                y: position.y + CGFloat(offset)
            )
            offset += 1
        }
        
        return testPosition
    }
    
    // MARK: - Force Save Methods (for intentional empty saves)
    func forceSaveCanvas() {
        print("🔧 forceSaveCanvas() called - Bypassing all guards")
        updateStateFromSelection()
        saveCanvasToDatabase()
        lastSaveTime = Date()
    }
    
    func clearCanvasElements() {
        print("🔧 clearCanvasElements() called - Intentionally clearing all elements")
        contacts.removeAll()
        groups.removeAll()
        clearSelection()
        forceSaveCanvas()
    }
    
    // MARK: - Zoom Methods (duplicate removed - using main setZoom function above)
}

// MARK: - Supporting Types

enum HitTestResult {
    case contact(UUID)
    case group(UUID)
}


