import SwiftUI
import Foundation

/// Simple, reliable drag manager for canvas elements
@MainActor
class CanvasDragManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isDragging: Bool = false
    @Published var draggedElements: Set<UUID> = []
    
    // MARK: - Private Properties
    private var dragStartPosition: CGPoint = .zero
    private var originalPositions: [UUID: CGPoint] = [:]
    private var draggedElementTypes: [UUID: ElementType] = [:]
    
    // MARK: - Element Type
    enum ElementType {
        case contact
        case group
    }
    
    // MARK: - Drag Operations
    
    /// Start dragging elements
    func startDrag(
        elementIds: Set<UUID>,
        elementTypes: [UUID: ElementType],
        startPosition: CGPoint,
        originalPositions: [UUID: CGPoint],
        viewModel: GroupsMapViewModel? = nil
    ) {
        print("🎯 DragManager: Starting drag for \(elementIds.count) elements")
        
        self.draggedElements = elementIds
        self.draggedElementTypes = elementTypes
        self.dragStartPosition = startPosition
        self.originalPositions = originalPositions
        self.isDragging = true
        
        // Synchronize drag state with view model
        viewModel?.startDragging()
    }
    
    /// Update drag position
    func updateDrag(currentPosition: CGPoint, zoom: CGFloat) -> [UUID: CGPoint] {
        guard isDragging else { return [:] }
        
        // Calculate drag offset in view coordinates
        let viewOffset = CGPoint(
            x: currentPosition.x - dragStartPosition.x,
            y: currentPosition.y - dragStartPosition.y
        )
        
        // Convert to canvas coordinates by dividing by zoom
        let canvasOffset = CGPoint(
            x: viewOffset.x / zoom,
            y: viewOffset.y / zoom
        )
        
        // Calculate new positions for all dragged elements
        var newPositions: [UUID: CGPoint] = [:]
        
        for elementId in draggedElements {
            if let originalPosition = originalPositions[elementId] {
                let newPosition = CGPoint(
                    x: originalPosition.x + canvasOffset.x,
                    y: originalPosition.y + canvasOffset.y
                )
                newPositions[elementId] = newPosition
            }
        }
        
        return newPositions
    }
    
    /// End drag operation
    func endDrag(viewModel: GroupsMapViewModel? = nil) -> [UUID: CGPoint]? {
        guard isDragging else { return nil }
        
        print("🎯 DragManager: Ending drag for \(draggedElements.count) elements")
        
        // Get the current positions from the view model instead of original positions
        // This ensures we return the final dragged positions, not the original ones
        var finalPositions: [UUID: CGPoint] = [:]
        
        // Get current positions from view model
        if let viewModel = viewModel {
            for elementId in draggedElements {
                if let elementType = draggedElementTypes[elementId] {
                    switch elementType {
                    case .contact:
                        if let contact = viewModel.contacts.first(where: { $0.id == elementId }) {
                            finalPositions[elementId] = contact.position
                        }
                    case .group:
                        if let group = viewModel.groups.first(where: { $0.id == elementId }) {
                            finalPositions[elementId] = group.center
                        }
                    }
                }
            }
        }
        
        // Reset state
        isDragging = false
        draggedElements.removeAll()
        draggedElementTypes.removeAll()
        originalPositions.removeAll()
        
        // Synchronize drag state with view model
        viewModel?.endDragging()
        
        return finalPositions
    }
    
    /// Cancel drag operation
    func cancelDrag(viewModel: GroupsMapViewModel? = nil) {
        print("🎯 DragManager: Canceling drag")
        
        isDragging = false
        draggedElements.removeAll()
        draggedElementTypes.removeAll()
        originalPositions.removeAll()
        
        // Synchronize drag state with view model
        viewModel?.endDragging()
    }
    
    // MARK: - Helper Methods
    
    /// Get element type for a given ID
    func getElementType(for elementId: UUID) -> ElementType? {
        return draggedElementTypes[elementId]
    }
    
    /// Check if an element is being dragged
    func isElementDragged(_ elementId: UUID) -> Bool {
        return draggedElements.contains(elementId)
    }
}
