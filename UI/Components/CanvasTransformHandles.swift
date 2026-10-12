import SwiftUI

/// Canvas-level transform handles that render independently on top of everything
/// This ensures clean hit-testing without gesture conflicts
struct CanvasTransformHandles: View {
    let group: GroupCircle
    let zoom: CGFloat
    let pan: CGPoint
    let viewSize: CGSize
    let onResize: (CGFloat, CGFloat, CGPoint) -> Void  // width, height, newCenter
    let onRotate: (CGFloat) -> Void
    let onCommit: () -> Void  // Called on drag end to save to database
    
    @Binding var isHandleDragging: Bool
    @State private var dragStartGroupWidth: CGFloat = 0
    @State private var dragStartGroupHeight: CGFloat = 0
    @State private var dragStartGroupRotation: CGFloat = 0  // Lock rotation at drag start!
    @State private var dragStartMousePosition: CGPoint = .zero
    @State private var dragStartAnchorPosition: CGPoint = .zero
    @State private var dragStartGroupCenter: CGPoint = .zero
    @State private var initialDistanceX: CGFloat = 0
    @State private var initialDistanceY: CGFloat = 0
    @State private var activeHandle: TransformHandleType? = nil
    @State private var frameCounter: Int = 0  // Throttle updates for smoother performance
    @State private var lastWidth: CGFloat = 0
    @State private var lastHeight: CGFloat = 0
    @State private var lastCenter: CGPoint = .zero
    
    private let handleSize: CGFloat = 30
    private let handleOffset: CGFloat = 12
    private let rotationHandleOffset: CGFloat = 30  // 5px higher than before (was 25)
    
    // Rotation sensitivity factor - adjust how responsive rotation is to mouse movement
    private let rotationSensitivity: CGFloat = 0.005
    
    var body: some View {
        ZStack {
            // Edge handles
            createHandle(at: .left, color: group.color)
            createHandle(at: .right, color: group.color)
            createHandle(at: .top, color: group.color)
            createHandle(at: .bottom, color: group.color)
            
            // Corner handles
            createHandle(at: .topLeft, color: group.color)
            createHandle(at: .topRight, color: group.color)
            createHandle(at: .bottomLeft, color: group.color)
            createHandle(at: .bottomRight, color: group.color)
            
            // Rotation handle
            createHandle(at: .rotation, color: group.color)
        }
    }
    
    @ViewBuilder
    private func createHandle(at type: TransformHandleType, color: Color) -> some View {
        // During drag: Use the CURRENT group position for handles
        // This creates smooth visual feedback as the group updates
        // But we calculate where the handle SHOULD be based on current group dimensions
        let handlePosition = calculateHandlePosition(for: type)
        
        HandleView(
            type: type,
            color: color,
            onDragStart: { viewPosition in
                handleDragStart(type: type, startPosition: viewPosition)
            },
            onDrag: { viewPosition in
                handleDrag(type: type, currentPosition: viewPosition)
            },
            onDragEnd: {
                handleDragEnd()
            }
        )
        .position(x: handlePosition.x, y: handlePosition.y)
    }
    
    /// Calculate canvas position for a handle based on group position and type
    private func calculateHandlePosition(for type: TransformHandleType) -> CGPoint {
        // Calculate handle offset from group center (in group's local space, canvas coordinates)
        let localOffset: CGPoint
        switch type {
        case .left:
            localOffset = CGPoint(x: -group.width / 2 - handleOffset, y: 0)
        case .right:
            localOffset = CGPoint(x: group.width / 2 + handleOffset, y: 0)
        case .top:
            localOffset = CGPoint(x: 0, y: group.height / 2 + handleOffset)  // Top in canvas = positive Y
        case .bottom:
            localOffset = CGPoint(x: 0, y: -group.height / 2 - handleOffset)  // Bottom in canvas = negative Y
        case .topLeft:
            localOffset = CGPoint(x: -group.width / 2 - handleOffset, y: group.height / 2 + handleOffset)
        case .topRight:
            localOffset = CGPoint(x: group.width / 2 + handleOffset, y: group.height / 2 + handleOffset)
        case .bottomLeft:
            localOffset = CGPoint(x: -group.width / 2 - handleOffset, y: -group.height / 2 - handleOffset)
        case .bottomRight:
            localOffset = CGPoint(x: group.width / 2 + handleOffset, y: -group.height / 2 - handleOffset)
        case .rotation:
            localOffset = CGPoint(x: 0, y: group.height / 2 + rotationHandleOffset)  // Above in canvas = positive Y
        }
        
        // Apply rotation to offset (if group is rotated)
        let cos = cos(group.rotation)
        let sin = sin(group.rotation)
        let rotatedOffset = CGPoint(
            x: localOffset.x * cos - localOffset.y * sin,
            y: localOffset.x * sin + localOffset.y * cos
        )
        
        // Add rotated offset to group center (in canvas coordinates)
        let handleCanvasPosition = CGPoint(
            x: group.center.x + rotatedOffset.x,
            y: group.center.y + rotatedOffset.y
        )
        
        // Convert to view coordinates using the same method as other views
        let handleViewPosition = canvasToView(handleCanvasPosition)
        
        // Debug logging removed for performance
        
        return handleViewPosition
    }
    
