import SwiftUI
import UniformTypeIdentifiers

struct GroupCircleView: View {
    let group: ContactGroup
    @EnvironmentObject var selectionManager: SelectionManager
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var appState: AppState
    @StateObject private var groupEditingService: GroupEditingService
    @State private var showingEditDialog = false
    @State private var showingDeleteAlert = false
    
    init(group: ContactGroup) {
        self.group = group
        self._groupEditingService = StateObject(wrappedValue: GroupEditingService())
    }
    
    var body: some View {
        GroupCircleBackground(
            group: group,
            isSelected: selectionManager.isGroupSelected(group.id)
        )
        .scaleEffect(selectionManager.isGroupSelected(group.id) ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: selectionManager.isGroupSelected(group.id))
        .groupContextMenu(
            for: group,
            groupEditingService: groupEditingService,
            onEdit: {
                groupEditingService.startEditingGroup(group)
            },
            onDelete: {
                showingDeleteAlert = true
            },
            onViewDetails: {
                navigateToGroupDetails()
            }
        )
        .sheet(isPresented: $groupEditingService.showingEditDialog, onDismiss: {
            // Reload canvas after group edit dialog closes to update UI
            reloadCanvasAfterGroupEdit()
        }) {
            GroupEditDialog(groupEditingService: groupEditingService)
        }
        .alert("Delete Group", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await deleteGroup()
                }
            }
        } message: {
            Text("Are you sure you want to delete '\(group.name)'? This action cannot be undone.")
        }
        .onAppear {
            // Set the dataProvider for GroupEditingService
            groupEditingService.setDataProvider(dataProvider)
        }
    }
    
    private func reloadCanvasAfterGroupEdit() {
        // Reload the current canvas from database to update any UI changes made in the group editor
        if let canvasId = GlobalCanvasService.shared.currentCanvas?.id {
            LogManager.shared.info("🔄 Reloading canvas from database (ID: \(canvasId)) after group edit")
            GlobalCanvasService.shared.loadCanvas(id: canvasId)
        }
    }
    
    private func navigateToGroupDetails() {
        // Navigate to Group Details page
        print("Navigate to group details for: \(group.name)")
        
        // Set the selected page to deckBuilder and select this group
        appState.selectPage(Page.deckBuilder)
        appState.selectedDeck = group.id
    }
    
    private func deleteGroup() async {
        do {
            try await dataProvider.deleteGroup(group.id)
            LogManager.shared.info("Successfully deleted group: \(group.name)")
        } catch {
            LogManager.shared.error("Failed to delete group: \(error)")
        }
    }
}

struct GroupCircleBackground: View {
    let group: ContactGroup
    let isSelected: Bool
    
    @EnvironmentObject var selectionManager: SelectionManager
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    
    var body: some View {
        ZStack {
            // Background Circle
            Circle()
                .fill(group.color.opacity(0.2))
                .stroke(group.color, lineWidth: isSelected ? 4 : 2)
                .frame(width: 120, height: 120)
                .background(
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                )
            
            // Group Content
            GroupCircleContent(group: group)
        }
    }
}

struct GroupCircleContent: View {
    let group: ContactGroup
    
