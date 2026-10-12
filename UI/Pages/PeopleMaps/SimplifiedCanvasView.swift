import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Combine

struct SimplifiedCanvasView: View {
    @ObservedObject var viewModel: GroupsMapViewModel
    @ObservedObject var gestureCoordinator: CanvasGestureCoordinator
    @ObservedObject var edgeScrollingManager: EdgeScrollingManager
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @StateObject private var dragManager = CanvasDragManager()
    
    @State private var viewSize: CGSize = .zero
    @State private var edgeScrollTimer: Timer?
    @State private var scrollWheelMonitor: Any?
    @State private var mouseDownMonitor: Any?
    @State private var capturedModifierFlags: NSEvent.ModifierFlags = []
    @State private var isClickAndDragMode = false
    @State private var clickAndDragStartPosition: CGPoint = .zero
    
    // Marquee selection delay tracking
    @State private var marqueeDelayTimer: Timer?
    @State private var pendingMarqueeStartPoint: CGPoint?
    
    // Additional state from GroupsMapCanvas
    @State private var showingGroupQuickMenu = false
    @State private var quickMenuPosition: CGPoint = .zero
    @State private var overlappingGroups: [GroupCircle] = []
    @State private var isCreatingGroup = false
    @State private var groupCreationStart: CGPoint = .zero
    @State private var showingZoomFeedback = false
    @State private var canvasMouseLocation: CGPoint = .zero
    @State private var mouseTrackingTimer: Timer?
    @State private var isClickingOnEmptySpace: Bool = false
    @State private var isHandleDragging: Bool = false
    