    /// Convert canvas coordinates to view coordinates (matching SimplifiedCanvasView pattern)
    private func canvasToView(_ point: CGPoint) -> CGPoint {
        let transform = CanvasTransform(zoom: zoom, pan: pan)
        // Convert bottom-left canvas coordinates to top-left view coordinates
        let topLeftCanvasPoint = CGPoint(x: point.x, y: -point.y)
        let topLeftViewPoint = transform.canvasToView(topLeftCanvasPoint)
        // Convert to bottom-left view coordinates for SwiftUI
        return CGPoint(
            x: topLeftViewPoint.x,
            y: viewSize.height - topLeftViewPoint.y
        )
    }
    
    /// Convert view coordinates to canvas coordinates (matching SimplifiedCanvasView pattern)
    private func viewToCanvas(_ point: CGPoint) -> CGPoint {
        let transform = CanvasTransform(zoom: zoom, pan: pan)
        // Convert bottom-left view coordinates to top-left for the transform
        let topLeftViewPoint = CGPoint(
            x: point.x,
            y: viewSize.height - point.y
        )
        let topLeftCanvasPoint = transform.viewToCanvas(topLeftViewPoint)
        // Convert top-left canvas back to bottom-left
        return CGPoint(x: topLeftCanvasPoint.x, y: -topLeftCanvasPoint.y)
    }
    
    /// Get the anchor point (opposite corner/edge) that should stay fixed
    /// When dragging TL, BR should be the anchor (stay fixed)
    /// Returns point in WORLD coordinates, accounting for rotation
    private func getAnchorPoint(for handleType: TransformHandleType) -> CGPoint {
        // Get the local (unrotated) offset from center to anchor
        var localOffset: CGPoint
        
        switch handleType {
        case .topLeft:
            // Dragging TL → BR stays fixed (+width/2, -height/2 in local space)
            localOffset = CGPoint(x: group.width / 2, y: -group.height / 2)
        case .topRight:
            // Dragging TR → BL stays fixed (-width/2, -height/2 in local space)
            localOffset = CGPoint(x: -group.width / 2, y: -group.height / 2)
        case .bottomLeft:
            // Dragging BL → TR stays fixed (+width/2, +height/2 in local space)
            localOffset = CGPoint(x: group.width / 2, y: group.height / 2)
        case .bottomRight:
            // Dragging BR → TL stays fixed (-width/2, +height/2 in local space)
            localOffset = CGPoint(x: -group.width / 2, y: group.height / 2)
        case .top:
            // Dragging T → B stays fixed (0, -height/2 in local space)
            localOffset = CGPoint(x: 0, y: -group.height / 2)
        case .bottom:
            // Dragging B → T stays fixed (0, +height/2 in local space)
            localOffset = CGPoint(x: 0, y: group.height / 2)
        case .left:
            // Dragging L → R stays fixed (+width/2, 0 in local space)
            localOffset = CGPoint(x: group.width / 2, y: 0)
        case .right:
            // Dragging R → L stays fixed (-width/2, 0 in local space)
            localOffset = CGPoint(x: -group.width / 2, y: 0)
        case .rotation:
            return group.center
        }
        
        // Rotate the offset by group's rotation to get world space offset
        let cos = cos(group.rotation)
        let sin = sin(group.rotation)
        let rotatedOffset = CGPoint(
            x: localOffset.x * cos - localOffset.y * sin,
            y: localOffset.x * sin + localOffset.y * cos
        )
        
        // World position = center + rotatedOffset
        return CGPoint(
            x: group.center.x + rotatedOffset.x,
            y: group.center.y + rotatedOffset.y
        )
    }
    
