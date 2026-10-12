import SwiftUI
import AppKit

// MARK: - Canvas Gesture Coordinator

class CanvasGestureCoordinator: NSObject, ObservableObject {
    @Published var isPanning = false
    @Published var isZooming = false
    @Published var isMarqueeSelecting = false
    @Published var marqueeRect: CGRect?
    
    private var lastPanLocation: CGPoint?
    private var lastZoomScale: CGFloat = 1.0
    private var marqueeStartPoint: CGPoint?
    private var marqueeModifierFlags: NSEvent.ModifierFlags = []
    
    weak var viewModel: GroupsMapViewModel?
    
    init(viewModel: GroupsMapViewModel) {
        self.viewModel = viewModel
        super.init()
    }
    
    // MARK: - Coordinate Conversion
    
    @MainActor
    private func viewToCanvas(_ point: CGPoint, viewSize: CGSize) -> CGPoint {
        guard let viewModel = viewModel else { return point }
        let transform = CanvasTransform(zoom: viewModel.canvasState.zoom, pan: viewModel.canvasState.pan)
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
    
    // MARK: - Pan Gesture
    @MainActor
    func handlePanGesture(_ value: DragGesture.Value, in viewSize: CGSize) {
        guard let viewModel = viewModel else { return }
        
        if isPanning {
            let currentLocation = value.location
            guard let lastLocation = lastPanLocation else {
                // If we don't have a last location, use the start location
                lastPanLocation = value.startLocation
                return
            }
            
            // FIXED: Calculate pan delta directly from view coordinates
            let panDelta = CGPoint(
                x: currentLocation.x - lastLocation.x,
                y: currentLocation.y - lastLocation.y
            )
            
            #if DEBUG
            print("🔧 CanvasGestures: handlePanGesture - currentLocation: \(currentLocation), lastLocation: \(lastLocation)")
            print("🔧 CanvasGestures: handlePanGesture - panDelta: \(panDelta), zoom: \(viewModel.canvasState.zoom)")
            #endif
            
            // Apply the pan delta to move the canvas view
            viewModel.panBy(panDelta, viewSize: viewSize)
            lastPanLocation = currentLocation
        } else {
            isPanning = true
            lastPanLocation = value.startLocation
        }
    }
    
    func endPanGesture() {
        isPanning = false
        lastPanLocation = nil
    }
    
    // MARK: - Zoom Gesture
    @MainActor
    func handleZoomGesture(_ scale: CGFloat, at location: CGPoint, in viewSize: CGSize) {
        guard let viewModel = viewModel else { return }
        
        let zoomDelta = scale / lastZoomScale
        let newZoom = viewModel.canvasState.zoom * zoomDelta
        
        // Zoom from the pinch location instead of always from center
        let pinchLocation = location
        viewModel.setZoom(newZoom, viewSize: viewSize, anchorInView: pinchLocation)
        
        lastZoomScale = scale
        isZooming = true
    }
    
    func endZoomGesture() {
        isZooming = false
        lastZoomScale = 1.0
    }
    
    // MARK: - Marquee Selection
    func startMarqueeSelection(at point: CGPoint) {
        print("🔧 CanvasGestures: Starting marquee selection at \(point)")
        marqueeStartPoint = point
        isMarqueeSelecting = true
        marqueeRect = CGRect(origin: point, size: .zero)
        marqueeModifierFlags = NSEvent.modifierFlags
    }
    
    func updateMarqueeSelection(to point: CGPoint) {
        guard let startPoint = marqueeStartPoint else { return }
        
        let rect = CGRect(
            x: min(startPoint.x, point.x),
            y: min(startPoint.y, point.y),
            width: abs(point.x - startPoint.x),
            height: abs(point.y - startPoint.y)
        )
        
        marqueeRect = rect
        print("🔧 CanvasGestures: Updating marquee selection to \(point), rect: \(rect)")
    }
    
    @MainActor
    func endMarqueeSelection(viewSize: CGSize) {
        guard let rect = marqueeRect, let _ = viewModel else {
            isMarqueeSelecting = false
            marqueeRect = nil
            marqueeStartPoint = nil
            return
        }
        
        // Convert marquee rect to canvas space and select items
        // Convert the rect corners to canvas coordinates
        let topLeft = viewToCanvas(rect.origin, viewSize: viewSize)
        let bottomRight = viewToCanvas(CGPoint(x: rect.maxX, y: rect.maxY), viewSize: viewSize)
        let canvasRect = CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
        
        selectItemsInMarquee(canvasRect)
        
        isMarqueeSelecting = false
        marqueeRect = nil
        marqueeStartPoint = nil
    }
    
    @MainActor
    private func selectItemsInMarquee(_ canvasRect: CGRect) {
        guard let viewModel = viewModel else { return }
        
        var selectedItems: Set<UUID> = []
        
        // Select contacts in marquee
        for contact in viewModel.contacts {
            let contactRect = CGRect(
                x: contact.position.x - contact.size.width / 2,
                y: contact.position.y - contact.size.height / 2,
                width: contact.size.width,
                height: contact.size.height
            )
            
            if canvasRect.intersects(contactRect) {
                selectedItems.insert(contact.id)
            }
        }
        
        // Select groups in marquee
        for group in viewModel.groups {
            let groupRect = CGRect(
                x: group.center.x - group.radius,
                y: group.center.y - group.radius,
                width: group.radius * 2,
                height: group.radius * 2
            )
            
            if canvasRect.intersects(groupRect) {
                selectedItems.insert(group.id)
            }
        }
        
        // Update selection based on modifier keys captured at start of marquee
        if marqueeModifierFlags.contains(.shift) || marqueeModifierFlags.contains(.command) {
            // Toggle mode: add or remove items from selection
            let contactIds = Set(viewModel.contacts.map { $0.id })
            let groupIds = Set(viewModel.groups.map { $0.id })
            
            let marqueeContactIds = selectedItems.intersection(contactIds)
            let marqueeGroupIds = selectedItems.intersection(groupIds)
            
            // Toggle contacts: add if not selected, remove if selected
            for contactId in marqueeContactIds {
                if viewModel.selectedContacts.contains(contactId) {
                    viewModel.selectedContacts.remove(contactId)
                } else {
                    viewModel.selectedContacts.insert(contactId)
                }
            }
            
            // Toggle groups: add if not selected, remove if selected
            for groupId in marqueeGroupIds {
                if viewModel.selectedGroups.contains(groupId) {
                    viewModel.selectedGroups.remove(groupId)
                } else {
                    viewModel.selectedGroups.insert(groupId)
                }
            }
        } else if marqueeModifierFlags.contains(.option) {
            // Subtract from existing selection
            viewModel.selectedContacts.subtract(selectedItems.intersection(Set(viewModel.contacts.map { $0.id })))
            viewModel.selectedGroups.subtract(selectedItems.intersection(Set(viewModel.groups.map { $0.id })))
        } else {
            // Replace selection
            viewModel.selectedContacts = selectedItems.intersection(Set(viewModel.contacts.map { $0.id }))
            viewModel.selectedGroups = selectedItems.intersection(Set(viewModel.groups.map { $0.id }))
        }
        
        viewModel.updateStateFromSelection()
    }
    
    // MARK: - Keyboard Shortcuts
    // Note: Keyboard handling is now managed by HotkeyManager to avoid conflicts
    // This ensures proper separation between app-level and canvas-level hotkeys
    
    // Note: Keyboard handling methods have been moved to HotkeyManager
    // to ensure proper separation between app-level and canvas-level hotkeys
}

// MARK: - Notification Names

extension Notification.Name {
    static let toggleNavigation = Notification.Name("toggleNavigation")
}

// MARK: - Edge Scrolling

class EdgeScrollingManager: ObservableObject {
    @Published var isEdgeScrolling = false
    @Published var scrollDirection: CGPoint = .zero
    