    init(viewModel: GroupsMapViewModel, gestureCoordinator: CanvasGestureCoordinator, edgeScrollingManager: EdgeScrollingManager) {
        self.viewModel = viewModel
        self.gestureCoordinator = gestureCoordinator
        self.edgeScrollingManager = edgeScrollingManager
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Canvas background and grid
                CanvasBackground(
                    gridEnabled: viewModel.canvasState.gridEnabled,
                    gridSize: viewModel.canvasState.gridSize,
                    zoom: viewModel.canvasState.zoom,
                    pan: viewModel.canvasState.pan
                )
                
                // Canvas content (groups and contacts)
                CanvasContent(
                    viewModel: viewModel,
                    gestureCoordinator: gestureCoordinator,
                    dragManager: dragManager,
                    viewSize: geometry.size,
                    showingGroupQuickMenu: showingGroupQuickMenu,
                    overlappingGroups: overlappingGroups,
                    quickMenuPosition: quickMenuPosition,
                    showingZoomFeedback: showingZoomFeedback,
                    isCreatingGroup: isCreatingGroup,
                    isClickingOnEmptySpace: isClickingOnEmptySpace,
                    isHandleDragging: $isHandleDragging,
                    onGroupTap: handleGroupTap,
                    onContactTap: handleContactTap,
                    onGroupQuickMenuSelect: { groupId in
                        viewModel.toggleGroupSelection(groupId)
                    },
                    onAddNewGroup: addNewGroup,
                    onGroupCreationDrag: { _ in }, // DISABLED: Buggy group creation drag removed
                    onEndGroupCreation: endGroupCreation,
                    onGroupResize: { groupId, newSize in
                        print("🔧 SimplifiedCanvasView: onGroupResize called for group \(groupId) with size: \(newSize)")
                        viewModel.resizeGroup(groupId, width: newSize, height: newSize)
                    },
                    onGroupRotate: { groupId, angle in
                        viewModel.rotateGroup(groupId, by: angle)
                    },
                    onCanvasTap: { location in
                        if showingGroupQuickMenu {
                            showingGroupQuickMenu = false
                        }
                    },
                    calculateLeftUIWidth: calculateLeftUIWidth
                )
                
                // Marquee selection overlay
                if let marqueeRect = gestureCoordinator.marqueeRect {
                    MarqueeSelection(rect: marqueeRect)
                        .zIndex(100)
                }
                
                // NEW SIMPLE MOUSE TRACKING OVERLAY
                if viewModel.debugSettings.showDebugPoints {
                    SimpleMouseTracker(
                        zoom: viewModel.canvasState.zoom,
                        pan: viewModel.canvasState.pan,
                        viewSize: geometry.size
                    )
                    .zIndex(5) // Above groups and contacts but below UI overlays
                    .allowsHitTesting(false) // CRITICAL: Don't intercept mouse events
                    .onAppear {
                        print("🔍 Simple mouse tracker appeared")
                    }
                }
                
                // Debug diagnostics overlay (only show if debug points enabled)
                if viewModel.debugSettings.showDebugPoints {
                    let leftUIWidth = calculateLeftUIWidth()
                    let menuBarHeight = getMenuBarHeight()
                    
                    DebugDiagnosticsOverlay(
                        viewModel: viewModel,
                        viewSize: geometry.size,
                        leftUIWidth: leftUIWidth,
                        menuBarHeight: menuBarHeight
                    )
                    .zIndex(6) // Above coordinate points overlay
                    .allowsHitTesting(false) // CRITICAL: Don't intercept mouse events
                    .onAppear {
                        print("🔧 Debug diagnostics overlay appeared")
                        print("🔧 Debug Window Setup:")
                        print("  - AppState available: \(viewModel.appState != nil)")
                        print("  - Left UI width: \(leftUIWidth)")
                        print("  - Menu bar height: \(menuBarHeight)")
                    }
                }
                
                // Group quick menu (for overlapping groups)
                if showingGroupQuickMenu {
                    GroupQuickMenu(
                        groups: overlappingGroups,
                        position: quickMenuPosition,
                        onSelect: { groupId in
                            viewModel.toggleGroupSelection(groupId)
                            showingGroupQuickMenu = false
                        },
                        onDismiss: {
                            showingGroupQuickMenu = false
                        }
                    )
                    .zIndex(200) // Above everything else
                }
                
                // Group add mode indicator
                if viewModel.isGroupAddMode {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                Text("Click to add group")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.9))
                            )
                            .padding()
                        }
                    }
                    .zIndex(150) // Above canvas content but below quick menu
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .allowsHitTesting(true)
            .simultaneousGesture(
                // Pan gesture (ONLY in hand mode, NEVER in selection mode)
                DragGesture(minimumDistance: 10) // Increased minimum distance to avoid conflicts
                    .onChanged { value in
                        // STRICT: Only handle pan gestures when in hand mode AND NOT in selection mode
                        if viewModel.isHandMode && !viewModel.isSelectionMode {
                            // Only handle if the gesture starts within the canvas content area
                            if value.startLocation.y > 80 && value.startLocation.x > 0 {
                                handleCanvasPan(value)
                            }
                        }
                    }
                    .onEnded { _ in
                        if viewModel.isHandMode && !viewModel.isSelectionMode {
                            endCanvasGesture()
                        }
                    }
            )
            .simultaneousGesture(
                // Selection gesture (ONLY in selection mode, NEVER in hand mode)
                // Marquee selection works everywhere except on handles
                DragGesture(minimumDistance: 5) // Increased minimum distance to avoid conflicts
                    .onChanged { value in
                        print("🟣 Canvas selection gesture .onChanged triggered at \(value.location)")
                        // STRICT: Only handle selection gestures when in selection mode AND NOT in hand mode
                        if viewModel.isSelectionMode && !viewModel.isHandMode && !viewModel.isDragging && !isHandleDragging {
                            // Only handle if the gesture starts within the canvas content area
                            if value.startLocation.y > 80 && value.startLocation.x > 0 {
                                // Convert view coordinates to canvas coordinates for proper hit testing
                                let canvasStartPoint = viewToCanvas(value.startLocation)
                                
                                // Check if we're clicking on empty space (not on a contact or group)
                                let hasContactAtPoint = viewModel.contacts.contains { contact in
                                    let contactRect = CGRect(
                                        x: contact.position.x - contact.size.width / 2,
                                        y: contact.position.y - contact.size.height / 2,
                                        width: contact.size.width,
                                        height: contact.size.height
                                    )
                                    return contactRect.contains(canvasStartPoint)
                                }
                                
                                let hasGroupAtPoint = viewModel.groups.contains { group in
                                    let groupRect = CGRect(
                                        x: group.center.x - group.radius,
                                        y: group.center.y - group.radius,
                                        width: group.radius * 2,
                                        height: group.radius * 2
                                    )
                                    return groupRect.contains(canvasStartPoint)
                                }
                                
                                // Check if we're clicking on transform handles
                                let hasTransformHandleAtPoint = viewModel.shouldShowTransformHandles && viewModel.groups.contains { group in
                                    let handleOffset: CGFloat = 12
                                    let rotationHandleOffset: CGFloat = 30  // Match CanvasTransformHandles
                                    let handleSize: CGFloat = 30
                                    
                                    // Get rotation angle for rotated handle positions
                                    let cos = cos(group.rotation)
                                    let sin = sin(group.rotation)
                                    
                                    // Helper to rotate offset and get world position
                                    func rotatedHandlePosition(localX: CGFloat, localY: CGFloat) -> CGPoint {
                                        let rotatedX = localX * cos - localY * sin
                                        let rotatedY = localX * sin + localY * cos
                                        return CGPoint(
                                            x: group.center.x + rotatedX,
                                            y: group.center.y + rotatedY
                                        )
                                    }
                                    
                                    // Check all transform handle positions (including corners and rotation)
                                    let handlePositions = [
                                        // Edge handles
                                        rotatedHandlePosition(localX: -group.width / 2 - handleOffset, localY: 0),  // Left
                                        rotatedHandlePosition(localX: group.width / 2 + handleOffset, localY: 0),   // Right
                                        rotatedHandlePosition(localX: 0, localY: group.height / 2 + handleOffset),  // Top
                                        rotatedHandlePosition(localX: 0, localY: -group.height / 2 - handleOffset), // Bottom
                                        // Corner handles
                                        rotatedHandlePosition(localX: -group.width / 2 - handleOffset, localY: group.height / 2 + handleOffset),  // Top-left
                                        rotatedHandlePosition(localX: group.width / 2 + handleOffset, localY: group.height / 2 + handleOffset),   // Top-right
                                        rotatedHandlePosition(localX: -group.width / 2 - handleOffset, localY: -group.height / 2 - handleOffset), // Bottom-left
                                        rotatedHandlePosition(localX: group.width / 2 + handleOffset, localY: -group.height / 2 - handleOffset),  // Bottom-right
                                        // Rotation handle
                                        rotatedHandlePosition(localX: 0, localY: group.height / 2 + rotationHandleOffset)  // Rotation (above top)
                                    ]
                                    
                                    return handlePositions.contains { handlePos in
                                        let handleRect = CGRect(
                                            x: handlePos.x - handleSize / 2,
                                            y: handlePos.y - handleSize / 2,
                                            width: handleSize,
                                            height: handleSize
                                        )
                                        return handleRect.contains(canvasStartPoint)
                                    }
                                }
                                
                                // CRITICAL: If clicking on a transform handle, don't start marquee - let handle process it
                                if hasTransformHandleAtPoint {
                                    print("🔴🔴🔴 Canvas gesture detected HANDLE CLICK at canvas point \(canvasStartPoint) - SKIPPING marquee")
                                    return
                                }
                                
                                print("🟣 Canvas gesture checks: hasContact=\(hasContactAtPoint), hasGroup=\(hasGroupAtPoint), hasHandle=\(hasTransformHandleAtPoint)")
                                
                                // Only start marquee selection if clicking on empty space (not on contacts, groups, or transform handles)
                                if !hasContactAtPoint && !hasGroupAtPoint {
                                    // Start immediate marquee selection for testing
                                    if !gestureCoordinator.isMarqueeSelecting {
                                        print("🔧 Starting immediate marquee selection at \(value.startLocation)")
                                        gestureCoordinator.startMarqueeSelection(at: value.startLocation)
                                    } else {
                                        print("🔧 Updating marquee selection to \(value.location)")
                                        gestureCoordinator.updateMarqueeSelection(to: value.location)
                                    }
                                } else {
                                    print("🔧 SimplifiedCanvasView: Clicked on contact, group, or transform handle, not starting marquee selection")
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        // Cancel any pending delayed marquee selection
                        cancelDelayedMarqueeSelection()
                        
                        if viewModel.isSelectionMode && !viewModel.isHandMode {
                            if gestureCoordinator.isMarqueeSelecting {
                                print("🔧 Ending marquee selection")
                                gestureCoordinator.endMarqueeSelection(viewSize: viewSize)
                            }
                            endCanvasGesture()
                        }
                    }
            )
            .simultaneousGesture(
                // Pinch to zoom (works in all modes)
                MagnificationGesture()
                    .onChanged { scale in
                        handlePinchZoom(scale)
                    }
                    .onEnded { _ in
                        gestureCoordinator.endZoomGesture()
                    }
            )
            .onTapGesture(coordinateSpace: .local) { location in
                let canvasPoint = viewToCanvas(location)
                
                // Check if tap is on a contact
                let hasContactAtPoint = viewModel.contacts.contains { contact in
                    let contactRect = CGRect(
                        x: contact.position.x - contact.size.width / 2,
                        y: contact.position.y - contact.size.height / 2,
                        width: contact.size.width,
                        height: contact.size.height
                    )
                    return contactRect.contains(canvasPoint)
                }
                
                // Check if tap is on a group
                let hasGroupAtPoint = viewModel.groups.contains { group in
                    let distance = canvasPoint.distance(to: group.center)
                    return distance <= group.radius
                }
                
                // Check if we're clicking on transform handles
                let hasTransformHandleAtPoint = viewModel.shouldShowTransformHandles && viewModel.groups.contains { group in
                    let handleOffset: CGFloat = 12
                    let handleSize: CGFloat = 30 // Increased to match debug size
                    
                    // Check all four transform handle positions
                    let handles = [
                        // Left handle
                        CGRect(x: group.center.x - group.width / 2 - handleOffset - handleSize / 2, 
                              y: group.center.y - handleSize / 2, 
                              width: handleSize, height: handleSize),
                        // Right handle  
                        CGRect(x: group.center.x + group.width / 2 + handleOffset - handleSize / 2,
                              y: group.center.y - handleSize / 2,
                              width: handleSize, height: handleSize),
                        // Top handle
                        CGRect(x: group.center.x - handleSize / 2,
                              y: group.center.y - group.height / 2 - handleOffset - handleSize / 2,
                              width: handleSize, height: handleSize),
                        // Bottom handle
                        CGRect(x: group.center.x - handleSize / 2,
                              y: group.center.y + group.height / 2 + handleOffset - handleSize / 2,
                              width: handleSize, height: handleSize)
                    ]
                    
                    return handles.contains { handleRect in
                        handleRect.contains(canvasPoint)
                    }
                }
                
                // CRITICAL: If clicking on a transform handle, don't consume the event - let it pass to the handle
                if hasTransformHandleAtPoint {
                    print("🔴🔴🔴 Canvas TAP detected HANDLE CLICK at canvas point \(canvasPoint) - passing through to handle")
                    return
                }
                
                print("🟣 Canvas TAP checks: hasContact=\(hasContactAtPoint), hasGroup=\(hasGroupAtPoint), hasHandle=\(hasTransformHandleAtPoint)")
                
                // Handle canvas tap based on mode and location
                if !hasContactAtPoint && !hasGroupAtPoint {
                    if viewModel.isSelectionMode && !NSEvent.modifierFlags.contains(.shift) && !NSEvent.modifierFlags.contains(.command) {
                        // In selection mode: clear all selections when clicking on blank space (but not with modifiers)
                        print("🔧 Canvas tap on blank space in selection mode - clearing all selections")
                        viewModel.clearSelection()
                    } else if (viewModel.isHandMode || viewModel.isGroupAddMode) && location.y > 80 {
                        // In hand mode or group add mode: handle canvas-specific actions
                        handleCanvasTap(at: location)
                    }
                }
            }
            .onAppear {
                viewSize = geometry.size
                setupScrollWheelMonitoring()
                setupMouseDownMonitoring()
                
                // Auto-load first canvas on first appearance
                autoLoadFirstCanvas()
                
                // Release search bar focus when canvas appears
                NotificationCenter.default.post(name: NSNotification.Name("UnfocusSearchBar"), object: nil)
            }
            .onChange(of: geometry.size) { oldSize, newSize in
                viewSize = newSize
            }
            .onDisappear {
                if let monitor = scrollWheelMonitor {
                    NSEvent.removeMonitor(monitor)
                    scrollWheelMonitor = nil
                }
                if let monitor = mouseDownMonitor {
                    NSEvent.removeMonitor(monitor)
                    mouseDownMonitor = nil
                }
                mouseTrackingTimer?.invalidate()
                mouseTrackingTimer = nil
            }


            // DISABLED: This onChange handler was causing infinite loops
            // .onChange(of: viewModel.canvasState.zoom) { _, newZoom in
            //     // Show zoom feedback
            //     showingZoomFeedback = true
            //     DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            //         showingZoomFeedback = false
            //     }
            // }
            .onChange(of: viewModel.isGroupAddMode) { _, isGroupAddMode in
                // Change cursor when in group add mode
                if isGroupAddMode {
                    NSCursor.crosshair.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .overlay(alignment: .top) {
            // Tools and menus rendered on top of canvas
            CanvasToolbar(
                viewModel: viewModel,
                gestureCoordinator: gestureCoordinator,
                viewSize: viewSize
            )
            .padding(.top, 16)
            .padding(.horizontal, 16)
            .zIndex(1000) // Ensure toolbar renders on top of everything
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleNavigation)) { _ in
            // Handle navigation toggle by posting to AppState
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("ToggleNavigationBars"), object: nil)
            }
        }
    }
    
    // MARK: - Coordinate Transformations (Bottom-Left System)
    
    private func canvasToView(_ point: CGPoint) -> CGPoint {
        let transform = CanvasTransform(zoom: viewModel.canvasState.zoom, pan: viewModel.canvasState.pan)
        // Convert bottom-left canvas coordinates to top-left view coordinates
        let topLeftCanvasPoint = CGPoint(x: point.x, y: -point.y)
        let topLeftViewPoint = transform.canvasToView(topLeftCanvasPoint)
        // Convert to bottom-left view coordinates
        return CGPoint(
            x: topLeftViewPoint.x,
            y: viewSize.height - topLeftViewPoint.y
        )
    }
    
    private func viewToCanvas(_ point: CGPoint) -> CGPoint {
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
    
    // MARK: - UI Width Calculations
    
    private func calculateLeftUIWidth() -> CGFloat {
        var totalWidth: CGFloat = 0
        
        // Get AppState to check UI element states
        if let appState = viewModel.appState {
            // Page Navigation Bar (far left)
            if appState.isPageNavBarVisible {
                totalWidth += 260 // Full width when visible
                print("🔍 PageNavBar: EXPANDED (+260px), Total: \(totalWidth)")
            } else {
                totalWidth += 40 // Collapsed width
                print("🔍 PageNavBar: COLLAPSED (+40px), Total: \(totalWidth)")
            }
            
            // Contacts Bar (left)
            if appState.isContactsBarVisible {
                totalWidth += 340 // Full width when visible
                print("🔍 ContactsBar: EXPANDED (+340px), Total: \(totalWidth)")
            } else {
                totalWidth += 40 // Collapsed width
                print("🔍 ContactsBar: COLLAPSED (+40px), Total: \(totalWidth)")
            }
            
            // No correction needed - collapsed UI elements still contribute to width
            let pageNavBarWidth = appState.isPageNavBarVisible ? 260 : 40
            let contactsBarWidth = appState.isContactsBarVisible ? 340 : 40
            print("🔍 Final calculation: PageNavBar (\(pageNavBarWidth)px) + ContactsBar (\(contactsBarWidth)px) = \(totalWidth)px")
        } else {
            // Default values when AppState is not available yet
            // Assume both UI elements are visible by default
            totalWidth += 260 // PageNavBar expanded
            totalWidth += 340 // ContactsBar expanded
            print("🔍 calculateLeftUIWidth: AppState is nil, using default values (PageNavBar: +260px, ContactsBar: +340px), Total: \(totalWidth)")
        }
        
        print("🔍 Final total left UI width: \(totalWidth)")
        return totalWidth
    }
    
    // MARK: - Left UI Offset Calculation (Positive value to add to canvas mouse X)
    
    private func calculateLeftUIOffset() -> CGFloat {
        // This returns a positive offset that should be added to the canvas mouse X value
        // to get a more accurate position
        let baseWidth = calculateLeftUIWidth()
        
        // The offset is the same as the base width since we want to add it to the X value
        let offset = baseWidth
        
        print("🔍 Left UI Offset: +\(offset)px (to be added to canvas mouse X)")
        return offset
    }
    
    private func getMenuBarHeight() -> CGFloat {
        // Get the main screen's frame
        let screenFrame = NSScreen.main?.frame ?? .zero
        
        // Get the visible frame (screen minus menu bar and dock)
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        
        // Calculate menu bar height as the difference
        let menuBarHeight = screenFrame.height - visibleFrame.height - (screenFrame.minY - visibleFrame.minY)
        
        print("🔍 Menu bar calculation:")
        print("  - Screen frame: \(screenFrame)")
        print("  - Visible frame: \(visibleFrame)")
        print("  - Calculated menu bar height: \(menuBarHeight)")
        
        return menuBarHeight
    }
    
    // MARK: - Gesture Handlers
    
    private func handleCanvasPan(_ value: DragGesture.Value) {
        // Only handle pan if it's not in the top toolbar area
        if value.startLocation.y > 80 {
            gestureCoordinator.handlePanGesture(value, in: viewSize)
        }
    }
    
    private func handleCanvasSelection(_ value: DragGesture.Value) {
        // Only handle selection if it's not in the top toolbar area
        if value.startLocation.y > 80 {
            if !gestureCoordinator.isMarqueeSelecting {
                gestureCoordinator.startMarqueeSelection(at: value.startLocation)
            }
            gestureCoordinator.updateMarqueeSelection(to: value.location)
        }
    }
    
    private func endCanvasGesture() {
        gestureCoordinator.endPanGesture()
        gestureCoordinator.endMarqueeSelection(viewSize: viewSize)
        edgeScrollingManager.stopEdgeScrolling()
    }
    
    private func handlePinchZoom(_ scale: CGFloat) {
        // Get the current mouse location for pinch center
        let mouseLocation = NSEvent.mouseLocation
        
        // Convert screen coordinates to view coordinates
        guard let window = NSApp.windows.first(where: { $0.isKeyWindow }) else {
            // Fallback to center if no window found
            let centerPoint = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
            gestureCoordinator.handleZoomGesture(scale, at: centerPoint, in: viewSize)
            return
        }
        
        let windowFrame = window.frame
        let totalLeftUIWidth = calculateLeftUIWidth()
        
        // Convert screen coordinates to view coordinates
        let windowPoint = CGPoint(
            x: mouseLocation.x - windowFrame.origin.x,
            y: mouseLocation.y - windowFrame.origin.y
        )
        
        // Use the same logic as mouse debug points for consistency
        let pinchLocation = CGPoint(
            x: windowPoint.x - totalLeftUIWidth,
            y: viewSize.height - windowPoint.y
        )
        
        gestureCoordinator.handleZoomGesture(scale, at: pinchLocation, in: viewSize)
    }
    
    // MARK: - Contact Interactions
    
    private func handleContactTap(_ contact: ContactNode) {
        print("🔧 handleContactTap called for contact: \(contact.name) (\(contact.id))")
        
        // Handle contact selection using the unified selection system
        // Use captured modifier flags from mouse down event
        let modifiers = capturedModifierFlags
        print("🔧 Using captured modifiers: \(modifiers)")
        handleUnifiedSelection(
            elementId: contact.id,
            elementType: .contact,
            modifiers: modifiers
        )
        
        // Enable click-and-drag mode for repositioning
        isClickAndDragMode = true
        clickAndDragStartPosition = contact.position
    }
    
    // Old drag handlers removed - using new drag system
    
    // MARK: - Group Interactions
    
    private func handleGroupTap(_ group: GroupCircle) {
        print("🔧 handleGroupTap called for group: \(group.name) (\(group.id))")
        
        // Handle group selection using the unified selection system
        // Use captured modifier flags from mouse down event
        let modifiers = capturedModifierFlags
        print("🔧 Using captured modifiers: \(modifiers)")
        handleUnifiedSelection(
            elementId: group.id,
            elementType: .group,
            modifiers: modifiers
        )
        
        // Enable click-and-drag mode for repositioning
        isClickAndDragMode = true
        clickAndDragStartPosition = group.center
    }
    
    // Old group drag handlers removed - using new drag system
    
    // MARK: - Unified Element Drag Handling
    
    
    // MARK: - Canvas Interactions
    
    private func handleCanvasTap(at location: CGPoint? = nil) {
        if !gestureCoordinator.isPanning && !gestureCoordinator.isMarqueeSelecting {
            // Hide quick menu if clicking away
            if showingGroupQuickMenu {
                showingGroupQuickMenu = false
                return
            }
            
            // Use provided location or default to center
            let tapPoint = location ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
            let canvasPoint = viewToCanvas(tapPoint)
            
            // Check if we're in group add mode
            if viewModel.isGroupAddMode {
                print("🔧 In group add mode - adding group at position: \(canvasPoint)")
                viewModel.addNewGroupAtPosition(canvasPoint)
                return
            }
            
            // Unified element selection logic
            handleUnifiedElementSelection(at: canvasPoint, tapPoint: tapPoint)
        }
    }
    
    // MARK: - Unified Selection Logic
    
    private func handleUnifiedElementSelection(at canvasPoint: CGPoint, tapPoint: CGPoint) {
        // Use captured modifier flags from mouse down event
        let modifiers = capturedModifierFlags
        
        // First check for contacts at tap location (contacts are on top)
        let overlappingContacts = viewModel.contacts.filter { contact in
            let contactRect = CGRect(
                x: contact.position.x - contact.size.width / 2,
                y: contact.position.y - contact.size.height / 2,
                width: contact.size.width,
                height: contact.size.height
            )
            return contactRect.contains(canvasPoint)
        }
        
        if !overlappingContacts.isEmpty {
            // Select the topmost contact (last in array since contacts are rendered in order)
            let topmostContact = overlappingContacts.last!
            print("🔧 Unified selection - contact hit: \(topmostContact.name) (\(topmostContact.id))")
            print("🔧 Unified selection - modifiers: \(modifiers)")
            
            handleUnifiedSelection(
                elementId: topmostContact.id,
                elementType: .contact,
                modifiers: modifiers
            )
            isClickingOnEmptySpace = false
            return
        }
        
        // If no contacts, check for overlapping groups at tap location
        let overlappingGroups = viewModel.groups.filter { group in
            let distance = canvasPoint.distance(to: group.center)
            return distance <= group.radius
        }
        
        if overlappingGroups.count > 1 {
            // Multiple groups overlapping - show quick menu
            self.overlappingGroups = overlappingGroups
            quickMenuPosition = tapPoint
            showingGroupQuickMenu = true
            isClickingOnEmptySpace = false
        } else if let singleGroup = overlappingGroups.first {
            // Single group hit - select it
            print("🔧 Unified selection - group hit: \(singleGroup.name) (\(singleGroup.id))")
            print("🔧 Unified selection - modifiers: \(modifiers)")
            
            handleUnifiedSelection(
                elementId: singleGroup.id,
                elementType: .group,
                modifiers: modifiers
            )
            isClickingOnEmptySpace = false
        } else {
            // Clicked on empty space - handle based on modifiers
            if modifiers.contains(.command) || modifiers.contains(.shift) {
                // Command+click or Shift+click on empty space: do nothing
                print("🔧 Unified selection - modifier click on empty space, doing nothing")
                isClickingOnEmptySpace = true
            } else {
                // Regular click on empty space: clear selection
                print("🔧 Unified selection - empty space clicked, clearing all selections")
                viewModel.clearSelection()
                isClickingOnEmptySpace = true
            }
        }
    }
    
    private func handleUnifiedSelection(elementId: UUID, elementType: CanvasElementType, modifiers: NSEvent.ModifierFlags) {
        print("🔧 handleUnifiedSelection - elementId: \(elementId), type: \(elementType), modifiers: \(modifiers)")
        
        if modifiers.contains(.command) {
            // Command+click: toggle selection
            print("🔧 Command+click: toggling selection")
            if elementType == .contact {
                viewModel.toggleContactSelection(elementId)
            } else {
                viewModel.toggleGroupSelection(elementId)
            }
        } else if modifiers.contains(.shift) {
            // Shift+click: toggle selection
            print("🔧 Shift+click: toggling selection")
            if elementType == .contact {
                viewModel.toggleContactSelection(elementId)
            } else {
                viewModel.toggleGroupSelection(elementId)
            }
        } else if modifiers.contains(.option) {
            // Option+click: add to selection (same as shift)
            print("🔧 Option+click: adding to selection")
            if elementType == .contact {
                viewModel.selectContact(elementId, addToSelection: true)
            } else {
                viewModel.selectGroup(elementId, addToSelection: true)
            }
        } else {
            // Regular click: single selection - clear all other selections and select only this element
            print("🔧 Regular click: selecting element and clearing all other selections")
            print("🔧 Before selection - Selected contacts: \(viewModel.selectedContacts.count), Selected groups: \(viewModel.selectedGroups.count)")
            
            // Clear all selections first
            viewModel.clearSelection()
            
            // Then select only this element
            if elementType == .contact {
                viewModel.selectContact(elementId, addToSelection: false)
            } else {
                viewModel.selectGroup(elementId, addToSelection: false)
            }
            
            print("🔧 After selection - Selected contacts: \(viewModel.selectedContacts.count), Selected groups: \(viewModel.selectedGroups.count)")
        }
        
        // Note: saveImmediately() removed as part of canvas saving optimization
        // Selection changes no longer trigger saves
    }
    
    // MARK: - New Drag System (implemented in CanvasContent)
    
    // MARK: - Helper Functions
    
    private func addNewGroup() {
        let canvasPoint = viewToCanvas(quickMenuPosition)
        viewModel.addNewGroupAtPosition(canvasPoint)
        isCreatingGroup = false
    }
    
    // REMOVED: handleGroupCreationDrag() - This function was buggy and called moveGroup() with canvas ID instead of group ID
    // Group creation should use the unified element movement system instead
    
    private func endGroupCreation() {
        isCreatingGroup = false
    }
    
    // MARK: - Delayed Marquee Selection
    
    private func startDelayedMarqueeSelection(at point: CGPoint) {
        print("🔧 Starting delayed marquee selection at \(point)")
        
        // Cancel any existing timer
        marqueeDelayTimer?.invalidate()
        
        // Store the start point
        pendingMarqueeStartPoint = point
        
        // Start a timer for the delay (0.3 seconds for long click behavior)
        marqueeDelayTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            DispatchQueue.main.async {
                self.activateMarqueeSelection()
            }
        }
        print("🔧 Marquee timer started - will activate in 0.3 seconds")
    }
    
    private func activateMarqueeSelection() {
        guard let startPoint = pendingMarqueeStartPoint else { return }
        
        // Check if we're still in selection mode and not dragging
        // Use dragManager.isDragging instead of viewModel.isDragging for accurate drag state
        guard viewModel.isSelectionMode && !dragManager.isDragging else {
            print("🔧 Marquee selection cancelled - no longer in selection mode or drag mode active")
            cancelDelayedMarqueeSelection()
            return
        }
        
        print("🔧 Activating marquee selection at \(startPoint)")
        
        // Check if shift is held for toggle mode
        let isToggleMode = NSEvent.modifierFlags.contains(.shift)
        
        // If not in toggle mode, clear existing selection first
        if !isToggleMode {
            print("🔧 SimplifiedCanvasView: Starting marquee selection (clearing existing selection)")
            viewModel.clearSelection()
        } else {
            print("🔧 SimplifiedCanvasView: Starting marquee selection (toggle mode)")
        }
        
        // Start the actual marquee selection
        gestureCoordinator.startMarqueeSelection(at: startPoint)
        
        // Clear the pending state
        pendingMarqueeStartPoint = nil
    }
    
    private func cancelDelayedMarqueeSelection() {
        print("🔧 Cancelling delayed marquee selection")
        marqueeDelayTimer?.invalidate()
        marqueeDelayTimer = nil
        pendingMarqueeStartPoint = nil
    }
    
    // MARK: - Keyboard Handling
    // Note: Keyboard handling is now managed by HotkeyManager to avoid conflicts
    // This ensures proper separation between app-level and canvas-level hotkeys
    
    // MARK: - Scroll Wheel Handling
    
    private func setupScrollWheelMonitoring() {
        // Use local monitor for scroll wheel events when app is focused
        // This captures scroll events sent to our app
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // Check if mouse is over the canvas view
            if self.isMouseOverCanvas(event: event) {
                self.handleScrollWheel(event)
                return nil // Consume the event to prevent default scrolling
            }
            return event // Pass through if not over canvas
        }
    }
    
    private func setupMouseDownMonitoring() {
        // Capture modifier flags at the moment of mouse down
        // This ensures we have the correct modifiers even if user releases them before tap handler runs
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            self.capturedModifierFlags = event.modifierFlags
            
            if self.isMouseOverCanvas(event: event) {
                self.hotkeyManager.disableNavHotkeys()
            }
            
            return event // Always pass through - we're just observing
        }
    }
    
    private func autoLoadFirstCanvas() {
        // Only auto-load if no canvas is currently loaded
        guard globalCanvasService.currentCanvas == nil else {
            print("🔧 Auto-load skipped: Canvas already loaded (\(globalCanvasService.currentCanvas?.name ?? "unknown"))")
            return
        }
        
        print("🔧 Auto-loading first canvas...")
        
        // Load available canvases asynchronously
        DispatchQueue.global(qos: .userInitiated).async {
            let repository = DatabaseCanvasRepository()
            let canvases = repository.getGroupMapCanvasesOrdered()
            
            DispatchQueue.main.async {
                if let firstCanvas = canvases.first {
                    print("🔧 Auto-loading first available canvas: \(firstCanvas.name) (ID: \(firstCanvas.id))")
                    self.globalCanvasService.setCurrentCanvas(firstCanvas)
                    // Refresh the global service's available canvases list
                    self.globalCanvasService.loadAvailableCanvases()
                } else {
                    print("🔧 No canvases found, creating default canvas...")
                    self.createDefaultCanvas()
                }
            }
        }
    }
    
    private func createDefaultCanvas() {
        let repository = DatabaseCanvasRepository()
        let defaultCanvas = Canvas(
            name: "default canvas",
            canvasType: .groupMap,
            canvasState: CanvasState(gridEnabled: true)
        )
        
        if repository.createCanvas(defaultCanvas) {
            print("🔧 Created default canvas: \(defaultCanvas.name) (ID: \(defaultCanvas.id))")
            globalCanvasService.setCurrentCanvas(defaultCanvas)
            // Refresh the global service's available canvases list
            globalCanvasService.loadAvailableCanvases()
        } else {
            print("❌ Failed to create default canvas")
        }
    }
    
    private func isMouseOverCanvas(event: NSEvent) -> Bool {
        // Get the mouse location in screen coordinates
        let mouseLocation = NSEvent.mouseLocation
        
        // Convert to window coordinates if we have a window
        guard let window = NSApp.keyWindow else { return false }
        
        // Convert screen coordinates to window coordinates
        let windowLocation = window.convertFromScreen(CGRect(origin: mouseLocation, size: .zero)).origin
        
        // Convert to view coordinates
        guard let contentView = window.contentView else { return false }
        let viewLocation = contentView.convert(windowLocation, from: nil)
        
        // Check if the mouse is over our canvas view
        // This is a simplified check - in a real implementation, you'd want to
        // get the actual bounds of the canvas view within the window
        return viewLocation.x >= 0 && viewLocation.y >= 0 && 
               viewLocation.x <= viewSize.width && viewLocation.y <= viewSize.height
    }
    
    private func handleScrollWheel(_ event: NSEvent) {
        let modifiers = event.modifierFlags
        let usePreciseDeltas = event.hasPreciseScrollingDeltas
        let rawDeltaX = usePreciseDeltas ? event.scrollingDeltaX : event.deltaX
        let rawDeltaY = usePreciseDeltas ? event.scrollingDeltaY : event.deltaY
        let deltaX = CGFloat(rawDeltaX)
        let deltaY = CGFloat(rawDeltaY)
        
        // Determine scroll behavior based on modifiers and current mode
        if modifiers.contains(.option) {
            // Option + scroll: zoom in/out from center (works in all modes)
            let zoomDelta = deltaY * 0.02 // Increased sensitivity for better control
            let newZoom = viewModel.canvasState.zoom * (1 + zoomDelta)
            viewModel.setZoom(newZoom, viewSize: viewSize)
            return
        }
        
        // Determine horizontal vs vertical scrolling
        var handledHorizontal = false
        var horizontalAmount: CGFloat = 0
        
        if modifiers.contains(.shift) {
            horizontalAmount = abs(deltaX) > CGFloat.ulpOfOne ? deltaX : deltaY
            handledHorizontal = abs(horizontalAmount) > CGFloat.ulpOfOne
        } else if abs(deltaX) > abs(deltaY) {
            horizontalAmount = deltaX
            handledHorizontal = abs(horizontalAmount) > CGFloat.ulpOfOne
        }
        
        if handledHorizontal {
            // Horizontal scroll (trackpad or shift+scroll)
            let panDelta = CGPoint(x: horizontalAmount * 2, y: 0)
            viewModel.panBy(panDelta, viewSize: viewSize)
        } else {
            // Regular scroll: pan up/down (works in all modes)
            let panDelta = CGPoint(x: 0, y: deltaY * 2)
            viewModel.panBy(panDelta, viewSize: viewSize)
        }
    }
    
    // MARK: - Edge Scrolling
    
    private func startEdgeScrollTimer() {
        edgeScrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            if self.edgeScrollingManager.isEdgeScrolling {
                self.applyEdgeScrolling()
            }
        }
    }
    
    private func stopEdgeScrollTimer() {
        edgeScrollTimer?.invalidate()
        edgeScrollTimer = nil
    }
    
    private func applyEdgeScrolling() {
        let scrollDelta = edgeScrollingManager.scrollDirection
        if scrollDelta != .zero {
            // Invert the scroll direction so the canvas follows the dragged item
            // When dragging right, canvas should pan left (negative)
            // When dragging left, canvas should pan right (positive)
            let invertedDelta = CGPoint(x: -scrollDelta.x, y: -scrollDelta.y)
            viewModel.panBy(invertedDelta, viewSize: viewSize)
        }
    }
    
    private func calculateCanvasSize() -> CGSize {
        let allPositions = viewModel.contacts.map { $0.position } + viewModel.groups.map { $0.center }
        
        guard !allPositions.isEmpty else {
            return viewSize
        }
        
        let minX = allPositions.map { $0.x }.min() ?? 0
        let maxX = allPositions.map { $0.x }.max() ?? 0
        let minY = allPositions.map { $0.y }.min() ?? 0
        let maxY = allPositions.map { $0.y }.max() ?? 0
        
        let padding: CGFloat = 200
        return CGSize(
            width: max(maxX - minX + padding, viewSize.width),
            height: max(maxY - minY + padding, viewSize.height)
        )
    }
}