    var body: some View {
        VStack(spacing: 4) {
            Text(group.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            Text("\(group.memberCount) members")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
    }
}

// MARK: - Canvas Group Circle View

struct CanvasGroupCircleView: View {
    let group: GroupCircle
    let isSelected: Bool
    let showDebugCoordinates: Bool
    let showTransformHandles: Bool
    let isSelectionMode: Bool
    let zoom: CGFloat
    let pan: CGPoint
    let viewSize: CGSize
    let onTap: () -> Void
    let onDrag: (DragGesture.Value) -> Void
    let onEndDrag: () -> Void
    let onResize: (CGFloat, CGFloat) -> Void
    let onRotate: (CGFloat) -> Void
    
    @State private var isDragging = false
    @State private var isHandleDragging = false
    @StateObject private var groupEditingService: GroupEditingService
    @State private var showingDeleteAlert = false
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    @EnvironmentObject var appState: AppState
    
    init(group: GroupCircle, isSelected: Bool, showDebugCoordinates: Bool, showTransformHandles: Bool, isSelectionMode: Bool, zoom: CGFloat, pan: CGPoint, viewSize: CGSize, onTap: @escaping () -> Void, onDrag: @escaping (DragGesture.Value) -> Void, onEndDrag: @escaping () -> Void, onResize: @escaping (CGFloat, CGFloat) -> Void, onRotate: @escaping (CGFloat) -> Void) {
        self.group = group
        self.isSelected = isSelected
        self.showDebugCoordinates = showDebugCoordinates
        self.showTransformHandles = showTransformHandles
        self.isSelectionMode = isSelectionMode
        self.zoom = zoom
        self.pan = pan
        self.viewSize = viewSize
        self.onTap = onTap
        self.onDrag = onDrag
        self.onEndDrag = onEndDrag
        self.onResize = onResize
        self.onRotate = onRotate
        self._groupEditingService = StateObject(wrappedValue: GroupEditingService())
    }
    
    var body: some View {
        ZStack {
            // Main group container with proper coordinate system
            GroupCircleContainer(
                group: group,
                isSelected: isSelected,
                showDebugCoordinates: showDebugCoordinates,
                showTransformHandles: showTransformHandles,
                isSelectionMode: isSelectionMode,
                zoom: zoom,
                isHandleDragging: $isHandleDragging,
                onTap: onTap,
                onDrag: onDrag,
                onEndDrag: onEndDrag,
                onResize: onResize,
                onRotate: onRotate,
                onContactDrop: addContactToCanvasGroup,
                onGroupDrop: addGroupToCanvas,
                localToCanvas: localToCanvas
            )
        }
        .position(canvasToView(group.center, pan: pan))
        .simultaneousGesture(
            // Move drag gesture to global coordinate system to match contact behavior
            // This ensures consistent drag behavior between contacts and groups
            // Use minimumDistance of 3 to allow taps (including with modifiers) to be recognized
            // Block parent drag when handles are being dragged
            (isSelectionMode && !isHandleDragging) ? DragGesture(minimumDistance: 3)
                .onChanged { value in
                    print("🔧 CanvasGroupCircleView: Group drag initiated - delegating to unified system")
                    onDrag(value)
                }
                .onEnded { _ in
                    print("🔧 CanvasGroupCircleView: Group drag ended - delegating to unified system")
                    onEndDrag()
                } : nil
        )
        .contextMenu {
            CanvasGroupContextMenu(
                group: group,
                groupEditingService: groupEditingService,
                onEdit: {
                    editCanvasGroup()
                },
                onDelete: {
                    showingDeleteAlert = true
                },
                onViewDetails: {
                    navigateToCanvasGroupDetails()
                }
            )
        }
        .sheet(isPresented: $groupEditingService.showingEditDialog, onDismiss: {
            // Reload canvas after group edit dialog closes to update UI
            reloadCanvasAfterGroupEdit()
        }) {
            GroupEditDialog(groupEditingService: groupEditingService)
        }
        .alert("Delete Group", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await deleteCanvasGroup()
                }
            }
        } message: {
            Text("Are you sure you want to delete '\(group.name)'? This action cannot be undone.")
        }
        .onAppear {
            // Set the dataProvider for GroupEditingService
            groupEditingService.setDataProvider(dataProvider)
        }
    }
    
    // MARK: - Canvas Group Actions
    
    private func reloadCanvasAfterGroupEdit() {
        // Reload the current canvas from database to update any UI changes made in the group editor
        if let canvasId = globalCanvasService.currentCanvas?.id {
            LogManager.shared.info("🔄 Reloading canvas from database (ID: \(canvasId)) after group edit")
            globalCanvasService.loadCanvas(id: canvasId)
        }
    }
    
    private func editCanvasGroup() {
        // Use database integer ID to find the group
        guard let dbId = group.databaseId else {
            LogManager.shared.error("No database ID for canvas group: \(group.name)")
            return
        }
        
        Task {
            do {
                let allGroups = try await dataProvider.fetchGroups()
                
                // Find by database integer ID (not UUID!)
                guard let databaseGroup = allGroups.first(where: { $0.databaseId == dbId }) else {
                    LogManager.shared.error("Could not find group for database ID: \(dbId)")
                    LogManager.shared.error("Available groups: \(allGroups.map { "\($0.name) (dbId: \($0.databaseId ?? -1))" }.joined(separator: ", "))")
                    return
                }
                
                LogManager.shared.info("Found database group '\(databaseGroup.name)' for database ID: \(dbId)")
                
                await MainActor.run {
                    groupEditingService.startEditingGroup(databaseGroup)
                }
            } catch {
                LogManager.shared.error("Failed to find database group for editing: \(error)")
            }
        }
    }
    
