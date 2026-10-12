import Foundation
import SwiftUI

/// Represents a relationship classification that can link contacts and groups.
struct Relationship: Identifiable, Hashable, Codable {
    /// Stable UUID stored in the database (`relationships.uuid`)
    var id: UUID
    /// Display name of the relationship type
    var name: String
    /// Optional hex color used when rendering relationship chips
    var colorHex: String?
    /// Additional description for the relationship
    var description: String?
    /// Linked contacts by database ID
    var linkedContactIDs: [Int64]
    /// Linked groups by UUID
    var linkedGroupIDs: [UUID]
    /// Optional auto-incremented identifier for debugging
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