// MARK: - Debug Diagnostics Overlay

struct DebugDiagnosticsOverlay: View {
    let viewModel: GroupsMapViewModel
    let viewSize: CGSize
    let leftUIWidth: CGFloat
    let menuBarHeight: CGFloat
    @State private var mouseLocation: CGPoint = .zero
    @State private var canvasMouseLocation: CGPoint = .zero
    @State private var timer: Timer?
    @State private var viewFrame: CGRect = .zero
    
    private var canvasBounds: CGRect {
        viewModel.getCanvasBounds()
    }
    
    private func viewToCanvas(_ point: CGPoint) -> CGPoint {
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
    
    private var canvasSizeText: String {
        "Canvas Size: \(Int(canvasBounds.width)) × \(Int(canvasBounds.height))"
    }
    
    private var canvasBoundsText: String {
        "Canvas Bounds: (\(Int(canvasBounds.minX)), \(Int(canvasBounds.minY))), (\(Int(canvasBounds.maxX)), \(Int(canvasBounds.maxY)))"
    }
    
    private var viewSizeText: String {
        "View Size: \(Int(viewSize.width)) × \(Int(viewSize.height))"
    }
    
    private var viewBoundsText: String {
        // Calculate what canvas coordinates are currently visible in the view
        // Convert view corners to canvas coordinates using proper coordinate conversion
        let topLeft = viewToCanvas(CGPoint(x: 0, y: 0))
        let topRight = viewToCanvas(CGPoint(x: viewSize.width, y: 0))
        let bottomLeft = viewToCanvas(CGPoint(x: 0, y: viewSize.height))
        let bottomRight = viewToCanvas(CGPoint(x: viewSize.width, y: viewSize.height))
        
        // Find the min/max visible canvas coordinates
        let minX = min(topLeft.x, topRight.x, bottomLeft.x, bottomRight.x)
        let maxX = max(topLeft.x, topRight.x, bottomLeft.x, bottomRight.x)
        let minY = min(topLeft.y, topRight.y, bottomLeft.y, bottomRight.y)
        let maxY = max(topLeft.y, topRight.y, bottomLeft.y, bottomRight.y)
        
        return "View Bounds: (\(Int(minX)), \(Int(minY))), (\(Int(maxX)), \(Int(maxY)))"
    }
    
    private var zoomText: String {
        "Zoom: \(String(format: "%.2f", viewModel.canvasState.zoom))"
    }
    
    private var minZoomText: String {
        let minZoom = max(0.01, 50.0 / min(viewSize.width, viewSize.height))
        return "Min Zoom: \(String(format: "%.2f", minZoom))"
    }
    
    private var maxZoomText: String {
        let maxZoom = min(10.0, min(viewSize.width, viewSize.height) / 50.0)
        return "Max Zoom: \(String(format: "%.2f", maxZoom))"
    }
    
    private var panOffsetText: String {
        "Pan Offset: X(\(Int(viewModel.canvasState.pan.x)), Y(\(Int(viewModel.canvasState.pan.y)))"
    }
    
    private var windowPositionText: String {
        // Get the actual window position dynamically
        if let window = NSApplication.shared.windows.first {
            let windowFrame = window.frame
            return "Window Position: X(\(Int(windowFrame.origin.x)), Y(\(Int(windowFrame.origin.y)))"
        } else {
            return "Window Position: Unknown"
        }
    }
    
    private var mousePositionText: String {
        return "Mouse Position: X(\(Int(mouseLocation.x)), Y(\(Int(mouseLocation.y)))"
    }
    
    private var canvasMousePositionText: String {
        return "Canvas Mouse: X(\(Int(canvasMouseLocation.x)), Y(\(Int(canvasMouseLocation.y)))"
    }
    
    
    private var leftUIWidthText: String {
        return "Left UI: \(Int(leftUIWidth))px"
    }
    
    private var leftUIOffsetText: String {
        return "Left UI Offset: +\(Int(leftUIWidth))px"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("🔧 Canvas Diagnostics")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.orange)
            
            Group {
                Text(canvasSizeText)
                Text(canvasBoundsText)
                Text(viewSizeText)
                Text(viewBoundsText)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white)
            
            Group {
                Text(zoomText)
                Text(minZoomText)
                Text(maxZoomText)
                Text(panOffsetText)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.cyan)
            
            Group {
                Text(windowPositionText)
                Text(mousePositionText)
                Text(canvasMousePositionText)
                Text(leftUIWidthText)
                Text(leftUIOffsetText)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.purple)
            
            Group {
                Text("Selected Groups: \(viewModel.selectedGroups.count)")
                Text("Selected Contacts: \(viewModel.selectedContacts.count)")
                Text("Total Groups: \(viewModel.groups.count)")
                Text("Total Contacts: \(viewModel.contacts.count)")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.yellow)
        }
        .padding(8)
        .overlayBackground()
        .cornerRadius(8)
        .offset(x: 150, y: 200) // Use offset to prevent clipping
        .onAppear {
            // Start timer to update mouse position
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in
                    mouseLocation = NSEvent.mouseLocation
                    // Use the same calculation as the main mouse tracking
                    let _ = CanvasTransform(zoom: viewModel.canvasState.zoom, pan: viewModel.canvasState.pan)
                    
                    // Get the main window and convert screen coordinates to view coordinates
                    if let window = NSApplication.shared.windows.first {
                        // Get the screen that contains the window for proper coordinate conversion
                        let windowScreen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
                        let screenFrame = windowScreen?.frame ?? .zero
                        
                        print("🔧 Debug Window: Screen info - Frame: \(screenFrame), Mouse: \(mouseLocation)")
                        
                        // Calculate mouse position in window coordinates
                        // Use window.convertPoint for more robust multi-monitor support
                        let windowPoint = window.convertPoint(fromScreen: mouseLocation)
                        
                        // Calculate mouse position in view coordinates (WITH UI adjustments)
                        // Use bottom-left coordinate system (0,0 at bottom-left, Y increases going up)
                        let viewPointWithUI = CGPoint(
                            x: windowPoint.x - leftUIWidth,
                            y: viewSize.height - windowPoint.y
                        )
                        
                        
                        // Update canvas mouse location with correct calculations
                        canvasMouseLocation = viewToCanvas(viewPointWithUI)
                        
                        print("🔧 Debug Window: Canvas Mouse (with UI): \(canvasMouseLocation)")
                        print("🔧 Debug Window: UI adjustments - Left: \(leftUIWidth), Menu: \(menuBarHeight)")
                    }
                }
            }
        }
        .onDisappear {
            // Clean up timer
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Marquee Selection

struct MarqueeSelection: View {
    let rect: CGRect
    
    var body: some View {
        Rectangle()
            .stroke(Color.blue, lineWidth: 2)
            .blueBackground()
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

// MARK: - Debug Coordinate Points Overlay

struct DebugCoordinatePointsOverlay: View {
    let zoom: CGFloat
    let pan: CGPoint
    let viewSize: CGSize
    let mousePosition: CGPoint? // Optional mouse position in canvas coordinates
    
    // Z-depth layers for different UI elements
    private let backgroundZ: Int = 1
    private let contactZ: Int = 2
    private let groupZ: Int = 3
    
    var body: some View {
        ZStack {
            // Background plane coordinates (grey) - Z=1
            ForEach(-3...4, id: \.self) { x in
                ForEach(-3...4, id: \.self) { y in
                    let point = CGPoint(x: CGFloat(x) * 100, y: CGFloat(-y) * 100)
                    ZStack {
                        // Visual dot
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 4, height: 4)
                        
                        // Coordinate text
                        Text("(\(Int(point.x)),\(Int(point.y)),\(backgroundZ))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                            .offset(x: 0, y: 12 + CGFloat(backgroundZ - 1) * 15)
                    }
                    .position(canvasToView(point))
                }
            }
            
            // Contact plane coordinates (blue) - Z=2
            ForEach(-3...4, id: \.self) { x in
                ForEach(-3...4, id: \.self) { y in
                    let point = CGPoint(x: CGFloat(x) * 100, y: CGFloat(-y) * 100)
                    ZStack {
                        // Visual dot
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 4, height: 4)
                        
                        // Coordinate text
                        Text("(\(Int(point.x)),\(Int(point.y)),\(contactZ))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.blue)
                            .offset(x: 0, y: 12 + CGFloat(contactZ - 1) * 15)
                    }
                    .position(canvasToView(point))
                }
            }
            
            // Group plane coordinates (green) - Z=3
            ForEach(-3...4, id: \.self) { x in
                ForEach(-3...4, id: \.self) { y in
                    let point = CGPoint(x: CGFloat(x) * 100, y: CGFloat(-y) * 100)
                    ZStack {
                        // Visual dot
                        Circle()
                            .fill(Color.green)
                            .frame(width: 4, height: 4)
                        
                        // Coordinate text
                        Text("(\(Int(point.x)),\(Int(point.y)),\(groupZ))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .offset(x: 0, y: 12 + CGFloat(groupZ - 1) * 15)
                    }
                    .position(canvasToView(point))
                }
            }
            
            // Mouse position text (red) - Z=4 (top layer)
            if let mousePos = mousePosition {
                Text("MOUSE(\(Int(mousePos.x)), \(Int(mousePos.y)), 4)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.red)
                    .semiTransparentBackground()
                    .cornerRadius(4)
                    .padding(4)
                    .position(canvasToView(mousePos).applying(CGAffineTransform(translationX: 0, y: 50)))
                    .onAppear {
                        print("🔍 Debug overlay: Mouse position received: \(mousePos)")
                    }
            } else {
                Text("NO MOUSE POSITION")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.red)
                    .semiTransparentBackground()
                    .cornerRadius(4)
                    .padding(4)
                    .position(x: 100, y: 100)
                    .onAppear {
                        print("🔍 Debug overlay: No mouse position received (nil)")
                    }
            }
        }
    }
    
    private func canvasToView(_ point: CGPoint) -> CGPoint {
        let transform = CanvasTransform(zoom: zoom, pan: pan)
        // Convert bottom-left canvas coordinates to top-left view coordinates
        let topLeftCanvasPoint = CGPoint(x: point.x, y: -point.y)
        let topLeftViewPoint = transform.canvasToView(topLeftCanvasPoint)
        // Convert to bottom-left view coordinates
        return CGPoint(
            x: topLeftViewPoint.x,
            y: viewSize.height - topLeftViewPoint.y
        )
    }
}

// MARK: - Grid Background

struct GridBackground: View {
    let gridSize: CGFloat
    let zoom: CGFloat
    let pan: CGPoint
    
    var body: some View {
        SwiftUI.Canvas { context, size in
            // Safety check: prevent division by zero or very small zoom values
            guard zoom > 0.001 else {
                print("⚠️ Warning: Invalid zoom value (\(zoom)) in grid drawing, skipping grid")
                return
            }
            
            
            let transform = CanvasTransform(zoom: zoom, pan: pan)
            let scaledGridSize = gridSize * zoom
            
            // Calculate grid bounds
            let startX = -pan.x / zoom
            let startY = -pan.y / zoom
            let endX = size.width / zoom
            let endY = size.height / zoom
            
            // Draw vertical lines
            var x = startX - startX.truncatingRemainder(dividingBy: scaledGridSize)
            while x <= endX {
                let canvasPoint = CGPoint(x: x, y: 0)
                let viewPoint = transform.canvasToView(canvasPoint)
                
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: viewPoint.x, y: 0))
                        path.addLine(to: CGPoint(x: viewPoint.x, y: size.height))
                    },
                    with: .color(.gray.opacity(0.3)),
                    lineWidth: 0.5
                )
                x += scaledGridSize
            }
            
            // Draw horizontal lines
            var y = startY - startY.truncatingRemainder(dividingBy: scaledGridSize)
            while y <= endY {
                let canvasPoint = CGPoint(x: 0, y: y)
                let viewPoint = transform.canvasToView(canvasPoint)
                
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: viewPoint.y))
                        path.addLine(to: CGPoint(x: size.width, y: viewPoint.y))
                    },
                    with: .color(.gray.opacity(0.3)),
                    lineWidth: 0.5
                )
                y += scaledGridSize
            }
        }
    }
}

