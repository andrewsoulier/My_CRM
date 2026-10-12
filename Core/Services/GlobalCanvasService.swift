import SwiftUI
import Combine

@MainActor
class GlobalCanvasService: ObservableObject {
    static let shared = GlobalCanvasService()
    
    // MARK: - Published Properties
    @Published var currentCanvas: Canvas?
    @Published var isCanvasLoaded = false
    @Published var lastAddedContact: Contact?
    @Published var shouldAddContactToCanvas = false
    
    // MARK: - Canvas ViewModels (Centralized to prevent StateObject issues)
    @Published var groupsMapViewModel: GroupsMapViewModel
    @Published var edgeScrollingManager: EdgeScrollingManager
    @Published var contactsViewModel: ContactsViewModel
    @Published var groupsViewModel: GroupsViewModel
    
    // Create gestureCoordinator as a lazy property to maintain state between gesture events
    lazy var gestureCoordinator: CanvasGestureCoordinator = {
        CanvasGestureCoordinator(viewModel: self.groupsMapViewModel)
    }()
    
    // MARK: - Services
    @Published var canvasService = CanvasUpdateService()
    let canvasRepository = DatabaseCanvasRepository()
    private var cancellables = Set<AnyCancellable>()
    
    // Data provider for contact lookups
    private var dataProvider: SQLiteDataProvider?
    
    // MARK: - Canvas State
    private var currentCanvasId: String?
    @Published var availableCanvases: [Canvas] = []
    
    // MARK: - Group Data Synchronization
    func refreshCanvasGroupData(groupId: UUID) {
        print("🔄 GlobalCanvasService: Refreshing canvas group data for group ID: \(groupId)")
        LogManager.shared.info("🔄 GlobalCanvasService: Refreshing canvas group data for group ID: \(groupId)")
        
        // Refresh the group data in the canvas view model
        groupsMapViewModel.refreshGroupDataFromDatabase(groupId: groupId)
    }
    
    private init() {
        print("🚨 GlobalCanvasService.init() called")
        print("GlobalCanvasService: Initializing...")
        
        // Initialize view models and edge scrolling manager
        self.groupsMapViewModel = GroupsMapViewModel()
        self.edgeScrollingManager = EdgeScrollingManager()
        self.contactsViewModel = ContactsViewModel()
        self.groupsViewModel = GroupsViewModel()
        
        setupBindings()
        // TEMPORARILY DISABLED: Defer database operations to avoid recursive locking
        // DispatchQueue.main.async {
        //     self.loadDefaultCanvas()
        // }
    }
    
    // MARK: - Public Methods
    
    /// Set the data provider for contact lookups
    func setDataProvider(_ dataProvider: SQLiteDataProvider) {
        self.dataProvider = dataProvider
        // Also set the dataProvider in the GroupsMapViewModel to avoid StateObject issues
        self.groupsMapViewModel.setDataProvider(dataProvider)
    }
    
    /// Get the data provider for contact lookups
    func getDataProvider() -> SQLiteDataProvider? {
        return dataProvider
    }
    
    /// Set the current active canvas
    func setCurrentCanvas(_ canvas: Canvas?) {
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "GLOBAL_CANVAS_SERVICE_SET_CURRENT",
            details: "Setting current canvas: \(canvas?.name ?? "nil") (ID: \(canvas?.id ?? "nil")) with \(canvas?.elements.count ?? 0) elements",
            success: true
        )
        
        currentCanvas = canvas
        isCanvasLoaded = canvas != nil
        currentCanvasId = canvas?.id
        
        // Load canvas into GroupsMapViewModel if canvas is available
        if let canvas = canvas {
            groupsMapViewModel.loadCanvasFromDatabase(canvas, dataProvider: dataProvider)
        }
        
