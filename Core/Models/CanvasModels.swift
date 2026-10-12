import SwiftUI
import Foundation

// MARK: - Database Canvas Model

struct Canvas: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var elements: [CanvasElement]
    var elementCounts: ElementCounts
    var dateCreated: Date
    var dateUpdated: Date
    var lastSaved: Date?
    var canvasType: CanvasType
    var canvasState: CanvasState
    var metadata: [String: String] // Changed from [String: Any] to [String: String] for Codable conformance
    
    init(id: String = UUID().uuidString, name: String, elements: [CanvasElement] = [], 
         canvasType: CanvasType = .groupMap, canvasState: CanvasState = CanvasState()) {
        self.id = id
        self.name = name
        self.elements = elements
        self.elementCounts = ElementCounts(elements: elements)
        self.dateCreated = Date()
        self.dateUpdated = Date()
        self.lastSaved = nil // Initially null, will be set on first save
        self.canvasType = canvasType
        self.canvasState = canvasState
        self.metadata = [:]
    }
    
    // MARK: - Database Conversion
    
    func toDatabaseFormat() -> [String: Any] {
        var data: [String: Any] = [
            "canvas_id": id,
            "canvas_name": name,
            "canvas_elements": elements.map { $0.toDatabaseFormat() },
            "element_counts": elementCounts.toDatabaseFormat(),
            "date_created": ISO8601DateFormatter().string(from: dateCreated),
            "date_updated": ISO8601DateFormatter().string(from: dateUpdated),
            "canvas_type": canvasType.rawValue,
            "canvas_state": canvasState.toDatabaseFormat(),
            "metadata": metadata
        ]
        
        // Add last_saved if it exists
        if let lastSaved = lastSaved {
            data["last_saved"] = ISO8601DateFormatter().string(from: lastSaved)
        }
        
        return data
    }
    
    static func fromDatabaseFormat(_ data: [String: Any]) -> Canvas? {
        guard let id = data["canvas_id"] as? String,
              let name = data["canvas_name"] as? String,
              let elementsData = data["canvas_elements"] as? [[String: Any]],
              let countsData = data["element_counts"] as? [String: Any],
              let dateCreatedStr = data["date_created"] as? String,
              let dateUpdatedStr = data["date_updated"] as? String,
              let canvasTypeStr = data["canvas_type"] as? String,
              let canvasStateData = data["canvas_state"] as? [String: Any] else {
            return nil
        }
        
        let dateFormatter = ISO8601DateFormatter()
        let dateCreated = dateFormatter.date(from: dateCreatedStr) ?? Date()
        let dateUpdated = dateFormatter.date(from: dateUpdatedStr) ?? Date()
        let canvasType = CanvasType(rawValue: canvasTypeStr) ?? .groupMap
        
        // Parse last_saved if it exists
        let lastSaved: Date?
        if let lastSavedStr = data["last_saved"] as? String {
            lastSaved = dateFormatter.date(from: lastSavedStr)
        } else {
            lastSaved = nil
        }
        
        let elements = elementsData.compactMap { CanvasElement.fromDatabaseFormat($0) }
        let elementCounts = ElementCounts.fromDatabaseFormat(countsData)
        let canvasState = CanvasState.fromDatabaseFormat(canvasStateData)
        let metadata = data["metadata"] as? [String: String] ?? [:]
        
        var canvas = Canvas(
            id: id,
            name: name,
            elements: elements,
            canvasType: canvasType,
            canvasState: canvasState
        )
        canvas.elementCounts = elementCounts
        canvas.dateCreated = dateCreated
        canvas.dateUpdated = dateUpdated
        canvas.lastSaved = lastSaved
        canvas.metadata = metadata
        return canvas
    }
}

// MARK: - Canvas Element

struct CanvasElement: Identifiable, Codable, Equatable {
    let id: String
    var elementType: ElementType
    var location: CGPoint
    var scale: CGFloat
    var width: CGFloat
    var height: CGFloat
    var rotation: CGFloat
    var color: String // Hex color string
    var contactUUID: String? // Contact UUID for contact elements
    var groupUUID: String? // Group UUID for group elements
    