// MARK: - Canvas Background

struct CanvasBackground: View {
    let gridEnabled: Bool
    let gridSize: CGFloat
    let zoom: CGFloat
    let pan: CGPoint
    
    var body: some View {
        ZStack {
            // Background color
            Color(NSColor.controlBackgroundColor)
                .ignoresSafeArea()
            
        }
    }
}

// MARK: - Canvas Contact Node View

struct CanvasContactNodeView: View {
    let contact: ContactNode
    let isSelected: Bool
    let showDebugCoordinates: Bool
    let isHandMode: Bool
    let isSelectionMode: Bool
    let zoom: CGFloat
    let pan: CGPoint
    let viewSize: CGSize
    let onTap: () -> Void
    let onDrag: (DragGesture.Value) -> Void
    let onEndDrag: () -> Void
    
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: contact.size.width, height: contact.size.width)
                
                if let profileImage = contact.profileImage {
                    // Use profile photo data (same logic as contact toolbar)
                    Image(nsImage: profileImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: contact.size.width - 4, height: contact.size.width - 4)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if let avatarURL = contact.avatarURL {
                    // Fallback to avatar URL if no profile photo data
                    AsyncImage(url: avatarURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Text(contact.initials)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    }
                    .frame(width: contact.size.width - 4, height: contact.size.width - 4)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    // Show initials if no image available (same logic as contact toolbar)
                    Text(contact.initials)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
            }
            
            Text(contact.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: contact.size.width)
            
            // Debug coordinates (only show if debug points enabled)
            if showDebugCoordinates {
                Text("(\(Int(contact.position.x)), \(Int(contact.position.y)))")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.blue)
                    .frame(width: contact.size.width)
                    .semiTransparentBackground()
                    .cornerRadius(4)
                    .onAppear {
                        print("🔍 Contact coordinate text appeared for contact: \(contact.name) at (\(Int(contact.position.x)), \(Int(contact.position.y)))")
                    }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 2)
        )
        .overlay(
            // Blue selection glow
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue, lineWidth: 3)
                .opacity(isSelected ? 0.8 : 0)
                .blur(radius: 2)
        )
        .background(
            // Transparent clickable area covering the entire node
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.clear)
                .frame(width: contact.size.width + 8, height: contact.size.height + 8)
        )
        .position(canvasToView(contact.position))
        .simultaneousGesture(
            // Enable drag gesture only in selection mode to avoid conflicts with canvas pan
            // Use minimumDistance of 3 to allow taps (including with modifiers) to be recognized
            isSelectionMode ? DragGesture(minimumDistance: 3)
                .onChanged { value in
                    isDragging = true
                    onDrag(value)
                }
                .onEnded { _ in
                    isDragging = false
                    onEndDrag()
                } : nil
        )
        .onTapGesture {
            onTap()
        }
    }
    
    private func canvasToView(_ point: CGPoint) -> CGPoint {
        // Use CanvasTransform to handle the new pan offset system - use passed zoom/pan parameters
        let transform = CanvasTransform(zoom: zoom, pan: pan)
        // Convert bottom-left canvas coordinates to top-left view coordinates
        let topLeftCanvasPoint = CGPoint(x: point.x, y: -point.y)
        let topLeftViewPoint = transform.canvasToView(topLeftCanvasPoint)
        // Convert to bottom-left view coordinates
        return CGPoint(
            x: topLeftViewPoint.x,
            y: viewSize.height - topLeftViewPoint.y
        )
    }
    
}

