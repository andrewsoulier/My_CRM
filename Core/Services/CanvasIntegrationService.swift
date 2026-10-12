import SwiftUI
import Combine

@MainActor
class CanvasIntegrationService: ObservableObject {
    // MARK: - Published Properties
    @Published var currentCanvas: Canvas?
    @Published var isCanvasLoaded = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Services
    private let canvasService = CanvasUpdateService()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Canvas State
    private var currentCanvasId: String?
    
    init() {
        setupBindings()
    }
    
    // MARK: - Public Methods
    
    /// Load or create a canvas for the current group map
    func loadCanvasForGroupMap(mapId: UUID) {
        let canvasId = mapId.uuidString
        currentCanvasId = canvasId
        
        // Try to load existing canvas
        if let existingCanvas = canvasService.loadCanvas(id: canvasId) {
            currentCanvas = existingCanvas
            isCanvasLoaded = true
            print("✅ Loaded existing canvas: \(canvasId)")
        } else {
            // Create new canvas for this group map with the specific ID
            if let newCanvas = canvasService.createCanvas(name: "Group Map Canvas", type: .groupMap) {
                // Update the canvas ID to match our expected format
                var updatedCanvas = newCanvas
                updatedCanvas.id = canvasId
                
                // Save the canvas with the correct ID
                canvasService.saveCanvas(updatedCanvas)
                
                currentCanvas = updatedCanvas
                isCanvasLoaded = true
                print("✅ Created new canvas: \(canvasId)")
            } else {
                errorMessage = "Failed to create canvas"
                print("❌ Failed to create canvas: \(canvasId)")
            }
        }
    }
    
    /// Add a contact node to the current canvas
    func addContactNode(_ contact: Contact, at position: CGPoint) {
        guard let canvas = currentCanvas else {
            errorMessage = "No canvas loaded"
            return
        }
        
        let contactElement = CanvasElement(
            elementType: .contact,
            location: position,
            scale: 1.0,
            width: 60,
            height: 80,
            rotation: 0,
            color: "#007AFF"
        )
        
        // Add to canvas
        canvasService.addElement(contactElement, to: canvas.id)
        
        // Update local canvas state
        var updatedCanvas = canvas
        updatedCanvas.elements.append(contactElement)
        currentCanvas = updatedCanvas
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
    }
    
    /// Save current canvas state
    func saveCanvas() {
        guard let canvas = currentCanvas else { return }
        canvasService.saveCanvas(canvas)
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
    
    /// Convert CanvasElement to ContactNode for rendering
    func canvasElementToContactNode(_ element: CanvasElement, dataProvider: SQLiteDataProvider? = nil) -> ContactNode? {
        guard element.elementType == .contact else { return nil }
        
        return ContactNode.fromCanvasElement(element, dataProvider: dataProvider)
    }
    
    /// Convert CanvasElement to GroupCircle for rendering
    func canvasElementToGroupCircle(_ element: CanvasElement) -> GroupCircle? {
        guard element.elementType == .group else { return nil }
        
        return GroupCircle(
            id: UUID(uuidString: element.id) ?? UUID(),
            name: "Group", // This would need to be resolved from group data
            center: element.location,
            radius: element.width / 2,
            color: Color(hex: element.color) ?? .blue,
            rotation: element.rotation
        )
    }
    
    /// Convert ContactNode to CanvasElement for storage
    func contactNodeToCanvasElement(_ contactNode: ContactNode) -> CanvasElement {
        return CanvasElement(
            id: contactNode.phone, // Use phone number as element ID for database lookup
            elementType: .contact,
            location: contactNode.position,
            scale: 1.0,
            width: contactNode.size.width,
            height: contactNode.size.height,
            rotation: 0,
            color: "#007AFF"
        )
    }
    
    /// Convert GroupCircle to CanvasElement for storage
    func groupCircleToCanvasElement(_ groupCircle: GroupCircle) -> CanvasElement {
        return CanvasElement(
            id: groupCircle.id.uuidString,
            elementType: .group,
            location: groupCircle.center,
            scale: 1.0,
            width: groupCircle.radius * 2,
            height: groupCircle.radius * 2,
            rotation: groupCircle.rotation,
            color: groupCircle.color.toHexString()
        )
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Monitor canvas service updates
        canvasService.$isUpdating
            .assign(to: \.isLoading, on: self)
            .store(in: &cancellables)
        
        canvasService.$lastUpdateError
            .compactMap { $0 }
            .assign(to: \.errorMessage, on: self)
            .store(in: &cancellables)
    }
}

// MARK: - Extensions
// Color extensions are now defined in CanvasModels.swift
