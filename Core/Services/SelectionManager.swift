import Foundation
import SwiftUI

@MainActor
class SelectionManager: ObservableObject {
    @Published var selectedContacts: Set<String> = []
    @Published var selectedGroups: Set<UUID> = []

    
    @Published var lastSelectionTime: Date = Date()
    @Published var selectionMode: SelectionMode = .multiple
    @Published var lastSelectedContact: String?
    @Published var focusedContactIndex: Int = 0
    
    init() {
        print("🚨 SelectionManager.init() called")
    }
    
    // Contact list context for range selection
    @Published var contactListContext: [String] = []
    
    enum SelectionMode {
        case single
        case multiple
        case range
    }
    
    // MARK: - Contact List Context
    func updateContactListContext(_ contacts: [String]) {
        contactListContext = contacts
    }
    
    func setFocusedContact(_ phone: String) {
        if let index = contactListContext.firstIndex(of: phone) {
            focusedContactIndex = index
        }
    }
    
    // MARK: - Contact Selection
    func selectContact(_ phone: String, modifiers: EventModifiers = []) {
        // Update focused contact
        setFocusedContact(phone)
        
        if modifiers.contains(.command) || modifiers.contains(.option) {
            // Command+click or Option+click: toggle selection
            toggleContactSelection(phone)
            lastSelectedContact = phone
        } else if modifiers.contains(.shift) {
            // Shift+click: range selection (clears existing selections)
            selectContactRange(to: phone)
        } else {
            // Regular click: single selection
            clearContactSelection()
            selectedContacts.insert(phone)
            lastSelectedContact = phone
        }
        
        lastSelectionTime = Date()
    }
    
    func deselectContact(_ phone: String) {
        selectedContacts.remove(phone)
    }
    
    func toggleContactSelection(_ phone: String) {
        if selectedContacts.contains(phone) {
            selectedContacts.remove(phone)
        } else {
            selectedContacts.insert(phone)
        }
    }
    
    func selectContacts(_ phones: [String]) {
        selectedContacts.formUnion(phones)
    }
    
    func clearContactSelection() {
        selectedContacts.removeAll()
    }
    
    func isContactSelected(_ phone: String) -> Bool {
        selectedContacts.contains(phone)
    }
    
    func getSelectedContacts() -> [String] {
        Array(selectedContacts)
    }
    
    var selectedPhones: [String] {
        Array(selectedContacts)
    }
    
    // MARK: - Group Selection
    @Published var lastSelectedGroup: UUID?
    @Published var groupListContext: [UUID] = []
    @Published var focusedGroupIndex: Int = 0
    
    func updateGroupListContext(_ groups: [UUID]) {
        groupListContext = groups
    }
    
    func selectGroup(_ groupID: UUID, modifiers: EventModifiers = []) {
        if modifiers.contains(.command) || modifiers.contains(.option) {
            // Command+click or Option+click: toggle selection
            toggleGroupSelection(groupID)
            lastSelectedGroup = groupID
        } else if modifiers.contains(.shift) {
            // Shift+click: range selection (clears existing selections)
            selectGroupRange(to: groupID)
        } else {
            // Regular click: single selection
            clearGroupSelection()
            selectedGroups.insert(groupID)
            lastSelectedGroup = groupID
        }
    }
    
    func deselectGroup(_ groupID: UUID) {
        selectedGroups.remove(groupID)
    }
    
    func clearGroupSelection() {
        selectedGroups.removeAll()
    }
    
    func isGroupSelected(_ groupID: UUID) -> Bool {
        selectedGroups.contains(groupID)
    }
    
    func getSelectedGroups() -> [UUID] {
        Array(selectedGroups)
    }
    
    func toggleGroupSelection(_ groupID: UUID) {
        if selectedGroups.contains(groupID) {
            selectedGroups.remove(groupID)
        } else {
            selectedGroups.insert(groupID)
        }
    }
    
    // MARK: - Range Selection
    private func selectGroupRange(to endGroupID: UUID) {
        guard !groupListContext.isEmpty else {
            selectedGroups.insert(endGroupID)
            return
        }
        
        let startGroupID = lastSelectedGroup ?? endGroupID
        
        guard let startIndex = groupListContext.firstIndex(of: startGroupID),
              let endIndex = groupListContext.firstIndex(of: endGroupID) else {
            selectedGroups.insert(endGroupID)
            return
        }
        
        let minIndex = min(startIndex, endIndex)
        let maxIndex = max(startIndex, endIndex)
        
        // Clear current selection and select range
        clearGroupSelection()
        
        for i in minIndex...maxIndex {
            selectedGroups.insert(groupListContext[i])
        }
        
        lastSelectedGroup = endGroupID
    }

    
    private func selectContactRange(to endPhone: String) {
        guard !contactListContext.isEmpty else {
            selectedContacts.insert(endPhone)
            return
        }
        
        let startPhone = lastSelectedContact ?? endPhone
        
        guard let startIndex = contactListContext.firstIndex(of: startPhone),
              let endIndex = contactListContext.firstIndex(of: endPhone) else {
            selectedContacts.insert(endPhone)
            return
        }
        
        let minIndex = min(startIndex, endIndex)
        let maxIndex = max(startIndex, endIndex)
        
        // Clear current selection and select range
        clearContactSelection()
        
        for i in minIndex...maxIndex {
            selectedContacts.insert(contactListContext[i])
        }
        
        lastSelectedContact = endPhone
    }
    