// MARK: - Canvas Content

struct CanvasContent: View {
    let viewModel: GroupsMapViewModel
    let gestureCoordinator: CanvasGestureCoordinator
    @ObservedObject var dragManager: CanvasDragManager
    let viewSize: CGSize
    let showingGroupQuickMenu: Bool
    let overlappingGroups: [GroupCircle]
    let quickMenuPosition: CGPoint
    let showingZoomFeedback: Bool
    let isCreatingGroup: Bool
    let isClickingOnEmptySpace: Bool
    @Binding var isHandleDragging: Bool
    let onGroupTap: (GroupCircle) -> Void
    let onContactTap: (ContactNode) -> Void
    let onGroupQuickMenuSelect: (UUID) -> Void
    let onAddNewGroup: () -> Void
    let onGroupCreationDrag: (DragGesture.Value) -> Void
    let onEndGroupCreation: () -> Void
    let onGroupResize: (UUID, CGFloat) -> Void
    let onGroupRotate: (UUID, CGFloat) -> Void
    let onCanvasTap: (CGPoint) -> Void
    let calculateLeftUIWidth: () -> CGFloat
    
    // MARK: - Drag Handlers
    
    /// Handle drag start for contact
    private func handleContactDragStart(_ contact: ContactNode, value: DragGesture.Value) {
        print("🎯 Starting contact drag for \(contact.name)")
        
        // Select the contact if not already selected
        if !viewModel.selectedContacts.contains(contact.id) {
            viewModel.clearSelection()
            viewModel.selectContact(contact.id, addToSelection: false)
        }
        
        // Get all selected elements
        let selectedContacts = viewModel.selectedContacts
        let selectedGroups = viewModel.selectedGroups
        let allSelectedElements = selectedContacts.union(selectedGroups)
        
        // Prepare element types and original positions
        var elementTypes: [UUID: CanvasDragManager.ElementType] = [:]
        var originalPositions: [UUID: CGPoint] = [:]
        
        // Add selected contacts
        for contactId in selectedContacts {
            if let contact = viewModel.contacts.first(where: { $0.id == contactId }) {
                elementTypes[contactId] = .contact
                originalPositions[contactId] = contact.position
            }
        }
        
        // Add selected groups
        for groupId in selectedGroups {
            if let group = viewModel.groups.first(where: { $0.id == groupId }) {
                elementTypes[groupId] = .group
                originalPositions[groupId] = group.center
            }
        }
        
        // Start drag
        dragManager.startDrag(
            elementIds: allSelectedElements,
            elementTypes: elementTypes,
            startPosition: value.startLocation,
            originalPositions: originalPositions,
            viewModel: viewModel
        )
    }
    