    /// Get the handle position at the group edge (not including offset)
    /// Returns point in WORLD coordinates, accounting for rotation
    private func getHandleEdgePoint(for handleType: TransformHandleType) -> CGPoint {
        // Get the local (unrotated) offset from center to handle edge
        var localOffset: CGPoint
        
        switch handleType {
        case .topLeft:
            localOffset = CGPoint(x: -group.width / 2, y: group.height / 2)
        case .topRight:
            localOffset = CGPoint(x: group.width / 2, y: group.height / 2)
        case .bottomLeft:
            localOffset = CGPoint(x: -group.width / 2, y: -group.height / 2)
        case .bottomRight:
            localOffset = CGPoint(x: group.width / 2, y: -group.height / 2)
        case .top:
            localOffset = CGPoint(x: 0, y: group.height / 2)
        case .bottom:
            localOffset = CGPoint(x: 0, y: -group.height / 2)
        case .left:
            localOffset = CGPoint(x: -group.width / 2, y: 0)
        case .right:
            localOffset = CGPoint(x: group.width / 2, y: 0)
        case .rotation:
            localOffset = CGPoint(x: 0, y: group.height / 2)
        }
        
        // Rotate the offset by group's rotation to get world space offset
        let cos = cos(group.rotation)
        let sin = sin(group.rotation)
        let rotatedOffset = CGPoint(
            x: localOffset.x * cos - localOffset.y * sin,
            y: localOffset.x * sin + localOffset.y * cos
        )
        
        // World position = center + rotatedOffset
        return CGPoint(
            x: group.center.x + rotatedOffset.x,
            y: group.center.y + rotatedOffset.y
        )
    }
    