    // MARK: - Keyboard Navigation
    func moveFocusUp(modifiers: EventModifiers = []) {
        guard !contactListContext.isEmpty else { return }
        
        if modifiers.contains(.command) && modifiers.contains(.shift) {
            // Cmd+Shift+Up: Extend selection to top
            extendSelectionToTop()
        } else if modifiers.contains(.shift) {
            // Shift+Up: Extend selection up one
            extendSelectionUp()
        } else if modifiers.contains(.command) {
            // Cmd+Up: Move to top
            moveFocusToTop()
        } else {
            // Up: Move focus up one
            moveFocusUpOne()
        }
    }
    
    func moveFocusDown(modifiers: EventModifiers = []) {
        guard !contactListContext.isEmpty else { return }
        
        if modifiers.contains(.command) && modifiers.contains(.shift) {
            // Cmd+Shift+Down: Extend selection to bottom
            extendSelectionToBottom()
        } else if modifiers.contains(.shift) {
            // Shift+Down: Extend selection down one
            extendSelectionDown()
        } else if modifiers.contains(.command) {
            // Cmd+Down: Move to bottom
            moveFocusToBottom()
        } else {
            // Down: Move focus down one
            moveFocusDownOne()
        }
    }
    
    private func moveFocusUpOne() {
        if focusedContactIndex > 0 {
            focusedContactIndex -= 1
            let phone = contactListContext[focusedContactIndex]
            clearContactSelection()
            selectedContacts.insert(phone)
            lastSelectedContact = phone
        }
    }
    
    private func moveFocusDownOne() {
        if focusedContactIndex < contactListContext.count - 1 {
            focusedContactIndex += 1
            let phone = contactListContext[focusedContactIndex]
            clearContactSelection()
            selectedContacts.insert(phone)
            lastSelectedContact = phone
        }
    }
    
    private func moveFocusToTop() {
        focusedContactIndex = 0
        let phone = contactListContext[focusedContactIndex]
        clearContactSelection()
        selectedContacts.insert(phone)
        lastSelectedContact = phone
    }
    
    private func moveFocusToBottom() {
        focusedContactIndex = contactListContext.count - 1
        let phone = contactListContext[focusedContactIndex]
        clearContactSelection()
        selectedContacts.insert(phone)
        lastSelectedContact = phone
    }
    
    private func extendSelectionUp() {
        if focusedContactIndex > 0 {
            let newIndex = focusedContactIndex - 1
            let phone = contactListContext[newIndex]
            
            if let lastPhone = lastSelectedContact,
               let lastIndex = contactListContext.firstIndex(of: lastPhone) {
                // Select range from last selected to new position
                let minIndex = min(lastIndex, newIndex)
                let maxIndex = max(lastIndex, newIndex)
                
                clearContactSelection()
                for i in minIndex...maxIndex {
                    selectedContacts.insert(contactListContext[i])
                }
            } else {
                selectedContacts.insert(phone)
            }
            
            focusedContactIndex = newIndex
        }
    }
    
    private func extendSelectionDown() {
        if focusedContactIndex < contactListContext.count - 1 {
            let newIndex = focusedContactIndex + 1
            let phone = contactListContext[newIndex]
            
            if let lastPhone = lastSelectedContact,
               let lastIndex = contactListContext.firstIndex(of: lastPhone) {
                // Select range from last selected to new position
                let minIndex = min(lastIndex, newIndex)
                let maxIndex = max(lastIndex, newIndex)
                
                clearContactSelection()
                for i in minIndex...maxIndex {
                    selectedContacts.insert(contactListContext[i])
                }
            } else {
                selectedContacts.insert(phone)
            }
            
            focusedContactIndex = newIndex
        }
    }
    
    private func extendSelectionToTop() {
        if let lastPhone = lastSelectedContact,
           let lastIndex = contactListContext.firstIndex(of: lastPhone) {
            clearContactSelection()
            for i in 0...lastIndex {
                selectedContacts.insert(contactListContext[i])
            }
            focusedContactIndex = 0
        }
    }
    
    private func extendSelectionToBottom() {
        if let lastPhone = lastSelectedContact,
           let lastIndex = contactListContext.firstIndex(of: lastPhone) {
            clearContactSelection()
            for i in lastIndex..<contactListContext.count {
                selectedContacts.insert(contactListContext[i])
            }
            focusedContactIndex = contactListContext.count - 1
        }
    }
    
    // MARK: - Keyboard Shortcuts
    func handleKeyPress(_ key: KeyEquivalent, modifiers: EventModifiers) {
        switch key {
        case .escape:
            clearAllSelections()
        case KeyEquivalent("a"):
            if modifiers.contains(.command) {
                selectAllContacts()
            }
        case .upArrow:
            moveFocusUp(modifiers: modifiers)
        case .downArrow:
            moveFocusDown(modifiers: modifiers)
        default:
            break
        }
    }
    
    // MARK: - Utility Methods
    func clearAllSelections() {
        clearContactSelection()
        clearGroupSelection()
    }
    
    func selectAllContacts() {
        selectedContacts = Set(contactListContext)
        if !contactListContext.isEmpty {
            lastSelectedContact = contactListContext.last
        }
    }
    
    func hasSelection() -> Bool {
        return !selectedContacts.isEmpty || !selectedGroups.isEmpty
    }
    
    func getSelectionCount() -> Int {
        return selectedContacts.count + selectedGroups.count
    }
    
    // MARK: - Selection State
    func setSelectionMode(_ mode: SelectionMode) {
        selectionMode = mode
    }
    
    func isInMultiSelectMode() -> Bool {
        return selectionMode == .multiple || selectionMode == .range
    }
}

// MARK: - Extensions for SwiftUI Integration
extension SelectionManager {
    func handleContactTap(_ phone: String, modifiers: EventModifiers = []) {
        selectContact(phone, modifiers: modifiers)
    }
    
    func handleGroupTap(_ groupID: UUID, modifiers: EventModifiers = []) {
        selectGroup(groupID, modifiers: modifiers)
    }
    

}
