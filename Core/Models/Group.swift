import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContactGroup: Identifiable, Hashable, Codable, Transferable {
    var id: UUID
    var name: String
    var color: Color
    var createdAt: Date
    var parentID: UUID?
    var memberPhones: Set<String> // phone as FK
    var linkedGroupIDs: Set<UUID>
    var metadata: GroupMetadata
    var isDeck: Bool
    var canvases: Set<UUID> // Canvas UUIDs where this group exists
    var tags: Set<UUID>
    var childGroupIDs: Set<UUID>
    var parentGroupIDs: Set<UUID>
    var cachedSize: Int
    
    // Store the original hex string for proper color name display
    var colorHexString: String?
    
    // Database integer ID for matching with canvas elements
    var databaseId: Int?
    
    // macOS Contacts group identifier for syncing
    var macOSGroupID: String?
    
    // Computed property for drag & drop compatibility
    var members: [String] {
        get { Array(memberPhones) }
        set {
            memberPhones = Set(newValue)
            cachedSize = memberPhones.count
        }
    }
    
    init(id: UUID = UUID(), name: String, color: Color = .blue, parentID: UUID? = nil, isDeck: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = Date()
        self.parentID = parentID
        self.memberPhones = []
        self.linkedGroupIDs = []
        self.metadata = GroupMetadata()
        self.isDeck = isDeck
        self.canvases = []
        self.colorHexString = color.toHexString()
        self.tags = []
        self.childGroupIDs = []
        self.parentGroupIDs = []
        self.cachedSize = 0
        self.macOSGroupID = nil
    }
    
    // Computed properties
    var memberCount: Int {
        max(cachedSize, memberPhones.count)
    }
    
    var isRoot: Bool {
        parentID == nil
    }
    
    var hasChildren: Bool {
        !linkedGroupIDs.isEmpty
    }
    
    /// Get the display name for the color using the stored hex string
    var colorDisplayName: String {
        if let hexString = colorHexString {
            return getColorNameFromHex(hexString)
        } else {
            return color.displayName
        }
    }
    
    // MARK: - Transferable Implementation
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .crmGroup)
    }
}

struct GroupMetadata: Hashable, Codable {
    var inviteCount: Int = 0
    var interconnectivityScore: Double = 0.0
    
    // Custom coding for Color
    enum CodingKeys: String, CodingKey {
        case inviteCount, interconnectivityScore
    }
    
    init() {
        self.inviteCount = 0
        self.interconnectivityScore = 0.0
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inviteCount = try container.decode(Int.self, forKey: .inviteCount)
        interconnectivityScore = try container.decode(Double.self, forKey: .interconnectivityScore)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inviteCount, forKey: .inviteCount)
        try container.encode(interconnectivityScore, forKey: .interconnectivityScore)
    }
}

// Color Codable extension is now defined in CanvasModels.swift