    /// Handle drag start for group
    private func handleGroupDragStart(_ group: GroupCircle, value: DragGesture.Value) {
        print("🎯 Starting group drag for \(group.name)")
        
        // Select the group if not already selected
        if !viewModel.selectedGroups.contains(group.id) {
            viewModel.clearSelection()
            viewModel.selectGroup(group.id, addToSelection: false)
        }
        
        // Get all selected elements
        let selectedContacts = viewModel.selectedContacts
        let selectedGroups = viewModel.selectedGroups
        let allSelectedElements = selectedContacts.union(selectedGroups)
        
        // Prepare element types and original positions
        var elementTypes: [UUID: CanvasDragManager.ElementType] = [:]
        var originalPositions: [UUID: CGPoint] = [:]
        
        // Add selected contacts
        for contactId in selectedContacts {
            if let contact = viewModel.contacts.first(where: { $0.id == contactId }) {
                elementTypes[contactId] = .contact
                originalPositions[contactId] = contact.position
            }
        }
        
        // Add selected groups
        for groupId in selectedGroups {
            if let group = viewModel.groups.first(where: { $0.id == groupId }) {
                elementTypes[groupId] = .group
                originalPositions[groupId] = group.center
            }
        }
        
        // Start drag
        dragManager.startDrag(
            elementIds: allSelectedElements,
            elementTypes: elementTypes,
            startPosition: value.startLocation,
            originalPositions: originalPositions,
            viewModel: viewModel
        )
    }
    
    /// Handle drag update
    private func handleDragUpdate(_ value: DragGesture.Value) {
        guard dragManager.isDragging else { return }
        
        // Update positions using drag manager
        let newPositions = dragManager.updateDrag(
            currentPosition: value.location,
            zoom: viewModel.canvasState.zoom
        )
        
        // Apply position updates to view model
        viewModel.updateElementPositions(newPositions)
    }
    
    /// Handle drag end
    private func handleDragEnd() {
        guard dragManager.isDragging else { return }
        
        print("🎯 Ending drag")
        
        // End drag and save to database
        if dragManager.endDrag(viewModel: viewModel) != nil {
            // Save to database
            viewModel.saveElementPositions()
            
            // Recalculate group memberships after drag completion
            // This ensures contacts are properly added/removed from groups based on their new positions
            print("🎯 Recalculating group memberships after drag completion")
            viewModel.recalculateGroupMemberships()
        }
    }
    