    /// Handle drag start - record initial state
    private func handleDragStart(type: TransformHandleType, startPosition: CGPoint) {
        LogManager.shared.info("🔧🔧🔧 ==== DRAG START: \(type) ====")
        LogManager.shared.info("🔧 StartPosition from gesture: \(startPosition)")
        LogManager.shared.info("🔧 Group.center (canvas coords): \(group.center)")
        LogManager.shared.info("🔧 Group: w=\(group.width), h=\(group.height), rot=\(group.rotation * 180 / .pi)°")
        
        activeHandle = type
        isHandleDragging = true
        dragStartGroupWidth = group.width
        dragStartGroupHeight = group.height
        dragStartGroupCenter = group.center  // ONE-TIME LOOKUP: Lock center at drag start
        dragStartGroupRotation = group.rotation  // LOCK rotation at start!
        
        // CRITICAL: coordinateSpace: .named("canvas") means startPosition is in VIEW coordinates
        // NOT canvas coordinates - it's the view coordinate space of the ZStack named "canvas"
        dragStartMousePosition = viewToCanvas(startPosition)
        LogManager.shared.info("🔧 Gesture pos (view): \(startPosition) → Canvas: \(dragStartMousePosition)")
        
        // Calculate anchor point using LOCKED values (not live group object!)
        // Get the local (unrotated) offset from center to anchor
        var localOffset: CGPoint
        
        switch type {
        case .topLeft:
            localOffset = CGPoint(x: dragStartGroupWidth / 2, y: -dragStartGroupHeight / 2)
        case .topRight:
            localOffset = CGPoint(x: -dragStartGroupWidth / 2, y: -dragStartGroupHeight / 2)
        case .bottomLeft:
            localOffset = CGPoint(x: dragStartGroupWidth / 2, y: dragStartGroupHeight / 2)
        case .bottomRight:
            localOffset = CGPoint(x: -dragStartGroupWidth / 2, y: dragStartGroupHeight / 2)
        case .top:
            localOffset = CGPoint(x: 0, y: -dragStartGroupHeight / 2)
        case .bottom:
            localOffset = CGPoint(x: 0, y: dragStartGroupHeight / 2)
        case .left:
            localOffset = CGPoint(x: dragStartGroupWidth / 2, y: 0)
        case .right:
            localOffset = CGPoint(x: -dragStartGroupWidth / 2, y: 0)
        case .rotation:
            localOffset = .zero
        }
        
        // Rotate the offset by LOCKED rotation
        let cos = cos(dragStartGroupRotation)
        let sin = sin(dragStartGroupRotation)
        let rotatedOffset = CGPoint(
            x: localOffset.x * cos - localOffset.y * sin,
            y: localOffset.x * sin + localOffset.y * cos
        )
        
        // Anchor position in world space using LOCKED values
        dragStartAnchorPosition = CGPoint(
            x: dragStartGroupCenter.x + rotatedOffset.x,
            y: dragStartGroupCenter.y + rotatedOffset.y
        )
        
        // Calculate handle edge position using LOCKED values
        var handleLocalOffset: CGPoint
        
        switch type {
        case .topLeft:
            handleLocalOffset = CGPoint(x: -dragStartGroupWidth / 2, y: dragStartGroupHeight / 2)
        case .topRight:
            handleLocalOffset = CGPoint(x: dragStartGroupWidth / 2, y: dragStartGroupHeight / 2)
        case .bottomLeft:
            handleLocalOffset = CGPoint(x: -dragStartGroupWidth / 2, y: -dragStartGroupHeight / 2)
        case .bottomRight:
            handleLocalOffset = CGPoint(x: dragStartGroupWidth / 2, y: -dragStartGroupHeight / 2)
        case .top:
            handleLocalOffset = CGPoint(x: 0, y: dragStartGroupHeight / 2)
        case .bottom:
            handleLocalOffset = CGPoint(x: 0, y: -dragStartGroupHeight / 2)
        case .left:
            handleLocalOffset = CGPoint(x: -dragStartGroupWidth / 2, y: 0)
        case .right:
            handleLocalOffset = CGPoint(x: dragStartGroupWidth / 2, y: 0)
        case .rotation:
            handleLocalOffset = .zero
        }
        
        // Rotate by LOCKED rotation
        let handleRotatedOffset = CGPoint(
            x: handleLocalOffset.x * cos - handleLocalOffset.y * sin,
            y: handleLocalOffset.x * sin + handleLocalOffset.y * cos
        )
        
        let dragStartHandleEdge = CGPoint(
            x: dragStartGroupCenter.x + handleRotatedOffset.x,
            y: dragStartGroupCenter.y + handleRotatedOffset.y
        )
        
        // CRITICAL: Initial distance from HANDLE EDGE to ANCHOR (full dimension)
        initialDistanceX = dragStartAnchorPosition.x - dragStartHandleEdge.x
        initialDistanceY = dragStartAnchorPosition.y - dragStartHandleEdge.y
        
        // For rotation handle, just log the setup
        if type == .rotation {
            LogManager.shared.info("🔧 Rotation setup:")
            LogManager.shared.info("  Mouse start (canvas): \(dragStartMousePosition)")
            LogManager.shared.info("  Current group rotation: \(dragStartGroupRotation) radians (\(dragStartGroupRotation * 180 / .pi)°)")
        }
        
        LogManager.shared.info("🔧 LOCKED values: w=\(dragStartGroupWidth), h=\(dragStartGroupHeight), rot=\(dragStartGroupRotation * 180 / .pi)°")
        LogManager.shared.info("🔧🔧🔧 ============================")
    }
    
