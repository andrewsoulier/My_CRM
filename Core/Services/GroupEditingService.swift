import Foundation
import SwiftUI
import Combine

@MainActor
class GroupEditingService: ObservableObject {
    @Published var isEditingGroup: Bool = false
    @Published var editingGroup: ContactGroup?
    @Published var showingEditDialog: Bool = false
    
    private let logger = LogManager.shared
    
    // DataProvider will be injected from the calling view
    private var dataProvider: SQLiteDataProvider? = nil
    
    // Available colors for group selection
    static let availableColors: [Color] = [
        .blue, .green, .orange, .purple, .red, .pink, 
        .yellow, .cyan, .mint, .indigo, .brown, .gray
    ]
    
    init() {
        // DataProvider will be set via setDataProvider method
    }
    
    /// Set the data provider for database operations
    func setDataProvider(_ dataProvider: SQLiteDataProvider) {
        self.dataProvider = dataProvider
    }
    
    // MARK: - Group Editing Methods
    
    /// Start editing a group - opens the edit dialog
    func startEditingGroup(_ group: ContactGroup) {
        logger.info("🎨 Starting to edit group: \(group.name) (ID: \(group.id))")
        editingGroup = group
        isEditingGroup = true
        showingEditDialog = true
    }
    
    /// Update group name
    func updateGroupName(_ groupId: UUID, newName: String) async throws {
        logger.info("📝 Updating group name for ID: \(groupId) to: \(newName)")
        
        guard let dataProvider = dataProvider,
              let groupIndex = dataProvider.groups.firstIndex(where: { $0.id == groupId }) else {
            logger.error("❌ Group not found for ID: \(groupId)")
            throw GroupEditingError.groupNotFound
        }
        
        // Validate name
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.error("❌ Group name cannot be empty")
            throw GroupEditingError.invalidName
        }
        
        // Check for duplicate names
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingGroup = dataProvider.groups.first { 
            $0.id != groupId && $0.name.lowercased() == trimmedName.lowercased() 
        }
        
        if existingGroup != nil {
            logger.error("❌ Group name '\(trimmedName)' already exists")
            throw GroupEditingError.duplicateName
        }
        
        // Update the group
        var updatedGroup = dataProvider.groups[groupIndex]
        updatedGroup.name = trimmedName
        
        // Save to database
        try await dataProvider.updateGroup(updatedGroup)
        
        logger.info("✅ Successfully updated group name: \(trimmedName)")
        