    var body: some View {
        ZStack {
            // Invisible drop target - ensures drop area is always active even on empty canvas
            // This is critical for drag and drop to work when canvas has no elements
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(0)
            
            // Groups (rendered behind contacts, except when selected with handles showing)
            ForEach(viewModel.groups) { group in
                let isSelected = viewModel.selectedGroups.contains(group.id)
                let showingHandles = isSelected && viewModel.shouldShowTransformHandles
                
                CanvasGroupCircleView(
                    group: group,
                    isSelected: isSelected,
                    showDebugCoordinates: viewModel.debugSettings.showDebugPoints,
                    showTransformHandles: viewModel.shouldShowTransformHandles,
                    isSelectionMode: viewModel.isSelectionMode,
                    zoom: viewModel.canvasState.zoom,
                    pan: viewModel.canvasState.pan,
                    viewSize: viewSize,
                    onTap: { onGroupTap(group) },
                    onDrag: { value in 
                        if !dragManager.isDragging {
                            handleGroupDragStart(group, value: value)
                        }
                        handleDragUpdate(value)
                    },
                    onEndDrag: { 
                        handleDragEnd()
                    },
                    onResize: { newWidth, newHeight in 
                        print("🔧 SimplifiedCanvasView: onResize called for group \(group.id) with width: \(newWidth), height: \(newHeight)")
                        onGroupResize(group.id, newWidth) 
                    },
                    onRotate: { angle in onGroupRotate(group.id, angle) }
                )
                .zIndex(showingHandles ? 3 : 1) // Selected groups with handles render on top
            }
            .clipped() // Clip groups to canvas bounds
            
            // Contacts (rendered on top of groups)
            ForEach(viewModel.contacts) { contact in
                CanvasContactNodeView(
                    contact: contact,
                    isSelected: viewModel.selectedContacts.contains(contact.id),
                    showDebugCoordinates: viewModel.debugSettings.showDebugPoints,
                    isHandMode: viewModel.isHandMode,
                    isSelectionMode: viewModel.isSelectionMode,
                    zoom: viewModel.canvasState.zoom,
                    pan: viewModel.canvasState.pan,
                    viewSize: viewSize,
                    onTap: { onContactTap(contact) },
                    onDrag: { value in 
                        if !dragManager.isDragging {
                            handleContactDragStart(contact, value: value)
                        }
                        handleDragUpdate(value)
                    },
                    onEndDrag: { 
                        handleDragEnd()
                    }
                )
            }
            .clipped() // Clip contacts to canvas bounds
            .zIndex(2) // Contacts on top of groups
            
            // Transform handles (rendered on top of everything for clear hit-testing)
            if viewModel.shouldShowTransformHandles, let selectedGroup = viewModel.groups.first(where: { viewModel.selectedGroups.contains($0.id) }) {
                CanvasTransformHandles(
                    group: selectedGroup,
                    zoom: viewModel.canvasState.zoom,
                    pan: viewModel.canvasState.pan,
                    viewSize: viewSize,
                    onResize: { newWidth, newHeight, newCenter in
                        // Lightweight update - just change in-memory state
                        viewModel.resizeAndRepositionGroup(selectedGroup.id, width: newWidth, height: newHeight, center: newCenter)
                    },
                    onRotate: { angle in
                        // Lightweight update - just change in-memory state
                        onGroupRotate(selectedGroup.id, angle)
                    },
                    onCommit: {
                        // Expensive operations deferred to drag end
                        viewModel.commitGroupTransform(selectedGroup.id)
                    },
                    isHandleDragging: $isHandleDragging
                )
                .zIndex(100) // Handles on top of everything
            }
            
            // Zoom feedback indicator
            if showingZoomFeedback {
                VStack {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.title2)
                                .foregroundColor(.green)
                            Text("\(Int(viewModel.canvasState.zoom * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor).opacity(0.9))
                        )
                        .padding()
                    }
                    Spacer()
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: showingZoomFeedback)
            }
        }
        .onDrop(of: [.vCard, .crmGroup, .crmContactList], isTargeted: nil) { providers, location in
            DragDropLogger.shared.log("CanvasContent onDrop triggered with \(providers.count) providers at location: \(location)", operation: "DESTINATION")
            
            // Convert the drop location (in view coordinates) to canvas coordinates
            let canvasPoint = viewToCanvas(location)
            DragDropLogger.shared.log("Drop location: \(location), Canvas point: \(canvasPoint)", operation: "DESTINATION")
            
            for provider in providers {
                // Handle contact drops via crmContactList (native SwiftUI transferable)
                if provider.registeredTypeIdentifiers.contains(UTType.crmContactList.identifier) {
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.crmContactList.identifier) { data, error in
                        if let error = error {
                            DragDropLogger.shared.log("Failed to load crmContactList data representation: \(error)", operation: "ERROR")
                            return
                        }
                        
                        guard let data = data else {
                            DragDropLogger.shared.log("No crmContactList data received from provider", operation: "ERROR")
                            return
                        }
                        
                        do {
                            let contact = try JSONDecoder().decode(Contact.self, from: data)
                            DragDropLogger.shared.log("Successfully decoded contact: \(contact.name) with phone: \(contact.phone)", operation: "SUCCESS")
                            
                            DispatchQueue.main.async {
                                viewModel.addContactFromDrop(contact, at: canvasPoint)
                            }
                        } catch {
                            DragDropLogger.shared.log("Failed to decode contact: \(error)", operation: "ERROR")
                        }
                    }
                }
                
                // Handle contact drops via vCard (external compatibility)
                if provider.registeredTypeIdentifiers.contains(UTType.vCard.identifier) {
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.vCard.identifier) { data, error in
                    if let error = error {
                        DragDropLogger.shared.log("Failed to load vCard data representation: \(error)", operation: "ERROR")
                        return
                    }
                    
                    guard let data = data else {
                        DragDropLogger.shared.log("No vCard data received from provider", operation: "ERROR")
                        return
                    }
                    
                    guard let vCardString = String(data: data, encoding: .utf8) else {
                        DragDropLogger.shared.log("Failed to convert data to vCard string", operation: "ERROR")
                        return
                    }
                    
                    DragDropLogger.shared.log("Received vCard data: \(vCardString)", operation: "SUCCESS")
                    
                    let contact = Contact.fromVCardString(vCardString)
                    DragDropLogger.shared.log("Parsed contact: \(contact.name) with phone: \(contact.phone)", operation: "SUCCESS")
                    
                    DispatchQueue.main.async {
                        viewModel.addContactFromDrop(contact, at: canvasPoint)
                    }
                }
                }
                
                // Handle group drops
                if provider.registeredTypeIdentifiers.contains(UTType.crmGroup.identifier) {
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.crmGroup.identifier) { data, error in
                        if let error = error {
                            DragDropLogger.shared.log("Failed to load group data representation: \(error)", operation: "ERROR")
                            return
                        }
                        
                        guard let data = data else {
                            DragDropLogger.shared.log("No group data received from provider", operation: "ERROR")
                            return
                        }
                        
                        do {
                            let group = try JSONDecoder().decode(ContactGroup.self, from: data)
                            DragDropLogger.shared.log("Successfully decoded group: \(group.name)", operation: "SUCCESS")
                            
                            DispatchQueue.main.async {
                                viewModel.addGroupFromDrop(group, at: canvasPoint)
                            }
                        } catch {
                            DragDropLogger.shared.log("Failed to decode group: \(error)", operation: "ERROR")
                        }
                    }
                }
            }
            return true
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    onGroupCreationDrag(value)
                }
                .onEnded { value in
                    onEndGroupCreation()
                }
        )
        .onTapGesture(coordinateSpace: .local) { location in
            onCanvasTap(location)
        }
        .contextMenu {
            // Only show "Add New Group" when clicking on empty space or when there's a selection
            if isClickingOnEmptySpace || !viewModel.selectedContacts.isEmpty || !viewModel.selectedGroups.isEmpty {
                Button("Add New Group") {
                    onAddNewGroup()
                }
            }
        }
    }
    
    private func viewToCanvas(_ point: CGPoint) -> CGPoint {
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
}

// MARK: - Group Quick Menu

struct GroupQuickMenu: View {
    let groups: [GroupCircle]
    let position: CGPoint
    let onSelect: (UUID) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groups) { group in
                Button(action: {
                    onSelect(group.id)
                }) {
                    HStack {
                        Circle()
                            .fill(group.color)
                            .frame(width: 12, height: 12)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Text("\(group.members.count) members")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: .black.opacity(0.1), radius: 2)
                )
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.95))
                .shadow(color: .black.opacity(0.2), radius: 4)
        )
        .position(position)
        .onTapGesture {
            onDismiss()
        }
    }
}

// MARK: - Canvas Toolbar

struct CanvasToolbar: View {
    @ObservedObject var viewModel: GroupsMapViewModel
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    let gestureCoordinator: CanvasGestureCoordinator
    let viewSize: CGSize
    @State private var showingCreateDialog = false
    @State private var newMapName = ""
    @State private var availableCanvases: [Canvas] = []
    