    private let edgeThreshold: CGFloat = 50
    private let maxScrollSpeed: CGFloat = 20
    private var lastScrollTime: Date = Date()
    private let scrollInterval: TimeInterval = 1.0 / 30.0 // 30fps
    
    func updateEdgeScrolling(for location: CGPoint, in viewSize: CGSize, canvasSize: CGSize, currentPan: CGPoint) {
        // Only activate edge scrolling when dragging items
        let edgeDistance = min(
            min(location.x, viewSize.width - location.x),
            min(location.y, viewSize.height - location.y)
        )
        
        if edgeDistance < edgeThreshold {
            isEdgeScrolling = true
            
            // Calculate scroll direction and speed
            var direction = CGPoint.zero
            
            // All four edges can scroll
            if location.x < edgeThreshold {
                direction.x = -1
            } else if location.x > viewSize.width - edgeThreshold {
                direction.x = 1
            }
            
            if location.y < edgeThreshold {
                direction.y = -1
            } else if location.y > viewSize.height - edgeThreshold {
                direction.y = 1
            }
            
            // Linear speed calculation based on proximity to edge
            let speedMultiplier = (edgeThreshold - edgeDistance) / edgeThreshold
            let rawScrollSpeed = CGPoint(
                x: direction.x * maxScrollSpeed * speedMultiplier,
                y: direction.y * maxScrollSpeed * speedMultiplier
            )
            
            // Apply bounds checking - limit to 3x current canvas size
            let maxPanX = canvasSize.width * 2 // Allow panning 2x canvas width in each direction
            let maxPanY = canvasSize.height * 2 // Allow panning 2x canvas height in each direction
            
            let boundedScrollSpeed = CGPoint(
                x: applyBoundsToScroll(rawScrollSpeed.x, currentPan.x, maxPanX),
                y: applyBoundsToScroll(rawScrollSpeed.y, currentPan.y, maxPanY)
            )
            
            // Apply smoothing with 30fps throttling
            let now = Date()
            if now.timeIntervalSince(lastScrollTime) >= scrollInterval {
                scrollDirection = boundedScrollSpeed
                lastScrollTime = now
            }
        } else {
            isEdgeScrolling = false
            scrollDirection = .zero
        }
    }
    
    private func applyBoundsToScroll(_ scrollSpeed: CGFloat, _ currentPan: CGFloat, _ maxPan: CGFloat) -> CGFloat {
        // If we're at the bounds, reduce or stop scrolling
        if abs(currentPan) >= maxPan {
            // If we're at the boundary and trying to scroll further, stop
            if (currentPan > 0 && scrollSpeed > 0) || (currentPan < 0 && scrollSpeed < 0) {
                return 0
            }
            // If we're scrolling back toward center, allow it but reduce speed
            return scrollSpeed * 0.5
        }
        
        // If scrolling would exceed bounds, reduce speed
        if abs(currentPan + scrollSpeed) > maxPan {
            let remainingDistance = maxPan - abs(currentPan)
            return scrollSpeed > 0 ? remainingDistance : -remainingDistance
        }
        
        return scrollSpeed
    }
    
    func stopEdgeScrolling() {
        isEdgeScrolling = false
        scrollDirection = .zero
    }
}