    /// Handle drag update - calculate scale based on distance ratio
    private func handleDrag(type: TransformHandleType, currentPosition: CGPoint) {
        guard isHandleDragging, type == activeHandle else { return }
        
        // Convert current mouse position to canvas coordinates
        let currentMouseCanvas = viewToCanvas(currentPosition)
        
        // Handle rotation separately - simple X delta based rotation
        if type == .rotation {
            // Calculate mouse X delta in canvas coordinates
            let mouseDeltaX = currentMouseCanvas.x - dragStartMousePosition.x
            
            // Apply rotation based on horizontal mouse movement
            // Positive X movement = clockwise rotation
            let rotationDelta = mouseDeltaX * rotationSensitivity
            let newRotation = dragStartGroupRotation + rotationDelta
            
            LogManager.shared.info("🔧 ROT: currentPos(view)=\(currentPosition) → canvas=\(currentMouseCanvas)")
            LogManager.shared.info("🔧 ROT: mouseDeltaX=\(mouseDeltaX) px")
            LogManager.shared.info("🔧 ROT: rotationDelta=\(rotationDelta) rad (\(rotationDelta * 180 / .pi)°)")
            LogManager.shared.info("🔧 ROT: startRotation=\(dragStartGroupRotation) rad (\(dragStartGroupRotation * 180 / .pi)°)")
            LogManager.shared.info("🔧 ROT: newRotation=\(newRotation) rad (\(newRotation * 180 / .pi)°)")
            
            onRotate(newRotation)
            return
        }
        
        // Calculate mouse offset from drag start
        let mouseDeltaX = currentMouseCanvas.x - dragStartMousePosition.x
        let mouseDeltaY = currentMouseCanvas.y - dragStartMousePosition.y
        
        // Calculate implied new handle edge position (if handle edge moved with mouse delta)
        // We need to get the initial handle edge position first
        var handleLocalOffset: CGPoint
        switch type {
        case .topLeft:
            handleLocalOffset = CGPoint(x: -dragStartGroupWidth / 2, y: dragStartGroupHeight / 2)
        case .topRight:
            handleLocalOffset = CGPoint(x: dragStartGroupWidth / 2, y: dragStartGroupHeight / 2)
        case .bottomLeft:
            handleLocalOffset = CGPoint(x: -dragStartGroupWidth / 2, y: -dragStartGroupHeight / 2)
        case .bottomRight:
            handleLocalOffset = CGPoint(x: dragStartGroupWidth / 2, y: -dragStartGroupHeight / 2)
        case .top:
            handleLocalOffset = CGPoint(x: 0, y: dragStartGroupHeight / 2)
        case .bottom:
            handleLocalOffset = CGPoint(x: 0, y: -dragStartGroupHeight / 2)
        case .left:
            handleLocalOffset = CGPoint(x: -dragStartGroupWidth / 2, y: 0)
        case .right:
            handleLocalOffset = CGPoint(x: dragStartGroupWidth / 2, y: 0)
        case .rotation:
            handleLocalOffset = .zero
        }
        
        let cosAngle = cos(dragStartGroupRotation)
        let sinAngle = sin(dragStartGroupRotation)
        let handleRotatedOffset = CGPoint(
            x: handleLocalOffset.x * cosAngle - handleLocalOffset.y * sinAngle,
            y: handleLocalOffset.x * sinAngle + handleLocalOffset.y * cosAngle
        )
        
        let originalHandleEdge = CGPoint(
            x: dragStartGroupCenter.x + handleRotatedOffset.x,
            y: dragStartGroupCenter.y + handleRotatedOffset.y
        )
        
        // New handle edge = original + mouse delta
        let newHandleEdgeX = originalHandleEdge.x + mouseDeltaX
        let newHandleEdgeY = originalHandleEdge.y + mouseDeltaY
        
        // Calculate current distance from NEW HANDLE EDGE to anchor
        let currentDistanceX = dragStartAnchorPosition.x - newHandleEdgeX
        let currentDistanceY = dragStartAnchorPosition.y - newHandleEdgeY
        
        // Calculate scale factors (signed, avoid division by zero)
        let scaleX = abs(initialDistanceX) > 0.1 ? currentDistanceX / initialDistanceX : 1.0
        let scaleY = abs(initialDistanceY) > 0.1 ? currentDistanceY / initialDistanceY : 1.0
        
        // Reduced logging for performance
        // print("🔧 Scale: X=\(scaleX), Y=\(scaleY)")
        
        // Apply scale based on handle type
        var newWidth = dragStartGroupWidth
        var newHeight = dragStartGroupHeight
        
        switch type {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            // Corner handles scale both X and Y independently
            newWidth = dragStartGroupWidth * abs(scaleX)
            newHeight = dragStartGroupHeight * abs(scaleY)
        case .left, .right:
            // Side handles scale only X (width), keep height
            newWidth = dragStartGroupWidth * abs(scaleX)
            newHeight = dragStartGroupHeight
        case .top, .bottom:
            // Top/bottom handles scale only Y (height), keep width
            newWidth = dragStartGroupWidth
            newHeight = dragStartGroupHeight * abs(scaleY)
        case .rotation:
            return // Already handled above
        }
        
        // Enforce minimum size
        newWidth = max(newWidth, 20)
        newHeight = max(newHeight, 20)
        
        // Calculate new center to keep anchor point fixed
        // The anchor point stays at dragStartAnchorPosition (in world space)
        // We need to account for rotation when calculating the offset
        
        // Get the offset from center to anchor in local (unrotated) space
        var localOffset = CGPoint.zero
        
        switch type {
        case .topLeft:
            // Dragging TL → BR (anchor) stays fixed
            // BR is at (+width/2, -height/2) in local space
            localOffset = CGPoint(x: newWidth / 2, y: -newHeight / 2)
        case .topRight:
            // Dragging TR → BL (anchor) stays fixed
            // BL is at (-width/2, -height/2) in local space
            localOffset = CGPoint(x: -newWidth / 2, y: -newHeight / 2)
        case .bottomLeft:
            // Dragging BL → TR (anchor) stays fixed
            // TR is at (+width/2, +height/2) in local space
            localOffset = CGPoint(x: newWidth / 2, y: newHeight / 2)
        case .bottomRight:
            // Dragging BR → TL (anchor) stays fixed
            // TL is at (-width/2, +height/2) in local space
            localOffset = CGPoint(x: -newWidth / 2, y: newHeight / 2)
        case .left:
            // Dragging L → R (anchor) stays fixed - only X
            // R is at (+width/2, 0) in local space
            localOffset = CGPoint(x: newWidth / 2, y: 0)
        case .right:
            // Dragging R → L (anchor) stays fixed - only X
            // L is at (-width/2, 0) in local space
            localOffset = CGPoint(x: -newWidth / 2, y: 0)
        case .top:
            // Dragging T → B (anchor) stays fixed - only Y
            // B is at (0, -height/2) in local space
            localOffset = CGPoint(x: 0, y: -newHeight / 2)
        case .bottom:
            // Dragging B → T (anchor) stays fixed - only Y
            // T is at (0, +height/2) in local space
            localOffset = CGPoint(x: 0, y: newHeight / 2)
        case .rotation:
            return // Already handled
        }
        
        // Rotate the offset by the LOCKED rotation (from drag start) to get world space offset
        let cosR = cos(dragStartGroupRotation)
        let sinR = sin(dragStartGroupRotation)
        let rotatedOffset = CGPoint(
            x: localOffset.x * cosR - localOffset.y * sinR,
            y: localOffset.x * sinR + localOffset.y * cosR
        )
        
        // New center = anchor - rotatedOffset
        let newCenter = CGPoint(
            x: dragStartAnchorPosition.x - rotatedOffset.x,
            y: dragStartAnchorPosition.y - rotatedOffset.y
        )
        
        // Store last calculated values
        lastWidth = newWidth
        lastHeight = newHeight
        lastCenter = newCenter
        
        // Update on every frame for smoothest feedback
        onResize(newWidth, newHeight, newCenter)
    }
    