    init(id: String = UUID().uuidString, elementType: ElementType, location: CGPoint = .zero,
         scale: CGFloat = 1.0, width: CGFloat = 60, height: CGFloat = 80, 
         rotation: CGFloat = 0, color: String = "#007AFF", contactUUID: String? = nil, groupUUID: String? = nil) {
        self.id = id
        self.elementType = elementType
        self.location = location
        self.scale = scale
        self.width = width
        self.height = height
        self.rotation = rotation
        self.color = color
        self.contactUUID = contactUUID
        self.groupUUID = groupUUID
    }
    
    // MARK: - Database Conversion
    
    func toDatabaseFormat() -> [String: Any] {
        var data: [String: Any] = [
            "element_id": id,
            "element_type": elementType.rawValue,
            "location": ["x": location.x, "y": location.y],
            "scale": scale,
            "width": width,
            "height": height,
            "rotation": rotation,
            "color": color
        ]
        
        // Add contact UUID if present
        if let contactUUID = contactUUID {
            data["contact_uuid"] = contactUUID
        }
        
        // Add group UUID if present
        if let groupUUID = groupUUID {
            data["group_uuid"] = groupUUID
        }
        
        return data
    }
    
    static func fromDatabaseFormat(_ data: [String: Any]) -> CanvasElement? {
        guard let id = data["element_id"] as? String,
              let elementTypeStr = data["element_type"] as? String,
              let elementType = ElementType(rawValue: elementTypeStr),
              let locationData = data["location"] as? [String: CGFloat],
              let x = locationData["x"],
              let y = locationData["y"],
              let scale = data["scale"] as? CGFloat,
              let width = data["width"] as? CGFloat,
              let height = data["height"] as? CGFloat,
              let rotation = data["rotation"] as? CGFloat,
              let color = data["color"] as? String else {
            return nil
        }
        
        let contactUUID = data["contact_uuid"] as? String
        let groupUUID = data["group_uuid"] as? String
        
        return CanvasElement(
            id: id,
            elementType: elementType,
            location: CGPoint(x: x, y: y),
            scale: scale,
            width: width,
            height: height,
            rotation: rotation,
            color: color,
            contactUUID: contactUUID,
            groupUUID: groupUUID
        )
    }
}

// MARK: - Element Types

enum ElementType: String, CaseIterable, Codable, Equatable {
    case contact = "contact"
    case group = "group"
    case custom = "custom"
}

// MARK: - Canvas Types

enum CanvasType: String, CaseIterable, Codable, Equatable {
    case groupMap = "group_map"
    case contactMap = "contact_map"
    case custom = "custom"
}

// MARK: - Element Counts

struct ElementCounts: Codable, Equatable {
    var contacts: Int
    var groups: Int
    var all: Int
    
    init(contacts: Int = 0, groups: Int = 0, all: Int = 0) {
        self.contacts = contacts
        self.groups = groups
        self.all = all
    }
    
    init(elements: [CanvasElement]) {
        self.contacts = elements.filter { $0.elementType == .contact }.count
        self.groups = elements.filter { $0.elementType == .group }.count
        self.all = elements.count
    }
    
    // MARK: - Database Conversion
    
    func toDatabaseFormat() -> [String: Any] {
        return [
            "contacts": contacts,
            "groups": groups,
            "all": all
        ]
    }
    
    static func fromDatabaseFormat(_ data: [String: Any]) -> ElementCounts {
        return ElementCounts(
            contacts: data["contacts"] as? Int ?? 0,
            groups: data["groups"] as? Int ?? 0,
            all: data["all"] as? Int ?? 0
        )
    }
}

// MARK: - Canvas State Database Extension

