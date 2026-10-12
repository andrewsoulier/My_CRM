import Foundation
import SwiftUI
import AppKit

@MainActor
class HotkeyManager: ObservableObject {
    private var registeredHotkeys: [String: () -> Void] = [:]
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    
    // Canvas-specific properties
    @Published private(set) var navHotkeysEnabled = true
    private var navHotkeyIDs: Set<String> = []
    private var canvasViewModel: GroupsMapViewModel?
    private var canvasGestureCoordinator: CanvasGestureCoordinator?
    private var appState: AppState?
    
    
    init() {
        print("🚨 HotkeyManager.init() called")
        setupKeyMonitor()
    }
    
    deinit {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = keyUpMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    // MARK: - Canvas Integration
    func setCanvasComponents(viewModel: GroupsMapViewModel, gestureCoordinator: CanvasGestureCoordinator) {
        self.canvasViewModel = viewModel
        self.canvasGestureCoordinator = gestureCoordinator
        print("🔧 HotkeyManager: Canvas components set successfully")
    }
    
    func setAppState(_ appState: AppState) {
        self.appState = appState
        print("🔧 HotkeyManager: AppState set successfully")
    }
    
    
    // MARK: - Focus Detection
    private func isFocusOnTextInput() -> Bool {
        // Get the current first responder (the element that has keyboard focus)
        guard let window = NSApp.keyWindow,
              let firstResponder = window.firstResponder else {
            return false
        }
        
        // Check if the first responder is a text field or text view
        if firstResponder is NSTextField || 
           firstResponder is NSTextView ||
           firstResponder is NSSearchField {
            return true
        }
        
        // Check if the first responder is a field editor (used by many text input controls)
        if firstResponder is NSText {
            return true
        }
        
        // Check if we're in a SwiftUI text field by looking at the responder chain
        var responder = firstResponder
        while let nextResponder = responder.nextResponder {
            if nextResponder is NSTextField || 
               nextResponder is NSTextView ||
               nextResponder is NSSearchField {
                return true
            }
            responder = nextResponder
        }
        
        // Additional check: Look for SwiftUI text field hosting views
        // SwiftUI text fields often use NSHostingView with specific class names
        if let hostingView = firstResponder as? NSView {
            let className = String(describing: type(of: hostingView))
            if className.contains("TextField") || 
               className.contains("SearchField") ||
               className.contains("TextEditor") {
                return true
            }
        }
        
        // Check if the current window has any active text input
        if window.fieldEditor(false, for: nil) != nil {
            // If there's a field editor, it means we're in a text input
            return true
        }
        
        return false
    }
    
    private func isFocusOnCanvas() -> Bool {
        // Check if the current focus is on the canvas area
        // This is a more specific check to ensure hotkeys only work when canvas is active
        
        guard let window = NSApp.keyWindow,
              let firstResponder = window.firstResponder else {
            return false
        }
        
        // If focus is on any text input, it's not on canvas
        if isFocusOnTextInput() {
            return false
        }
        
        // Check if the first responder is part of the canvas view hierarchy
        var responder = firstResponder
        while let nextResponder = responder.nextResponder {
            let className = String(describing: type(of: nextResponder))
            if className.contains("Canvas") || 
               className.contains("SimplifiedCanvas") ||
               className.contains("GroupsMap") {
                return true
            }
            responder = nextResponder
        }
        
        // Check if the first responder itself is a canvas-related view
        let firstResponderClassName = String(describing: type(of: firstResponder))
        if firstResponderClassName.contains("Canvas") || 
           firstResponderClassName.contains("SimplifiedCanvas") ||
           firstResponderClassName.contains("GroupsMap") {
            return true
        }
        
        // If no specific canvas responder found, assume canvas focus if no text input
        // and we have a canvas view model and we're on the people maps page
        // This ensures that clicking on the canvas returns focus to it
        if canvasViewModel != nil {
            // Check if we're on the people maps page
            let isOnPeopleMapsPage = appState?.selectedPage == .peopleMaps
            
            if isOnPeopleMapsPage {
                // Additional check: if the window's content view is focused and we're not in a text input,
                // assume we're on the canvas (this handles the case where user clicks on canvas)
                if firstResponder == window.contentView || 
                   firstResponder == window.contentView?.subviews.first {
                    return true
                }
                
                // If we're on people maps page and not in a text input, assume canvas focus
                // This is a fallback to ensure canvas hotkeys work when user clicks on canvas
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Test Functions
    func testDeleteKey() {
        guard let viewModel = canvasViewModel else {
            print("🔧 HotkeyManager: No canvas viewModel available for delete test")
            return
        }
        
        print("🔧 HotkeyManager: Testing delete key functionality")
        print("🔧 Selected contacts count: \(viewModel.selectedContacts.count)")
        print("🔧 Selected groups count: \(viewModel.selectedGroups.count)")
        print("🔧 Total contacts: \(viewModel.contacts.count)")
        print("🔧 Total groups: \(viewModel.groups.count)")
        
        deleteSelection(viewModel: viewModel)
    }
    
    // MARK: - Hotkey Registration
    func register(key: KeyEquivalent, modifiers: EventModifiers = [], action: @escaping () -> Void) {
        let hotkeyID = makeHotkeyID(key: key, modifiers: modifiers)
        registeredHotkeys[hotkeyID] = action
    }
    
    func unregister(key: KeyEquivalent, modifiers: EventModifiers = []) {
        let hotkeyID = makeHotkeyID(key: key, modifiers: modifiers)
        registeredHotkeys.removeValue(forKey: hotkeyID)
        navHotkeyIDs.remove(hotkeyID)
    }
    
    func unregisterAll() {
        registeredHotkeys.removeAll()
        navHotkeyIDs.removeAll()
    }
    
    func enableNavHotkeys() {
        setNavHotkeysEnabled(true)
    }
    
    func disableNavHotkeys() {
        setNavHotkeysEnabled(false)
    }
    
    private func setNavHotkeysEnabled(_ enabled: Bool) {
        guard navHotkeysEnabled != enabled else { return }
        navHotkeysEnabled = enabled
        print("🔧 HotkeyManager: Navigation hotkeys \(enabled ? "enabled" : "disabled")")
    }
    
    // MARK: - Key Monitor Setup
    private func setupKeyMonitor() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            return self?.handleKeyEvent(event) ?? event
        }
        
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            return self?.handleKeyUpEvent(event) ?? event
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        // Only handle specific hotkeys that we know should be intercepted
        // Let everything else pass through for normal text input
        
        // Check if this is a hotkey we should handle
        if shouldInterceptKey(event) {
            print("🔧 HotkeyManager: Intercepting key event - keyCode: \(event.keyCode), character: '\(event.characters ?? "")', modifiers: \(event.modifierFlags)")
            
            let key = KeyEquivalent(character: event.charactersIgnoringModifiers ?? "")
            let modifiers = EventModifiers(rawValue: Int(event.modifierFlags.rawValue))
            let hotkeyID = makeHotkeyID(key: key, modifiers: modifiers)
            
            if let action = registeredHotkeys[hotkeyID] {
                if navHotkeyIDs.contains(hotkeyID) && !navHotkeysEnabled {
                    print("🔧 HotkeyManager: Navigation hotkey ignored (canvas active): \(hotkeyID)")
                    return event
                }
                
                print("🔧 HotkeyManager: Found registered hotkey: \(hotkeyID)")
                action()
                return nil // Consume the event
            }
            
            // Handle canvas-specific hotkeys
            if handleCanvasHotkey(event) {
                print("🔧 HotkeyManager: Handled canvas hotkey")
                return nil // Consume the event
            }
        }
        
        // For all other keys, pass through for normal text input
        return event
    }
    
    private func handleKeyUpEvent(_ event: NSEvent) -> NSEvent? {
        // Handle key up events for canvas (e.g., H key release)
        if handleCanvasKeyUp(event) {
            return nil // Consume the event
        }
        
        return event // Pass through the event
    }
    
    // MARK: - Key Interception Logic
    private func shouldInterceptKey(_ event: NSEvent) -> Bool {
        // Check if focus is on a text field or input element
        if isFocusOnTextInput() {
            print("🔧 HotkeyManager: Focus is on text input, not intercepting key")
            return false
        }
        
        // Check if this is a registered app-level hotkey (with modifiers)
        let key = KeyEquivalent(character: event.charactersIgnoringModifiers ?? "")
        let modifiers = EventModifiers(rawValue: Int(event.modifierFlags.rawValue))
        let hotkeyID = makeHotkeyID(key: key, modifiers: modifiers)
        
        if registeredHotkeys[hotkeyID] != nil {
            if navHotkeyIDs.contains(hotkeyID) && !navHotkeysEnabled {
                print("🔧 HotkeyManager: Navigation hotkey suppressed while canvas focused: \(hotkeyID)")
                return false
            }
            
            print("🔧 HotkeyManager: Found registered app-level hotkey: \(hotkeyID)")
            return true
        }
        
        // For canvas-specific hotkeys, only intercept if focus is on canvas
        if isFocusOnCanvas() && canvasViewModel != nil {
            // Canvas-specific hotkeys (no modifiers)
            switch event.keyCode {
            case 4, 5, 9, 49, 53: // H key, G key, V key, Spacebar, Escape key
                return true
                
            case 51: // Delete/Backspace - only intercept for canvas operations
                if let viewModel = canvasViewModel {
                    let hasSelection = !viewModel.selectedContacts.isEmpty || !viewModel.selectedGroups.isEmpty
                    print("🔧 Delete key interception check - hasSelection: \(hasSelection)")
                    return hasSelection
                }
                print("🔧 Delete key interception check - no canvasViewModel")
                return false
                
            // Arrow keys (for canvas navigation)
            case 123, 124, 125, 126: // Arrow keys
                return true
                
            default:
                return false
            }
        }
        
        return false
    }
    
    // MARK: - Text Field Handling
    private func shouldHandleInTextField(_ event: NSEvent) -> Bool {
        // Only handle specific hotkeys that should work even in text fields
        switch event.keyCode {
        case 53: // Escape key - should work everywhere
            return true
        case 36: // Enter key - should work everywhere
            return true
        case 48: // Tab key - should work everywhere
            return true
        default:
            return false
        }
    }
    
    private func handleSpecificHotkey(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 53: // Escape key
            // Close any open dialogs or clear focus
            if let window = NSApp.keyWindow {
                window.makeFirstResponder(nil)
            }
            return nil // Consume the event
        case 36: // Enter key
            // Let it pass through for normal text field behavior
            return event
        case 48: // Tab key
            // Let it pass through for normal tab behavior
            return event
        default:
            return event // Pass through
        }
    }
    
    // MARK: - Canvas Hotkey Handling
    private func handleCanvasHotkey(_ event: NSEvent) -> Bool {
        guard let viewModel = canvasViewModel else { return false }
        
        switch event.keyCode {
        case 4: // H key - hand mode
            // Always go to hand mode, don't toggle
            if !viewModel.isHandMode {
                viewModel.toggleHandMode()
            }
            return true
            
        case 5: // G key - group mode
            handleGKey(viewModel: viewModel)
            return true
            
        case 9: // V key - selection mode
            viewModel.toggleSelectionMode()
            return true
            
        case 49: // Spacebar - temporary hand/pan mode
            print("🔧 Spacebar pressed - switching to hand mode")
            // Switch to hand mode immediately (only if not already in hand mode)
            if !viewModel.isHandMode {
                viewModel.toggleHandMode()
            }
            // Always consume spacebar to prevent system sounds
            return true
            
        case 53: // Escape key - clear selection or exit modes
            if viewModel.isGroupAddMode {
                viewModel.exitGroupAddMode()
            } else {
                viewModel.clearSelection()
            }
            return true
            
        case 51: // Backspace/Delete
            print("🔧 Delete key detected - calling deleteSelection")
            deleteSelection(viewModel: viewModel)
            return true
            
        case 123, 124, 125, 126: // Arrow keys
            handleArrowKeys(event, viewModel: viewModel)
            return true
            
        default:
            break
        }
        
        return false
    }
    
    private func handleCanvasKeyUp(_ event: NSEvent) -> Bool {
        guard let viewModel = canvasViewModel else { return false }
        
        switch event.keyCode {
        case 4: // H key release - no action needed, just consume to prevent system sounds
            return true
            
        case 49: // Spacebar release - return to selection mode
            print("🔧 Spacebar released - returning to selection mode")
            // Always consume spacebar release to prevent system sounds
            if viewModel.isHandMode {
                // If we're in hand mode, return to selection mode
                viewModel.toggleHandMode() // This will switch back to selection mode
            }
            return true // Always consume to prevent system sounds
            
        default:
            break
        }
        
        return false
    }
    
    // MARK: - Canvas Hotkey Actions
    private func handleGKey(viewModel: GroupsMapViewModel) {
        print("🔧 G key pressed - handling group mode")
        
        // Check if we have selected items
        let hasSelection = !viewModel.selectedContacts.isEmpty || !viewModel.selectedGroups.isEmpty
        print("🔧 Has selection: \(hasSelection)")
        print("🔧 Selected contacts: \(viewModel.selectedContacts.count)")
        print("🔧 Selected groups: \(viewModel.selectedGroups.count)")
        
        if hasSelection {
            // Create group around selected items
            print("🔧 Creating group from selection")
            viewModel.createGroupFromSelection()
        } else {
            // Activate group add mode
            print("🔧 Activating group add mode")
            viewModel.toggleGroupAddMode()
        }
    }
    
    private func duplicateSelection(viewModel: GroupsMapViewModel) {
        let offset: CGFloat = 10
        
        // Duplicate selected contacts
        for contactId in viewModel.selectedContacts {
            if let contact = viewModel.contacts.first(where: { $0.id == contactId }) {
                var newContact = contact
                newContact.id = UUID()
                newContact.position = viewModel.findAvailablePosition(near: CGPoint(
                    x: contact.position.x + offset,
                    y: contact.position.y + offset
                ))
                newContact.isSelected = false
                viewModel.addContact(newContact)
            }
        }
        
        // Duplicate selected groups
        for groupId in viewModel.selectedGroups {
            if let group = viewModel.groups.first(where: { $0.id == groupId }) {
                var newGroup = group
                newGroup.id = UUID()
                newGroup.center = CGPoint(
                    x: group.center.x + offset,
                    y: group.center.y + offset
                )
                newGroup.isSelected = false
                newGroup.members.removeAll() // Clear members for new group
                viewModel.addGroup(newGroup)
            }
        }
    }
    
    private func deleteSelection(viewModel: GroupsMapViewModel) {
        print("🔧 HotkeyManager: deleteSelection called")
        print("🔧 Selected contacts: \(viewModel.selectedContacts.count)")
        print("🔧 Selected groups: \(viewModel.selectedGroups.count)")
        
        // Check if we have any selection
        if viewModel.selectedContacts.isEmpty && viewModel.selectedGroups.isEmpty {
            print("🔧 No selection to delete")
            return
        }
        
        // Delete selected contacts
        for contactId in viewModel.selectedContacts {
            print("🔧 Removing contact: \(contactId)")
            viewModel.removeContact(contactId)
        }
        
        // Delete selected groups
        for groupId in viewModel.selectedGroups {
            print("🔧 Removing group: \(groupId)")
            viewModel.removeGroup(groupId)
        }
        
        print("🔧 Delete operation completed")
    }
    
    private func handleArrowKeys(_ event: NSEvent, viewModel: GroupsMapViewModel) {
        let nudgeAmount: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        
        var delta = CGPoint.zero
        switch event.keyCode {
        case 123: // Left arrow
            delta.x = -nudgeAmount
        case 124: // Right arrow
            delta.x = nudgeAmount
        case 125: // Down arrow
            delta.y = nudgeAmount
        case 126: // Up arrow
            delta.y = -nudgeAmount
        default:
            return
        }
        
        // Use new drag system for movement
        // TODO: Implement keyboard movement with new drag system
    }
    
    // MARK: - Utility Functions
    private func makeHotkeyID(key: KeyEquivalent, modifiers: EventModifiers) -> String {
        let modifierString = modifiers.description
        return "\(modifierString)-\(key.character)"
    }
    
    // MARK: - Predefined Hotkeys
    func registerDefaultHotkeys() {
        // Navigation
        registerNavHotkey(key: KeyEquivalent("w"), modifiers: []) {
            // Toggle PageNavBar - handled by AppState
            NotificationCenter.default.post(name: .toggleNavigation, object: nil)
        }
        
        registerNavHotkey(key: KeyEquivalent(","), modifiers: []) {
            // Collapse all siblings - handled by AppState
        }
        
        registerNavHotkey(key: KeyEquivalent("."), modifiers: []) {
            // Expand all siblings - handled by AppState
        }
        
        // Selection
        register(key: KeyEquivalent("\u{1B}"), modifiers: []) {
            // Clear selection - handled by SelectionManager
        }
        
        register(key: KeyEquivalent("a"), modifiers: [.command]) {
            // Select all - handled by SelectionManager
        }
        
        // Zoom (app-level hotkeys)
        register(key: KeyEquivalent("="), modifiers: [.command]) { [weak self] in
            // Zoom in - handled by canvas if available
            if let viewModel = self?.canvasViewModel {
                viewModel.zoomIn()
            }
        }
        
        register(key: KeyEquivalent("-"), modifiers: [.command]) { [weak self] in
            // Zoom out - handled by canvas if available
            if let viewModel = self?.canvasViewModel {
                viewModel.zoomOut()
            }
        }
        
        register(key: KeyEquivalent("0"), modifiers: [.command]) { [weak self] in
            // Reset zoom - handled by canvas if available
            if let viewModel = self?.canvasViewModel {
                viewModel.resetZoom(viewSize: CGSize(width: 800, height: 600))
            }
        }
        
        // Duplicate (app-level hotkey)
        register(key: KeyEquivalent("d"), modifiers: [.command]) { [weak self] in
            // Duplicate selection - handled by canvas if available
            if let viewModel = self?.canvasViewModel {
                self?.duplicateSelection(viewModel: viewModel)
            }
        }
        
        // Undo/Redo
        register(key: KeyEquivalent("z"), modifiers: [.command]) {
            // Undo
        }
        
        register(key: KeyEquivalent("z"), modifiers: [.command, .shift]) {
            // Redo
        }
        
        // Search
        register(key: KeyEquivalent("f"), modifiers: [.command]) {
            // Focus search
        }
        
        // Settings
        register(key: KeyEquivalent(","), modifiers: [.command]) {
            // Open settings
        }
    }
    
    private func registerNavHotkey(key: KeyEquivalent, modifiers: EventModifiers = [], action: @escaping () -> Void) {
        let hotkeyID = makeHotkeyID(key: key, modifiers: modifiers)
        registeredHotkeys[hotkeyID] = action
        navHotkeyIDs.insert(hotkeyID)
    }
}

// MARK: - EventModifiers Extension
extension EventModifiers {
    var description: String {
        var parts: [String] = []
        
        if contains(.command) {
            parts.append("cmd")
        }
        if contains(.shift) {
            parts.append("shift")
        }
        if contains(.option) {
            parts.append("opt")
        }
        if contains(.control) {
            parts.append("ctrl")
        }
        if contains(.capsLock) {
            parts.append("caps")
        }
        // Note: .function modifier is deprecated in macOS 12.0+
        // Only include if we're on an older macOS version
        #if os(macOS)
        if #available(macOS 12.0, *) {
            // .function modifier is deprecated, skip it
        } else {
            if contains(.function) {
                parts.append("fn")
            }
        }
        #endif
        