    /// Handle drag end - reset state and commit to database
    private func handleDragEnd() {
        print("🔧 CanvasTransformHandles: Drag END - ensuring final update and committing to database")
        
        // Ensure final values are applied (in case last frame was skipped)
        if lastWidth > 0 && lastHeight > 0 {
            onResize(lastWidth, lastHeight, lastCenter)
        }
        
        // Commit changes to database (expensive operations deferred until now)
        onCommit()
        
        isHandleDragging = false
        activeHandle = nil
        frameCounter = 0
    }
}

/// Individual handle view that can be dragged
private struct HandleView: View {
    let type: TransformHandleType
    let color: Color
    let onDragStart: (CGPoint) -> Void
    let onDrag: (CGPoint) -> Void
    let onDragEnd: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Actual handle (no debug circle - removed for clarity)
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 12, height: 12)
                
                // Larger invisible hit area
                Circle()
                    .fill(Color.clear)
                    .frame(width: 30, height: 30)
                
                // Rotation handle indicator
                if type == .rotation {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 6))
                        .foregroundColor(.white)
                }
                
                // Debug label (disabled)
                // Text(handleLabel(for: type))
                //     .font(.system(size: 10, weight: .bold))
                //     .foregroundColor(.yellow)
                //     .offset(y: -20)
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if value.translation == .zero {
                            onDragStart(value.location)
                        }
                        onDrag(value.location)
                    }
                    .onEnded { value in
                        onDragEnd()
                    }
            )
        }
        .frame(width: 30, height: 30)
    }
    
    private func handleLabel(for type: TransformHandleType) -> String {
        switch type {
        case .topLeft: return "TL"
        case .top: return "T"
        case .topRight: return "TR"
        case .left: return "L"
        case .right: return "R"
        case .bottomLeft: return "BL"
        case .bottom: return "B"
        case .bottomRight: return "BR"
        case .rotation: return "r"
        }
    }
}