    private func navigateToCanvasGroupDetails() {
        // Navigate to Group Details page
        print("Navigate to group details for canvas group: \(group.name)")
        
        // Set the selected page to deckBuilder and select this group
        appState.selectPage(Page.deckBuilder)
        appState.selectedDeck = group.id
    }
    
    private func deleteCanvasGroup() async {
        // Use database integer ID to find the group
        guard let dbId = group.databaseId else {
            LogManager.shared.error("No database ID for canvas group deletion: \(group.name)")
            return
        }
        
        do {
            let allGroups = try await dataProvider.fetchGroups()
            
            // Find by database integer ID (not UUID!)
            guard let databaseGroup = allGroups.first(where: { $0.databaseId == dbId }) else {
                LogManager.shared.error("Could not find group for database ID: \(dbId)")
                return
            }
            
            LogManager.shared.info("Found database group '\(databaseGroup.name)' for deletion (database ID: \(dbId))")
            
            try await dataProvider.deleteGroup(databaseGroup.id)
            LogManager.shared.info("Successfully deleted canvas group: \(group.name)")
        } catch {
            LogManager.shared.error("Failed to delete canvas group: \(error)")
        }
    }
    
    
    private func canvasToView(_ point: CGPoint, pan: CGPoint) -> CGPoint {
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
    
    /// Convert local group coordinates to canvas coordinates
    /// - Parameter localPoint: Point in the group's local SwiftUI frame coordinate space
    /// - Returns: Point in canvas coordinate space
    private func localToCanvas(_ localPoint: CGPoint) -> CGPoint {
        // CRITICAL: The localPoint comes from .dropDestination which provides coordinates
        // in the group's local SwiftUI frame (where the view is positioned).
        // The group view is positioned using .position() which centers it at canvasToView(group.center).
        
        // Step 1: Get the group's position in view coordinates
        let groupViewPosition = canvasToView(group.center, pan: pan)
        
        // Step 2: The local drop point is relative to the view's frame center (because we use .position())
        // Convert local coordinates to view coordinates by offsetting from the group's view position
        // Since .position() centers the view, local coordinates are centered at the view's center
        let viewPoint = CGPoint(
            x: groupViewPosition.x + localPoint.x,
            y: groupViewPosition.y + localPoint.y
        )
        
        DragDropLogger.shared.log(
            "Step 1 - Group center: \(group.center) -> View position: \(groupViewPosition)",
            operation: "COORDINATE_TRANSFORM"
        )
        DragDropLogger.shared.log(
            "Step 2 - Local point: \(localPoint) -> View point: \(viewPoint)",
            operation: "COORDINATE_TRANSFORM"
        )
        
        // Step 3: Convert view coordinates to canvas coordinates using the standard transform
        let transform = CanvasTransform(zoom: zoom, pan: pan)
        
        // Convert bottom-left view coordinates to top-left for the transform
        let topLeftViewPoint = CGPoint(
            x: viewPoint.x,
            y: viewSize.height - viewPoint.y
        )
        let topLeftCanvasPoint = transform.viewToCanvas(topLeftViewPoint)
        
        // Convert to bottom-left canvas coordinates
        let canvasPoint = CGPoint(
            x: topLeftCanvasPoint.x,
            y: -topLeftCanvasPoint.y
        )
        
        DragDropLogger.shared.log(
            "Step 3 - View point: \(viewPoint) -> Canvas point: \(canvasPoint)",
            operation: "COORDINATE_TRANSFORM"
        )
        DragDropLogger.shared.log(
            "Final transform - Local: \(localPoint) -> Canvas: \(canvasPoint) (zoom: \(zoom), pan: \(pan))",
            operation: "COORDINATE_TRANSFORM"
        )
        
        return canvasPoint
    }
    
    // MARK: - Contact Drop Handling
    
    private func addContactToCanvasGroup(_ contact: Contact, at dropLocation: CGPoint? = nil) {
        DragDropLogger.shared.log(
            "Adding contact \(contact.displayName) to canvas group \(group.name) at location: \(dropLocation?.debugDescription ?? "nil")",
            operation: "CONTACT_DROP"
        )
        LogManager.shared.info("Adding contact \(contact.displayName) to canvas group \(group.name)")
        
        Task {
            do {
                // Find the corresponding ContactGroup in the database by name
                // This is more reliable than trying to use the GroupCircle's databaseId
                let allGroups = try await dataProvider.fetchGroups()
                guard let databaseGroup = allGroups.first(where: { $0.name == group.name }) else {
                    LogManager.shared.error("Could not find database group with name: \(group.name)")
                    DragDropLogger.shared.log("Failed to find database group: \(group.name)", operation: "ERROR")
                    return
                }
                
                LogManager.shared.info("Found database group: \(databaseGroup.name) with ID: \(databaseGroup.id)")
                
                // Add contact to the group in the database using the correct group ID
                try await dataProvider.add(phones: [contact.phone], to: databaseGroup.id)
                LogManager.shared.info("Successfully added contact \(contact.displayName) to group \(group.name)")
                DragDropLogger.shared.log(
                    "Contact \(contact.displayName) added to database group \(group.name)",
                    operation: "SUCCESS"
                )
                
                // Create a new contact node on the canvas at the actual drop location
                // Use the drop location if provided, otherwise fall back to group center
                let contactPosition = dropLocation ?? group.center
                DragDropLogger.shared.log(
                    "Creating contact node at canvas position: \(contactPosition)",
                    operation: "CONTACT_NODE_CREATION"
                )
                
                await MainActor.run {
                    globalCanvasService.addContactToCanvas(contact, at: contactPosition)
                }
                
                // Note: No need to refresh groups list as the dataProvider.add method
                // already updates the in-memory data and saves to database
            } catch {
                LogManager.shared.error("Failed to add contact to canvas group: \(error)")
                DragDropLogger.shared.log("Failed to add contact to canvas group: \(error)", operation: "ERROR")
            }
        }
    }
    
    // MARK: - Group Drop Handling
    
    private func addGroupToCanvas(_ droppedGroup: ContactGroup, at dropLocation: CGPoint? = nil) {
        DragDropLogger.shared.log(
            "Adding group \(droppedGroup.name) to canvas at location: \(dropLocation?.debugDescription ?? "nil")",
            operation: "GROUP_DROP"
        )
        LogManager.shared.info("Adding group \(droppedGroup.name) to canvas")
        
        // Use the drop location if provided, otherwise fall back to group center
        let groupPosition = dropLocation ?? group.center
        DragDropLogger.shared.log(
            "Creating group node at canvas position: \(groupPosition)",
            operation: "GROUP_NODE_CREATION"
        )
        
        // Add the group to the canvas via the global canvas service
        globalCanvasService.addGroupToCanvas(droppedGroup, at: groupPosition)
        
        LogManager.shared.info("Successfully added group \(droppedGroup.name) to canvas at \(groupPosition)")
        DragDropLogger.shared.log(
            "Group \(droppedGroup.name) added to canvas successfully",
            operation: "SUCCESS"
        )
    }
}

// MARK: - Group Circle Container with Integrated Handles

struct GroupCircleContainer: View {
    let group: GroupCircle
    let isSelected: Bool
    let showDebugCoordinates: Bool
    let showTransformHandles: Bool
    let isSelectionMode: Bool
    let zoom: CGFloat
    @Binding var isHandleDragging: Bool
    let onTap: () -> Void
    let onDrag: (DragGesture.Value) -> Void
    let onEndDrag: () -> Void
    let onResize: (CGFloat, CGFloat) -> Void
    let onRotate: (CGFloat) -> Void
    let onContactDrop: (Contact, CGPoint?) -> Void
    let onGroupDrop: (ContactGroup, CGPoint?) -> Void
    let localToCanvas: (CGPoint) -> CGPoint
    