        return parts.isEmpty ? "none" : parts.joined(separator: "-")
    }
}

// MARK: - KeyEquivalent Extension
extension KeyEquivalent {
    init(character: String) {
        if let firstChar = character.first {
            self.init(firstChar)
        } else {
            self.init(character: "")
        }
    }
    
    var characterString: String {
        return String(self.character)
    }
}

// MARK: - Global Hotkey Support
extension HotkeyManager {
    func registerGlobalHotkey(key: KeyEquivalent, modifiers: EventModifiers = [], action: @escaping () -> Void) {
        // This would require additional permissions and Carbon framework
        // For now, we'll use local monitoring only
        register(key: key, modifiers: modifiers, action: action)
    }
    
    func requestAccessibilityPermissions() {
        // Check if accessibility permissions are already granted (without prompting)
        let accessibilityEnabled = AXIsProcessTrusted()
        
        if accessibilityEnabled {
            print("✅ HotkeyManager: Accessibility permissions already granted, skipping prompt")
            return
        }
        
        print("⚠️ HotkeyManager: Accessibility permissions not granted, showing prompt")
        
        // Now check with prompt option to show system dialog
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessibilityEnabled {
            // Show alert to user about enabling accessibility
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permissions Required"
                alert.informativeText = "This app needs accessibility permissions to register global hotkeys. Please enable it in System Preferences > Security & Privacy > Privacy > Accessibility."
                alert.addButton(withTitle: "Open System Preferences")
                alert.addButton(withTitle: "Cancel")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
                }
            }
        }
    }
}