        // Trigger UI updates for canvas changes
        objectWillChange.send()
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "GLOBAL_CANVAS_SERVICE_SET_CURRENT_COMPLETED",
            details: "Current canvas set successfully: \(canvas?.name ?? "nil") (ID: \(canvas?.id ?? "nil"))",
            success: true
        )
    }
    
    /// Update the current canvas state without triggering loadCanvasFromDatabase (prevents circular dependency)
    func updateCurrentCanvasState(_ canvas: Canvas) {
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "GLOBAL_CANVAS_SERVICE_UPDATE_STATE",
            details: "Updating current canvas state: \(canvas.name) (ID: \(canvas.id)) with \(canvas.elements.count) elements",
            success: true
        )
        
        currentCanvas = canvas
        isCanvasLoaded = true
        currentCanvasId = canvas.id
        
        // Trigger UI updates for canvas contact changes
        objectWillChange.send()
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "GLOBAL_CANVAS_SERVICE_UPDATE_STATE_COMPLETED",
            details: "Current canvas state updated successfully: \(canvas.name) (ID: \(canvas.id))",
            success: true
        )
    }
    
    /// Add a contact to the current canvas
    func addContactToCanvas(_ contact: Contact, at position: CGPoint? = nil) {
        guard currentCanvas != nil else {
            print("No canvas loaded")
            return
        }
        
        let defaultPosition = position ?? CGPoint(x: 200, y: 200)
        
        // Create tags from contact information (same pattern as GroupsMapViewModel)
        var tags: [String] = []
        if let business = contact.business, !business.isEmpty {
            tags.append(business)
        }
        if let contactGroup = contact.contactGroup, !contactGroup.isEmpty {
            tags.append(contactGroup)
        }
        
        // Use GroupsMapViewModel's public addContactFromDrop method to handle all operations
        // This ensures both systems stay in sync and all database operations are handled properly
        groupsMapViewModel.addContactFromDrop(contact, at: defaultPosition)
        
        // The GroupsMapViewModel will handle updating the canvas state through its save mechanism
        // We don't need to update currentCanvas here as it will be updated by the GroupsMapViewModel
        
        // Notify that a contact was added
        lastAddedContact = contact
        shouldAddContactToCanvas = true
        
        // Reset after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.shouldAddContactToCanvas = false
        }
    }
    
    /// Add a group to the current canvas
    func addGroupToCanvas(_ group: ContactGroup, at position: CGPoint? = nil) {
        guard currentCanvas != nil else {
            print("No canvas loaded")
            DragDropLogger.shared.log("Cannot add group: no canvas loaded", operation: "ERROR")
            return
        }
        
        let defaultPosition = position ?? CGPoint(x: 300, y: 300)
        
        DragDropLogger.shared.log(
            "GlobalCanvasService: Adding group '\(group.name)' to canvas at position \(defaultPosition)",
            operation: "GROUP_ADD"
        )
        
        // Use GroupsMapViewModel's public addGroupFromDrop method to handle all operations
        // This ensures both systems stay in sync and all database operations are handled properly
        groupsMapViewModel.addGroupFromDrop(group, at: defaultPosition)
        
        // The GroupsMapViewModel will handle updating the canvas state through its save mechanism
        // We don't need to update currentCanvas here as it will be updated by the GroupsMapViewModel
        
        DragDropLogger.shared.log(
            "GlobalCanvasService: Group '\(group.name)' added to canvas successfully",
            operation: "SUCCESS"
        )
    }
    
    /// Update canvas element position
    func updateElementPosition(elementId: String, to position: CGPoint) {
        guard let canvas = currentCanvas,
              let elementIndex = canvas.elements.firstIndex(where: { $0.id == elementId }) else {
            return
        }
        
        var updatedCanvas = canvas
        updatedCanvas.elements[elementIndex].location = position
        
        // Update in database
        canvasService.updateElement(updatedCanvas.elements[elementIndex], in: canvas.id)
        currentCanvas = updatedCanvas
    }
    
    /// Remove element from canvas
    func removeElement(elementId: String) {
        guard let canvas = currentCanvas else { return }
        
        canvasService.removeElement(elementId: elementId, from: canvas.id)
        
        var updatedCanvas = canvas
        updatedCanvas.elements.removeAll { $0.id == elementId }
        currentCanvas = updatedCanvas
        
        // Trigger UI updates for canvas contact changes
        objectWillChange.send()
    }
    
    /// Get all contact elements from current canvas
    var contactElements: [CanvasElement] {
        guard let canvas = currentCanvas else { return [] }
        return canvas.elements.filter { $0.elementType == .contact }
    }
    
    /// Get all group elements from current canvas
    var groupElements: [CanvasElement] {
        guard let canvas = currentCanvas else { return [] }
        return canvas.elements.filter { $0.elementType == .group }
    }
    
    /// Get phone numbers of all contacts currently in the canvas
    var canvasContactPhones: Set<String> {
        guard let canvas = currentCanvas else { return Set() }
        return Set(canvas.elements.compactMap { element in
            if element.elementType == .contact {
                // The element ID is the phone number for contact elements
                return element.id
            }
            return nil
        })
    }
    
    // MARK: - Private Methods
    
    // MARK: - Canvas Management
    
    func loadAvailableCanvases() {
        availableCanvases = canvasRepository.getGroupMapCanvasesOrdered()
    }
    
    func loadDefaultCanvas() {
        // Try to load the last edited canvas first
        if let lastEditedCanvas = canvasRepository.getLastEditedCanvas(type: .groupMap) {
            setCurrentCanvas(lastEditedCanvas)
            print("GlobalCanvasService: Loaded last edited canvas '\(lastEditedCanvas.name)'")
        } else {
            // Create a default canvas if none exists
            var defaultCanvasState = CanvasState(gridEnabled: true)
            defaultCanvasState.mode = .select // Ensure default mode is selection
            let defaultCanvas = Canvas(
                name: "Default Canvas",
                canvasType: .groupMap,
                canvasState: defaultCanvasState
            )
            setCurrentCanvas(defaultCanvas)
            print("GlobalCanvasService: Created default canvas")
        }
    }
    
    func loadCanvas(id: String) {
        if let canvas = canvasRepository.getCanvas(id: id) {
            setCurrentCanvas(canvas)
            print("GlobalCanvasService: Loaded canvas '\(canvas.name)'")
        }
    }
    
    func toggleCanvasFavorite(canvasId: String) {
        if canvasRepository.toggleCanvasFavorite(canvasId: canvasId) {
            // Reload available canvases to reflect the change
            loadAvailableCanvases()
        }
    }
    
    func saveCurrentCanvas() {
        guard let canvas = currentCanvas else { return }
        
        var updatedCanvas = canvas
        updatedCanvas.dateUpdated = Date()
        
        if canvasRepository.updateCanvas(updatedCanvas) {
            currentCanvas = updatedCanvas
            print("GlobalCanvasService: Saved current canvas '\(canvas.name)'")
        }
    }
    
    private func setupBindings() {
        // Monitor canvas service updates
        canvasService.$isUpdating
            .sink { _ in
                // Handle loading state if needed
            }
            .store(in: &cancellables)
        
        canvasService.$lastUpdateError
            .compactMap { $0 }
            .sink { error in
                print("Canvas service error: \(error)")
            }
            .store(in: &cancellables)
    }
}