extension CanvasState {
    func toDatabaseFormat() -> [String: Any] {
        return [
            "zoom": zoom,
            "pan": ["x": pan.x, "y": pan.y],
            "gridEnabled": gridEnabled,
            "snapToGrid": snapToGrid,
            "gridSize": gridSize,
            "multiSelectMode": multiSelectMode,
            "mode": mode.rawValue,
            "selection": Array(selection).map { $0.uuidString }
        ]
    }
    
    static func fromDatabaseFormat(_ data: [String: Any]) -> CanvasState {
        let zoom = data["zoom"] as? CGFloat ?? 1.0
        let panData = data["pan"] as? [String: CGFloat] ?? ["x": 0, "y": 0]
        let pan = CGPoint(x: panData["x"] ?? 0, y: panData["y"] ?? 0)
        let gridEnabled = data["gridEnabled"] as? Bool ?? false
        let snapToGrid = data["snapToGrid"] as? Bool ?? false
        let gridSize = data["gridSize"] as? CGFloat ?? 8.0
        let multiSelectMode = data["multiSelectMode"] as? Bool ?? false
        let modeString = data["mode"] as? String ?? "select"
        let mode = CanvasMode(rawValue: modeString) ?? .select
        
        let selectionStrings = data["selection"] as? [String] ?? []
        let selection = Set(selectionStrings.compactMap { UUID(uuidString: $0) })
        
        var state = CanvasState(
            zoom: zoom,
            pan: pan,
            gridEnabled: gridEnabled,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            multiSelectMode: multiSelectMode,
            mode: mode
        )
        state.selection = selection
        return state
    }
}

// MARK: - Unified Element Movement

protocol MovableElement {
    var id: UUID { get }
    var position: CGPoint { get set }
}

enum CanvasElementType {
    case contact
    case group
}

struct ElementMovementTarget {
    let contactIds: [UUID]
    let groupIds: [UUID]
    
    var isEmpty: Bool {
        return contactIds.isEmpty && groupIds.isEmpty
    }
    
    init(contactIds: [UUID] = [], groupIds: [UUID] = []) {
        self.contactIds = contactIds
        self.groupIds = groupIds
    }
    
    static func selectedElements(contacts: Set<UUID>, groups: Set<UUID>) -> ElementMovementTarget {
        return ElementMovementTarget(contactIds: Array(contacts), groupIds: Array(groups))
    }
}

// MARK: - Core Models

struct ContactNode: Identifiable, Hashable, Codable, MovableElement {
    var id: UUID
    var name: String
    var phone: String               // phone number for database lookup
    var contactUUID: UUID?          // original contact UUID from database
    var avatarURL: URL?
    var profilePhotoData: Data?     // profile photo data for image display
    var position: CGPoint           // canvas space
    var size: CGSize                // default shows a square avatar
    var isSelected: Bool
    var tags: [String]              // for future filters
    
    init(id: UUID = UUID(), name: String, phone: String = "", contactUUID: UUID? = nil, avatarURL: URL? = nil, profilePhotoData: Data? = nil, position: CGPoint = .zero, size: CGSize = CGSize(width: 60, height: 80), isSelected: Bool = false, tags: [String] = []) {
        self.id = id
        self.name = name
        self.phone = phone
        self.contactUUID = contactUUID
        self.avatarURL = avatarURL
        self.profilePhotoData = profilePhotoData
        self.position = position
        self.size = size
        self.isSelected = isSelected
        self.tags = tags
    }
    
    // Computed property to get NSImage from profile photo data (same as Contact model)
    var profileImage: NSImage? {
        guard let photoData = profilePhotoData else { return nil }
        return NSImage(data: photoData)
    }
    
    // Computed property for initials (same logic as Contact model)
    var initials: String {
        if !name.isEmpty {
            // Use the name field if available
            let components = name.components(separatedBy: " ")
            let initials = components.prefix(2).compactMap { $0.first }
            let result = String(initials).uppercased()
            return result.isEmpty ? "?" : result
        } else {
            // Fallback to phone number (first 2 characters)
            let phoneDigits = phone.filter { $0.isNumber }
            if phoneDigits.count >= 2 {
                return String(phoneDigits.prefix(2))
            } else if phoneDigits.count == 1 {
                return phoneDigits + "?"
            } else {
                return "??"
            }
        }
    }
}