    @State private var isDragging = false
    
    var body: some View {
        let _ = print("🔵 GroupCircleContainer: Rendering group '\(group.name)' - isSelected: \(isSelected), showTransformHandles: \(showTransformHandles)")
        
        return ZStack {
            // Group circle/oval - this is the base coordinate system
            Ellipse()
                .fill(group.color.opacity(0.1))
                .frame(width: group.width, height: group.height)
                .overlay(
                    Ellipse()
                        .stroke(group.color, lineWidth: 1)
                )
                .overlay(
                    // Blue selection glow
                    Ellipse()
                        .stroke(Color.blue, lineWidth: 3)
                        .opacity(isSelected ? 0.8 : 0)
                        .blur(radius: 2)
                )
                .scaleEffect(zoom)
                .rotationEffect(.radians(group.rotation))
            
            // Group label (doesn't rotate) - positioned relative to circle
            VStack {
                Text(group.name)
                    .font(.system(size: 12 * zoom, weight: .medium))
                    .foregroundColor(.primary)
                
                Text("\(group.members.count) members")
                    .font(.system(size: 10 * zoom))
                    .foregroundColor(.secondary)
                
                // Debug coordinates
                if showDebugCoordinates {
                    Text("(\(Int(group.center.x)), \(Int(group.center.y)))")
                        .font(.system(size: 8 * zoom, weight: .bold))
                        .foregroundColor(.green)
                }
            }
            .padding(8 * zoom)
            .background(
                RoundedRectangle(cornerRadius: 6 * zoom)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.9))
            )
            