        // Notify the GlobalCanvasService to refresh canvas group data
        await MainActor.run {
            GlobalCanvasService.shared.refreshCanvasGroupData(groupId: groupId)
        }
    }
    
    /// Update group color
    func updateGroupColor(_ groupId: UUID, newColor: Color) async throws {
        logger.info("🎨 Updating group color for ID: \(groupId) to: \(newColor.toHexString())")
        
        guard let dataProvider = dataProvider,
              let groupIndex = dataProvider.groups.firstIndex(where: { $0.id == groupId }) else {
            logger.error("❌ Group not found for ID: \(groupId)")
            throw GroupEditingError.groupNotFound
        }
        
        // Update the group with proper color hex string handling
        var updatedGroup = dataProvider.groups[groupIndex]
        let newColorHex = newColor.toHexString()
        let currentColorHex = updatedGroup.colorHexString ?? updatedGroup.color.toHexString()
        
        logger.info("🔍 COLOR DEBUG: New color hex: '\(newColorHex)'")
        logger.info("🔍 COLOR DEBUG: Current color hex: '\(currentColorHex)'")
        logger.info("🔍 COLOR DEBUG: Colors are different: \(currentColorHex != newColorHex)")
        
        if currentColorHex != newColorHex {
            updatedGroup.color = newColor
            updatedGroup.colorHexString = newColorHex // Update the stored hex string
            logger.info("🎨 Updating group color from '\(currentColorHex)' to '\(newColorHex)'")
            logger.info("🔍 COLOR DEBUG: Group color updated in memory")
            
            // Save to database and wait for completion
            try await dataProvider.updateGroup(updatedGroup)
            logger.info("✅ Successfully updated group color: \(newColorHex)")
            
            // Wait a moment to ensure database write is fully committed
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            // Notify the GlobalCanvasService to refresh canvas group data
            await MainActor.run {
                GlobalCanvasService.shared.refreshCanvasGroupData(groupId: groupId)
            }
        } else {
            logger.info("🔍 COLOR DEBUG: No color change needed - colors are the same")
        }
    }
    
    /// Update both group name and color in a single operation
    func updateGroup(_ groupId: UUID, name: String?, color: Color?) async throws {
        logger.info("🔄 Updating group (ID: \(groupId)) - name: \(name ?? "nil"), color: \(color?.toHexString() ?? "nil")")
        
        guard let dataProvider = dataProvider,
              let groupIndex = dataProvider.groups.firstIndex(where: { $0.id == groupId }) else {
            logger.error("❌ Group not found for ID: \(groupId)")
            throw GroupEditingError.groupNotFound
        }
        
        var updatedGroup = dataProvider.groups[groupIndex]
        var hasChanges = false
        
        // Update name if provided
        if let newName = name {
            let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw GroupEditingError.invalidName
            }
            
            // Check for duplicate names
            let existingGroup = dataProvider.groups.first { 
                $0.id != groupId && $0.name.lowercased() == trimmedName.lowercased() 
            }
            
            if existingGroup != nil {
                throw GroupEditingError.duplicateName
            }
            
            if updatedGroup.name != trimmedName {
                updatedGroup.name = trimmedName
                hasChanges = true
            }
        }
        
        // Update color if provided
        if let newColor = color {
            let newColorHex = newColor.toHexString()
            let currentColorHex = updatedGroup.colorHexString ?? updatedGroup.color.toHexString()
            
            logger.info("🔍 COLOR DEBUG: New color provided: \(newColor)")
            logger.info("🔍 COLOR DEBUG: New color hex: '\(newColorHex)'")
            logger.info("🔍 COLOR DEBUG: Current color hex: '\(currentColorHex)'")
            logger.info("🔍 COLOR DEBUG: Colors are different: \(currentColorHex != newColorHex)")
            
            if currentColorHex != newColorHex {
                updatedGroup.color = newColor
                updatedGroup.colorHexString = newColorHex // Update the stored hex string
                hasChanges = true
                logger.info("🎨 Updating group color from '\(currentColorHex)' to '\(newColorHex)'")
                logger.info("🔍 COLOR DEBUG: Group color updated in memory, hasChanges = \(hasChanges)")
            } else {
                logger.info("🔍 COLOR DEBUG: No color change needed - colors are the same")
            }
        } else {
            logger.info("🔍 COLOR DEBUG: No new color provided")
        }
        
        // Save to database only if there are changes
        if hasChanges {
            // Save to database and wait for completion
            try await dataProvider.updateGroup(updatedGroup)
            logger.info("✅ Successfully updated group: \(updatedGroup.name)")
            
            // Wait a moment to ensure database write is fully committed
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            // Notify the GlobalCanvasService to refresh canvas group data
            await MainActor.run {
                GlobalCanvasService.shared.refreshCanvasGroupData(groupId: groupId)
            }
        } else {
            logger.info("ℹ️ No changes detected for group: \(updatedGroup.name)")
        }
    }
    
    /// Cancel editing
    func cancelEditing() {
        logger.info("❌ Cancelling group editing")
        isEditingGroup = false
        editingGroup = nil
        showingEditDialog = false
    }
    
    /// Finish editing and close dialog
    func finishEditing() {
        logger.info("✅ Finishing group editing")
        isEditingGroup = false
        editingGroup = nil
        showingEditDialog = false
    }
    
    // MARK: - Helper Methods
    
    /// Get group by ID
    func getGroup(by id: UUID) -> ContactGroup? {
        return dataProvider?.groups.first { $0.id == id }
    }
    
    /// Check if a group name is available
    func isGroupNameAvailable(_ name: String, excludingGroupId: UUID? = nil) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !(dataProvider?.groups.contains { 
            $0.id != excludingGroupId && $0.name.lowercased() == trimmedName 
        } ?? false)
    }
}

// MARK: - Group Editing Errors

enum GroupEditingError: LocalizedError {
    case groupNotFound
    case invalidName
    case duplicateName
    case databaseError(String)
    
    var errorDescription: String? {
        switch self {
        case .groupNotFound:
            return "Group not found"
        case .invalidName:
            return "Group name cannot be empty"
        case .duplicateName:
            return "A group with this name already exists"
        case .databaseError(let message):
            return "Database error: \(message)"
        }
    }
}

// MARK: - Color Extensions for Group Editing

extension Color {
    /// Get a display-friendly name for the color
    var displayName: String {
        // Try to get the hex string from the color
        let hexString = self.toHexString()
        
        // Compare by hex string to handle colors loaded from database
        switch hexString {
        case "#007AFF": return "Blue"
        case "#34C759": return "Green"
        case "#FF9500": return "Orange"
        case "#AF52DE": return "Purple"
        case "#FF3B30": return "Red"
        case "#FF2D92": return "Pink"
        case "#FFCC02": return "Yellow"
        case "#5AC8FA": return "Cyan"
        case "#00C7BE": return "Mint"
        case "#5856D6": return "Indigo"
        case "#8E8E93": return "Gray" // Both brown and gray use the same hex
        default: 
            // If the toHexString() method doesn't work properly, try a different approach
            // This handles colors created from hex strings that don't match predefined colors
            return self.getColorNameFromHex()
        }
    }
    
    /// Get color name by trying to match against known hex values
    private func getColorNameFromHex() -> String {
        // This is a fallback method for colors that don't match predefined SwiftUI colors
        // We'll try to extract the hex value using a different approach
        
        // For now, return "Custom" as a fallback
        // In a more sophisticated implementation, you could use NSColor to extract the hex value
        return "Custom"
    }
}

// MARK: - Helper function for getting color name from hex string
func getColorNameFromHex(_ hexString: String) -> String {
    switch hexString {
    case "#007AFF": return "Blue"
    case "#34C759": return "Green"
    case "#FF9500": return "Orange"
    case "#AF52DE": return "Purple"
    case "#FF3B30": return "Red"
    case "#FF2D92": return "Pink"
    case "#FFCC02": return "Yellow"
    case "#5AC8FA": return "Cyan"
    case "#00C7BE": return "Mint"
    case "#5856D6": return "Indigo"
    case "#8E8E93": return "Gray"
    default: return "Custom"
    }
}