struct GroupCircle: Identifiable, Hashable, Codable, MovableElement {
    var id: UUID
    var name: String
    var center: CGPoint             // canvas space
    var radius: CGFloat             // For backward compatibility - represents average of width/height
    var width: CGFloat              // Width of the group (for oval support)
    var height: CGFloat             // Height of the group (for oval support)
    var color: Color                // group color
    var members: Set<UUID>          // ContactNode ids
    var isSelected: Bool
    var rotation: CGFloat           // rotation in radians
    var databaseId: Int?            // Database ID for direct access
    
    // MovableElement conformance - use center as position
    var position: CGPoint {
        get { center }
        set { center = newValue }
    }
    
    init(id: UUID = UUID(), name: String, center: CGPoint = .zero, radius: CGFloat = 100, color: Color = .blue, members: Set<UUID> = [], isSelected: Bool = false, rotation: CGFloat = 0, databaseId: Int? = nil) {
        self.id = id
        self.name = name
        self.center = center
        self.radius = radius
        self.width = radius * 2     // Initialize width from radius
        self.height = radius * 2    // Initialize height from radius
        self.color = color
        self.members = members
        self.isSelected = isSelected
        self.rotation = rotation
        self.databaseId = databaseId
    }
    
    // Computed property for backward compatibility
    var averageRadius: CGFloat {
        return (width + height) / 4
    }
    
    // Update radius when width/height change
    mutating func updateRadius() {
        radius = (width + height) / 4
    }
}

struct CanvasState: Codable, Equatable {
    var zoom: CGFloat               // 0.02 ... 3.0
    var pan: CGPoint                // translation in view space
    var gridEnabled: Bool
    var snapToGrid: Bool
    var gridSize: CGFloat           // default 8.0
    var multiSelectMode: Bool
    var marqueeRect: CGRect?
    var selection: Set<UUID>        // ids of selected nodes (contacts + groups)
    var mode: CanvasMode            // current canvas mode
    var bounds: CGRect              // canvas bounds in canvas space
    
    init(zoom: CGFloat = 1.0, pan: CGPoint = .zero, gridEnabled: Bool = true, snapToGrid: Bool = false, gridSize: CGFloat = 8.0, multiSelectMode: Bool = false, mode: CanvasMode = .select, bounds: CGRect = CGRect(x: -1000, y: -1000, width: 2000, height: 2000)) {
        self.zoom = zoom
        self.pan = pan
        self.gridEnabled = gridEnabled
        self.snapToGrid = snapToGrid
        self.gridSize = gridSize
        self.multiSelectMode = multiSelectMode
        self.mode = mode
        self.selection = []
        self.bounds = bounds
    }
}