            // Transform handles moved to canvas level for independent rendering and hit-testing
        }
        .contentShape(Ellipse())
        .onTapGesture {
            onTap()
        }
        .dropDestination(for: Contact.self) { contacts, location in
            // Handle dropping contacts into this group
            DragDropLogger.shared.log(
                "GroupCircleContainer received contact drop at local location: \(location)",
                operation: "CONTACT_DROP_RECEIVED"
            )
            
            for contact in contacts {
                // CRITICAL FIX: Transform local coordinates to canvas coordinates
                // The location is in the group's local coordinate space (centered at 0,0)
                // We need to convert it to canvas coordinates before passing to the handler
                let canvasLocation = localToCanvas(location)
                DragDropLogger.shared.log(
                    "Transformed contact drop location from local \(location) to canvas \(canvasLocation)",
                    operation: "COORDINATE_TRANSFORM"
                )
                onContactDrop(contact, canvasLocation)
            }
            return true
        } isTargeted: { isTargeted in
            // Visual feedback when dragging over the group
            if isTargeted {
                DragDropLogger.shared.log(
                    "Contact drag is hovering over group '\(group.name)'",
                    operation: "DROP_TARGET"
                )
            }
        }
        .dropDestination(for: ContactGroup.self) { groups, location in
            // Handle dropping groups onto this group
            DragDropLogger.shared.log(
                "GroupCircleContainer received group drop at local location: \(location)",
                operation: "GROUP_DROP_RECEIVED"
            )
            
            for droppedGroup in groups {
                // CRITICAL FIX: Transform local coordinates to canvas coordinates
                let canvasLocation = localToCanvas(location)
                DragDropLogger.shared.log(
                    "Transformed group drop location from local \(location) to canvas \(canvasLocation)",
                    operation: "COORDINATE_TRANSFORM"
                )
                onGroupDrop(droppedGroup, canvasLocation)
            }
            return true
        } isTargeted: { isTargeted in
            // Visual feedback when dragging a group over this group
            if isTargeted {
                DragDropLogger.shared.log(
                    "Group drag is hovering over group '\(group.name)'",
                    operation: "DROP_TARGET"
                )
            }
        }
        // Drag gesture moved to global coordinate system in CanvasGroupCircleView
        // to ensure consistent behavior with contact dragging
    }
    
    // MARK: - Handle Actions
    
    private func handleLeftResize(delta: CGPoint) {
        // Convert delta to canvas coordinates (accounting for zoom)
        let canvasDelta = CGPoint(x: delta.x / zoom, y: delta.y / zoom)
        let widthChange = -canvasDelta.x // Left handle moves opposite to drag direction
        let newWidth = group.width + widthChange
        
        print("🔧 GroupCircleContainer: handleLeftResize - canvasDelta: \(canvasDelta), widthChange: \(widthChange)")
        print("🔧 GroupCircleContainer: Current group width: \(group.width), newWidth: \(newWidth)")
        print("🔧 GroupCircleContainer: Left resize - keeps right edge and height fixed")
        
        // Left resize: only change width, keep height and right edge position fixed
        onResize(newWidth, group.height)
    }
    
    private func handleRightResize(delta: CGPoint) {
        // Convert delta to canvas coordinates (accounting for zoom)
        let canvasDelta = CGPoint(x: delta.x / zoom, y: delta.y / zoom)
        let widthChange = canvasDelta.x // Right handle moves with drag direction
        let newWidth = group.width + widthChange
        
        print("🔧 GroupCircleContainer: handleRightResize - canvasDelta: \(canvasDelta), widthChange: \(widthChange)")
        print("🔧 GroupCircleContainer: Current group width: \(group.width), newWidth: \(newWidth)")
        print("🔧 GroupCircleContainer: Right resize - keeps left edge and height fixed")
        
        // Right resize: only change width, keep height and left edge position fixed
        onResize(newWidth, group.height)
    }
    
    private func handleTopResize(delta: CGPoint) {
        // Convert delta to canvas coordinates (accounting for zoom)
        let canvasDelta = CGPoint(x: delta.x / zoom, y: delta.y / zoom)
        let heightChange = -canvasDelta.y // Top handle moves opposite to drag direction
        let newHeight = group.height + heightChange
        
        print("🔧 GroupCircleContainer: handleTopResize - canvasDelta: \(canvasDelta), heightChange: \(heightChange)")
        print("🔧 GroupCircleContainer: Current group height: \(group.height), newHeight: \(newHeight)")
        print("🔧 GroupCircleContainer: Top resize - keeps bottom edge and width fixed")
        
        // Top resize: only change height, keep width and bottom edge position fixed
        onResize(group.width, newHeight)
    }
    
    private func handleBottomResize(delta: CGPoint) {
        // Convert delta to canvas coordinates (accounting for zoom)
        let canvasDelta = CGPoint(x: delta.x / zoom, y: delta.y / zoom)
        let heightChange = canvasDelta.y // Bottom handle moves with drag direction
        let newHeight = group.height + heightChange
        
        print("🔧 GroupCircleContainer: handleBottomResize - canvasDelta: \(canvasDelta), heightChange: \(heightChange)")
        print("🔧 GroupCircleContainer: Current group height: \(group.height), newHeight: \(newHeight)")
        print("🔧 GroupCircleContainer: Bottom resize - keeps top edge and width fixed")
        
        // Bottom resize: only change height, keep width and top edge position fixed
        onResize(group.width, newHeight)
    }
    
    // MARK: - Corner Handle Actions
    
    private func handleTopLeftResize(delta: CGPoint) {
        // Convert delta to canvas coordinates (accounting for zoom)
        let canvasDelta = CGPoint(x: delta.x / zoom, y: delta.y / zoom)
        let widthChange = -canvasDelta.x // Top-left: expand left edge
        let heightChange = -canvasDelta.y // Top-left: expand top edge
        let newWidth = group.width + widthChange
        let newHeight = group.height + heightChange
        
        print("🔧 GroupCircleContainer: handleTopLeftResize - canvasDelta: \(canvasDelta)")
        print("🔧 GroupCircleContainer: newWidth: \(newWidth), newHeight: \(newHeight)")
        
        // Top-left resize: keeps bottom-right corner fixed
        onResize(newWidth, newHeight)
    }
    
    private func handleTopRightResize(delta: CGPoint) {
        // Convert delta to canvas coordinates (accounting for zoom)
        let canvasDelta = CGPoint(x: delta.x / zoom, y: delta.y / zoom)
        let widthChange = canvasDelta.x // Top-right: expand right edge
        let heightChange = -canvasDelta.y // Top-right: expand top edge
        let newWidth = group.width + widthChange
        let newHeight = group.height + heightChange
        
        print("🔧 GroupCircleContainer: handleTopRightResize - canvasDelta: \(canvasDelta)")
        print("🔧 GroupCircleContainer: newWidth: \(newWidth), newHeight: \(newHeight)")
        
        // Top-right resize: keeps bottom-left corner fixed
        onResize(newWidth, newHeight)
    }
    
    private func handleBottomLeftResize(delta: CGPoint) {
        // Convert delta to canvas coordinates (accounting for zoom)
        let canvasDelta = CGPoint(x: delta.x / zoom, y: delta.y / zoom)
        let widthChange = -canvasDelta.x // Bottom-left: expand left edge
        let heightChange = canvasDelta.y // Bottom-left: expand bottom edge
        let newWidth = group.width + widthChange
        let newHeight = group.height + heightChange
        
        print("🔧 GroupCircleContainer: handleBottomLeftResize - canvasDelta: \(canvasDelta)")
        print("🔧 GroupCircleContainer: newWidth: \(newWidth), newHeight: \(newHeight)")
        
        // Bottom-left resize: keeps top-right corner fixed
        onResize(newWidth, newHeight)
    }
    
    private func handleBottomRightResize(delta: CGPoint) {
        // Convert delta to canvas coordinates (accounting for zoom)
        let canvasDelta = CGPoint(x: delta.x / zoom, y: delta.y / zoom)
        let widthChange = canvasDelta.x // Bottom-right: expand right edge
        let heightChange = canvasDelta.y // Bottom-right: expand bottom edge
        let newWidth = group.width + widthChange
        let newHeight = group.height + heightChange
        
        print("🔧 GroupCircleContainer: handleBottomRightResize - canvasDelta: \(canvasDelta)")
        print("🔧 GroupCircleContainer: newWidth: \(newWidth), newHeight: \(newHeight)")
        
        // Bottom-right resize: keeps top-left corner fixed
        onResize(newWidth, newHeight)
    }
    
    // MARK: - Rotation Handle Actions
    
    private func handleRotation(delta: CGPoint) {
        // Convert delta to canvas coordinates (accounting for zoom)
        let canvasDelta = CGPoint(x: delta.x / zoom, y: delta.y / zoom)
        
        // Calculate angle based on horizontal movement
        // Positive X movement = clockwise rotation, negative = counter-clockwise
        let rotationSpeed: CGFloat = 0.01 // Adjust sensitivity
        let angleChange = canvasDelta.x * rotationSpeed
        
        print("🔧 GroupCircleContainer: handleRotation - canvasDelta: \(canvasDelta), angleChange: \(angleChange)")
        
        // Apply rotation - this will be handled by the onRotate callback
        onRotate(group.rotation + angleChange)
    }
}