    var body: some View {
        HStack(spacing: 12) {
            // Canvas selection dropdown
            Menu {
                ForEach(availableCanvases) { canvas in
                    Button(action: {
                        print("🔧 User selected canvas from dropdown: \(canvas.name) (ID: \(canvas.id))")
                        print("🔧 Canvas from dropdown has \(canvas.elements.count) elements")
                        loadCanvas(canvas)
                    }) {
                        HStack {
                            Text(canvas.name)
                            Spacer()
                            if canvas.metadata["favorite"] == "true" {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                            }
                        }
                    }
                    .contextMenu {
                        Button(action: {
                            toggleCanvasFavorite(canvasId: canvas.id)
                        }) {
                            Label(
                                canvas.metadata["favorite"] == "true" ? "Remove from Favorites" : "Add to Favorites",
                                systemImage: canvas.metadata["favorite"] == "true" ? "star.slash" : "star"
                            )
                        }
                    }
                }
                
                Divider()
                
                Button("Create New Canvas...") {
                    showingCreateDialog = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentCanvasName)
                        .font(.caption)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .controlBackground()
                .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .onAppear {
                loadAvailableCanvases()
            }
            
            Divider()
                .frame(height: 20)
            
            // Zoom controls
            HStack(spacing: 4) {
                Button(action: { 
                    viewModel.zoomOutFromCenter(viewSize: viewSize)
                }) {
                    Image(systemName: "minus")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                
                Text("\(Int(viewModel.canvasState.zoom * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 35)
                
                Button(action: { 
                    viewModel.zoomInFromCenter(viewSize: viewSize)
                }) {
                    Image(systemName: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            
            Divider()
                .frame(height: 20)
            
            // Mode toggle icons
            HStack(spacing: 8) {
                // Select Mode
                Button(action: {
                    viewModel.setMode(.select)
                }) {
                    Image(systemName: "cursorarrow")
                        .font(.caption2)
                        .foregroundColor(viewModel.canvasState.mode == .select ? .white : .primary)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(viewModel.canvasState.mode == .select ? Color.accentColor : Color.gray.opacity(0.3))
                        )
                }
                .buttonStyle(.plain)
                
                // Hand Mode
                Button(action: {
                    viewModel.setMode(.hand)
                }) {
                    Image(systemName: "hand.draw")
                        .font(.caption2)
                        .foregroundColor(viewModel.canvasState.mode == .hand ? .white : .primary)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(viewModel.canvasState.mode == .hand ? Color.accentColor : Color.gray.opacity(0.3))
                        )
                }
                .buttonStyle(.plain)
                
                // Add Group Mode
                Button(action: {
                    viewModel.setMode(.addGroup)
                }) {
                    Image(systemName: "circle.grid.2x2")
                        .font(.caption2)
                        .foregroundColor(viewModel.canvasState.mode == .addGroup ? .white : .primary)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(viewModel.canvasState.mode == .addGroup ? Color.accentColor : Color.gray.opacity(0.3))
                        )
                }
                .buttonStyle(.plain)
                
                // Show Grid
                Button(action: {
                    viewModel.canvasState.gridEnabled.toggle()
                }) {
                    Image(systemName: "grid")
                        .font(.caption2)
                        .foregroundColor(viewModel.canvasState.gridEnabled ? .white : .primary)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(viewModel.canvasState.gridEnabled ? Color.accentColor : Color.gray.opacity(0.3))
                        )
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Status info
            if !viewModel.selectedContacts.isEmpty || !viewModel.selectedGroups.isEmpty {
                Text("Selected: \(viewModel.selectedContacts.count) contacts, \(viewModel.selectedGroups.count) groups")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
        .alert("Create New Canvas", isPresented: $showingCreateDialog) {
            TextField("Canvas Name", text: $newMapName)
            Button("Create") {
                if !newMapName.isEmpty {
                    // Create new canvas
                    let newCanvas = Canvas(
                        name: newMapName,
                        canvasType: .groupMap,
                        canvasState: CanvasState(gridEnabled: true)
                    )
                    let repository = DatabaseCanvasRepository()
                    if repository.createCanvas(newCanvas) {
                        globalCanvasService.setCurrentCanvas(newCanvas)
                        loadAvailableCanvases()
                    }
                    newMapName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newMapName = ""
            }
        } message: {
            Text("Enter a name for your new canvas")
        }
    }
    
    private var currentCanvasName: String {
        globalCanvasService.currentCanvas?.name ?? "Default Canvas"
    }
    
    private func loadAvailableCanvases() {
        // Load canvases asynchronously to prevent UI hanging
        DispatchQueue.global(qos: .userInitiated).async {
            let repository = DatabaseCanvasRepository()
            let canvases = repository.getGroupMapCanvasesOrdered()
            
            print("🔧 Loaded \(canvases.count) canvases for dropdown")
            for (index, canvas) in canvases.enumerated() {
                print("🔧 Canvas \(index): \(canvas.name) (ID: \(canvas.id)) with \(canvas.elements.count) elements")
            }
            
            DispatchQueue.main.async {
                self.availableCanvases = canvases
            }
        }
    }
    
    private func loadCanvas(_ canvas: Canvas) {
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "LOAD_CANVAS_FROM_DROPDOWN",
            details: "Loading canvas: \(canvas.name) (ID: \(canvas.id)) with \(canvas.elements.count) elements from dropdown selection",
            success: true
        )
        
        print("🔧 SimplifiedCanvasView.loadCanvas() called for canvas: \(canvas.name)")
        print("🔧 Canvas ID: \(canvas.id)")
        print("🔧 Canvas has \(canvas.elements.count) elements in dropdown object")
        
        // Debug: Print all element details from dropdown
        for (index, element) in canvas.elements.enumerated() {
            print("🔧 Dropdown Element \(index): ID=\(element.id), Type=\(element.elementType), Location=\(element.location)")
        }
        
        // Fetch the full canvas from database to ensure we have the latest data
        let repository = DatabaseCanvasRepository()
        guard let fullCanvas = repository.getCanvas(id: canvas.id) else {
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "LOAD_CANVAS_FROM_DROPDOWN_FAILED",
                details: "Failed to fetch full canvas from database for ID: \(canvas.id)",
                success: false
            )
            print("❌ Failed to fetch full canvas from database for ID: \(canvas.id)")
            return
        }
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "LOAD_CANVAS_FROM_DROPDOWN_SUCCESS",
            details: "Successfully fetched full canvas: \(fullCanvas.name) (ID: \(fullCanvas.id)) with \(fullCanvas.elements.count) elements from database",
            success: true
        )
        
        print("🔧 Successfully fetched full canvas from database")
        print("🔧 Full canvas name: \(fullCanvas.name)")
        print("🔧 Full canvas has \(fullCanvas.elements.count) elements")
        
        // Debug: Print all element details from database
        for (index, element) in fullCanvas.elements.enumerated() {
            print("🔧 Database Element \(index): ID=\(element.id), Type=\(element.elementType), Location=\(element.location)")
        }
        
        // Set the current canvas in the global service with the FULL canvas data
        globalCanvasService.setCurrentCanvas(fullCanvas)
        
        // Update the ViewModel's current map ID to match the selected canvas
        if let canvasId = UUID(uuidString: fullCanvas.id) {
            viewModel.currentMapId = canvasId
        }
        
        // Load the canvas into the ViewModel with dataProvider for contact lookup
        let dataProvider = globalCanvasService.getDataProvider()
        viewModel.loadCanvasFromDatabase(fullCanvas, dataProvider: dataProvider)
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "LOAD_CANVAS_COMPLETED",
            details: "Canvas loading completed for: \(fullCanvas.name) (ID: \(fullCanvas.id))",
            success: true
        )
        
        print("🔧 Canvas loading completed for: \(fullCanvas.name)")
        
        // Refresh the canvas selector dropdown to reflect the current canvas
        loadAvailableCanvases()
    }
    
    private func toggleCanvasFavorite(canvasId: String) {
        let repository = DatabaseCanvasRepository()
        if repository.toggleCanvasFavorite(canvasId: canvasId) {
            loadAvailableCanvases() // Reload the list
        }
    }
}


// MARK: - Simple Mouse Tracker

struct SimpleMouseTracker: View {
    let zoom: CGFloat
    let pan: CGPoint
    let viewSize: CGSize
    @State private var mouseLocation: CGPoint = .zero
    @State private var mouseViewLocation: CGPoint = .zero
    
    // Z-depth layers for different UI elements
    private let backgroundZ: Int = 1
    private let contactZ: Int = 2
    private let groupZ: Int = 3
    
    var body: some View {
        ZStack {
            // Background plane coordinates (grey) - Z=1
            ForEach(-3...4, id: \.self) { x in
                ForEach(-3...4, id: \.self) { y in
                    let point = CGPoint(x: CGFloat(x) * 100, y: CGFloat(-y) * 100)
                    ZStack {
                        // Visual dot
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 4, height: 4)
                        
                        // Coordinate text
                        Text("(\(Int(point.x)),\(Int(point.y)),\(backgroundZ))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                            .offset(x: 0, y: 12 + CGFloat(backgroundZ - 1) * 15)
                    }
                    .position(canvasToView(point))
                }
            }
            
            // Contact plane coordinates (blue) - Z=2
            ForEach(-3...4, id: \.self) { x in
                ForEach(-3...4, id: \.self) { y in
                    let point = CGPoint(x: CGFloat(x) * 100, y: CGFloat(-y) * 100)
                    ZStack {
                        // Visual dot
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 4, height: 4)
                        
                        // Coordinate text
                        Text("(\(Int(point.x)),\(Int(point.y)),\(contactZ))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.blue)
                            .offset(x: 0, y: 12 + CGFloat(contactZ - 1) * 15)
                    }
                    .position(canvasToView(point))
                }
            }
            
            // Group plane coordinates (green) - Z=3
            ForEach(-3...4, id: \.self) { x in
                ForEach(-3...4, id: \.self) { y in
                    let point = CGPoint(x: CGFloat(x) * 100, y: CGFloat(-y) * 100)
                    ZStack {
                        // Visual dot
                        Circle()
                            .fill(Color.green)
                            .frame(width: 4, height: 4)
                        
                        // Coordinate text
                        Text("(\(Int(point.x)),\(Int(point.y)),\(groupZ))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .offset(x: 0, y: 12 + CGFloat(groupZ - 1) * 15)
                    }
                    .position(canvasToView(point))
                }
            }
            
            // Invisible overlay that tracks mouse movement
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onHover { isHovering in
                    if isHovering {
                        print("🔍 Mouse is hovering over canvas")
                    }
                }
            
            // Mouse position text (red) - follows the mouse
            Text("MOUSE(\(Int(mouseLocation.x)), \(Int(mouseLocation.y)))")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.red)
                .modalBackground()
                .cornerRadius(4)
                .padding(4)
                .position(x: mouseViewLocation.x + 50, y: mouseViewLocation.y - 20) // Offset to avoid covering cursor
                .onAppear {
                    print("🔍 Mouse position text appeared at: \(mouseLocation)")
                }
        }
        .coordinateSpace(name: "canvas")
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                // Store view coordinates for positioning the text
                mouseViewLocation = location
                // Convert view coordinates to canvas coordinates
                let canvasPoint = viewToCanvas(location)
                mouseLocation = canvasPoint
                print("🔍 Mouse at view: \(location), canvas: \(canvasPoint)")
            case .ended:
                print("🔍 Mouse left canvas")
            }
        }
    }
    
    private func viewToCanvas(_ point: CGPoint) -> CGPoint {
        let transform = CanvasTransform(zoom: zoom, pan: pan)
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
    
    private func canvasToView(_ point: CGPoint) -> CGPoint {
        let transform = CanvasTransform(zoom: zoom, pan: pan)
        // Convert bottom-left canvas coordinates to top-left view coordinates
        let topLeftCanvasPoint = CGPoint(x: point.x, y: -point.y)
        let topLeftViewPoint = transform.canvasToView(topLeftCanvasPoint)
        // Convert to bottom-left view coordinates
        return CGPoint(
            x: topLeftViewPoint.x,
            y: viewSize.height - topLeftViewPoint.y
        )
    }
}

#Preview {
    let viewModel = GroupsMapViewModel()
    let gestureCoordinator = CanvasGestureCoordinator(viewModel: viewModel)
    let edgeScrollingManager = EdgeScrollingManager()
    SimplifiedCanvasView(viewModel: viewModel, gestureCoordinator: gestureCoordinator, edgeScrollingManager: edgeScrollingManager)
        .frame(width: 800, height: 600)
}

