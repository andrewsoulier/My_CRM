import Foundation
import SwiftUI

/// Represents a user-defined tag that can be attached to contacts or groups.
struct Tag: Identifiable, Hashable, Codable {
    /// Stable UUID used across the app and database (`tags.uuid`)
    var id: UUID
    /// Display name for the tag
    var name: String
    /// Optional hex string used to render the tag color in chips
    var colorHex: String?
    /// Additional description supplied by the user
    var description: String?
    /// Linked contact identifiers (database row IDs)
    var linkedContactIDs: [Int64]
    /// Linked group identifiers
    var linkedGroupIDs: [UUID]
    /// Internal auto-incremented identifier (optional)
    var databaseId: Int64?
    
    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String? = nil,
        description: String? = nil,
        linkedContactIDs: [Int64] = [],
        linkedGroupIDs: [UUID] = [],
        databaseId: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.description = description
        self.linkedContactIDs = linkedContactIDs
        self.linkedGroupIDs = linkedGroupIDs
        self.databaseId = databaseId
    }
}