// MARK: - Transform Handle

enum TransformHandleType {
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case rotation
}

struct TransformHandle: View {
    let position: CGPoint
    let handleType: TransformHandleType
    let groupColor: Color
    let zoom: CGFloat
    let onDrag: (CGPoint) -> Void
    let onDragStart: () -> Void
    let onDragEnd: () -> Void
    
    // Custom labels for debugging: t1, t2, t3, l, r, b1, b2, b3, R
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
    
    var body: some View {
        // Create handle at the offset position using a spacer-based layout
        Color.clear
            .frame(width: 30, height: 30)
            .overlay(
                ZStack {
                    // Large debug circle - should be VERY visible
                    Circle()
                        .fill(Color.red.opacity(0.5))
                        .frame(width: 30, height: 30)
                    
                    // Handle background - small circle matching group color
                    Circle()
                        .fill(groupColor)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    
                    // Handle border - white outline for visibility
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 12, height: 12)
                    
                    // Rotation handle gets a special indicator
                    if handleType == .rotation {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 6))
                            .foregroundColor(.white)
                    }
                    
                    // Debug text showing handle type with custom labels
                    Text(handleLabel(for: handleType))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.yellow)
                        .offset(y: -20)
                }
            )
            .offset(x: position.x, y: position.y) // Position handle
            .contentShape(Rectangle()) // Ensure hit area moves with offset
            .allowsHitTesting(true) // CRITICAL: Ensure handle can receive touches
        .onAppear {
            print("🟢🟢🟢 TransformHandle APPEARED: \(handleType) at position \(position), zoom: \(zoom)")
        }
        .onTapGesture {
            print("🔴🔴🔴 TransformHandle: \(handleType) TAP DETECTED at position \(position)")
        }
        .gesture(
            // Use .gesture() instead of .highPriorityGesture() for EXCLUSIVE control
            // This blocks ALL other gestures when the handle is touched
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    print("🔧🔧🔧 TransformHandle: \(handleType) DRAG CHANGED at \(value.location), translation: \(value.translation)")
                    onDragStart() // Notify parent that handle drag started
                    print("🔧 TransformHandle: \(handleType) drag started at \(value.location)")
                    // Pass the raw drag delta - coordinate conversion happens in the handler
                    onDrag(CGPoint(x: value.translation.width, y: value.translation.height))
                }
                .onEnded { _ in
                    print("🔧🔧🔧 TransformHandle: \(handleType) DRAG ENDED")
                    onDragEnd() // Notify parent that handle drag ended
                    print("🔧 TransformHandle: \(handleType) drag ended")
                }
        )
    }
}

#Preview {
    GroupCircleView(group: ContactGroup(name: "Work Team", color: .blue))
        .environmentObject(SelectionManager())
        .environmentObject(SQLiteDataProvider())
}