struct GroupMap: Identifiable, Codable {
    var id: UUID
    var name: String
    var contacts: [ContactNode]
    var groups: [GroupCircle]
    var canvasState: CanvasState
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, contacts: [ContactNode] = [], groups: [GroupCircle] = [], canvasState: CanvasState = CanvasState()) {
        self.id = id
        self.name = name
        self.contacts = contacts
        self.groups = groups
        self.canvasState = canvasState
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Drag Context (Removed - will implement new drag system)

// MARK: - Coordinate Transformation

struct CanvasTransform {
    let zoom: CGFloat
    let pan: CGPoint
    
    init(zoom: CGFloat = 1.0, pan: CGPoint = .zero) {
        self.zoom = zoom
        self.pan = pan
    }
    
    // Transform from canvas space to view space
    func canvasToView(_ point: CGPoint) -> CGPoint {
        // Apply zoom scaling
        let scaledPoint = CGPoint(
            x: point.x * zoom,
            y: point.y * zoom
        )
        // Apply pan in view space
        return CGPoint(
            x: scaledPoint.x + pan.x,
            y: scaledPoint.y + pan.y
        )
    }
    
    // Transform from view space to canvas space
    func viewToCanvas(_ point: CGPoint) -> CGPoint {
        // Safety check: prevent division by zero or very small zoom values
        guard zoom > 0.001 else {
            print("⚠️ Warning: Invalid zoom value (\(zoom)) in viewToCanvas, using fallback")
            return CGPoint(x: point.x - pan.x, y: point.y - pan.y)
        }
        
        // Remove pan first
        let unPannedPoint = CGPoint(
            x: point.x - pan.x,
            y: point.y - pan.y
        )
        // Remove zoom scaling
        return CGPoint(
            x: unPannedPoint.x / zoom,
            y: unPannedPoint.y / zoom
        )
    }
    
    // Transform a size from canvas to view space
    func canvasToView(_ size: CGSize) -> CGSize {
        return CGSize(
            width: size.width * zoom,
            height: size.height * zoom
        )
    }
    
    // Transform a size from view to canvas space
    func viewToCanvas(_ size: CGSize) -> CGSize {
        // Safety check: prevent division by zero or very small zoom values
        guard zoom > 0.001 else {
            print("⚠️ Warning: Invalid zoom value (\(zoom)) in viewToCanvas size, using fallback")
            return size
        }
        
        return CGSize(
            width: size.width / zoom,
            height: size.height / zoom
        )
    }
    
    // Transform a rectangle from canvas to view space
    func canvasToView(_ rect: CGRect) -> CGRect {
        let origin = canvasToView(rect.origin)
        let size = canvasToView(rect.size)
        return CGRect(origin: origin, size: size)
    }
    
    // Transform a rectangle from view to canvas space
    func viewToCanvas(_ rect: CGRect) -> CGRect {
        let origin = viewToCanvas(rect.origin)
        let size = viewToCanvas(rect.size)
        return CGRect(origin: origin, size: size)
    }
}

// MARK: - Utility Extensions

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
    
    func snappedToGrid(gridSize: CGFloat) -> CGPoint {
        return CGPoint(
            x: round(x / gridSize) * gridSize,
            y: round(y / gridSize) * gridSize
        )
    }
}

extension CGRect {
    func intersectsWith(_ other: CGRect) -> Bool {
        return self.intersects(other)
    }
    
    var center: CGPoint {
        return CGPoint(x: midX, y: midY)
    }
}



// MARK: - Color Palette

struct ColorPalette {
    static let colors: [Color] = [
        .blue, .green, .orange, .purple, .red, .pink, .yellow, .cyan, .mint, .indigo
    ]
    
    static func randomColor() -> Color {
        return colors.randomElement() ?? .blue
    }
}

// MARK: - Group Management
// Note: Legacy updateGroup() and updateGroupInDatabase() functions removed
// These were unused dead code that relied on deprecated Python scripts

enum GroupOperation: String, CaseIterable {
    case add = "ADD"
    case subtract = "SUBTRACT"
    case update = "UPDATE"
}

// MARK: - Color Extensions

extension Color {
    func toHexString() -> String {
        // Convert SwiftUI Color to hex string
        // This is a simplified implementation - in production you'd want more sophisticated color handling
        switch self {
        case .blue: return "#007AFF"
        case .green: return "#34C759"
        case .orange: return "#FF9500"
        case .purple: return "#AF52DE"
        case .red: return "#FF3B30"
        case .pink: return "#FF2D92"
        case .yellow: return "#FFCC02"
        case .cyan: return "#5AC8FA"
        case .mint: return "#00C7BE"
        case .indigo: return "#5856D6"
        case .brown: return "#8E8E93"
        case .gray: return "#8E8E93"
        default: 
            // For custom colors, try to extract RGB values and convert to hex
            // This is a fallback for colors that don't match the predefined cases
            return "#007AFF" // Default fallback
        }
    }
    
    init?(hex: String) {
        // Convert hex string to SwiftUI Color
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Color Codable Extension
extension Color: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hexString = try container.decode(String.self)
        self = Color(hex: hexString) ?? .blue
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(toHexString())
    }
}
