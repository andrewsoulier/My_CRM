import Foundation

// MARK: - Smart Chip Models

/// Metadata container for smart chips in message templates
struct ChipMetadata: Codable {
    let chips: [SmartChip]
    let version: String
    
    init(chips: [SmartChip] = [], version: String = "2.0") {
        self.chips = chips
        self.version = version
    }
}

/// Individual smart chip definition
struct SmartChip: Codable, Identifiable {
    let id: String // chipId
    let type: ChipType
    let startIndex: Int
    let endIndex: Int
    let displayText: String
    let field: String? // Only for contact_field type
    let metadata: [String: AnyCodable]
    
    init(
        type: ChipType,
        startIndex: Int,
        endIndex: Int,
        displayText: String,
        field: String? = nil,
        metadata: [String: Any] = [:]
    ) {
        self.id = "chip_\(UUID().uuidString.prefix(8))"
        self.type = type
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.displayText = displayText
        self.field = field
        self.metadata = metadata.mapValues { AnyCodable($0) }
    }
}

/// Supported chip types
enum ChipType: String, Codable, CaseIterable {
    case contactField = "contact_field"
    case image = "image"
    case link = "link"
    case datetime = "datetime"
    case variable = "variable"
    case attachment = "attachment"
    
    var displayName: String {
        switch self {
        case .contactField: return "Contact Field"
        case .image: return "Image"
        case .link: return "Link"
        case .datetime: return "Date/Time"
        case .variable: return "Variable"
        case .attachment: return "Attachment"
        }
    }
    
    var icon: String {
        switch self {
        case .contactField: return "person.fill"
        case .image: return "photo.fill"
        case .link: return "link"
        case .datetime: return "calendar"
        case .variable: return "textformat.abc"
        case .attachment: return "doc.fill"
        }
    }
    
    var defaultColor: String {
        switch self {
        case .contactField: return "blue"
        case .image: return "green"
        case .link: return "purple"
        case .datetime: return "orange"
        case .variable: return "teal"
        case .attachment: return "gray"
        }
    }
}

#if canImport(AppKit)
import AppKit

extension ChipType {
    /// Returns the NSColor for this chip type
    var nsColor: NSColor {
        switch self {
        case .contactField: return .systemBlue
        case .image: return .systemGreen
        case .link: return .systemPurple
        case .datetime: return .systemOrange
        case .variable: return .systemTeal
        case .attachment: return .systemGray
        }
    }
}
#endif

// MARK: - Chip Type Specific Metadata

/// Metadata for image chips
struct ImageChipMetadata: Codable {
    let imageUrl: String
    let altText: String?
    let width: Int?
    let height: Int?
    let alignment: String? // "left", "center", "right"
    
    init(
        imageUrl: String,
        altText: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        alignment: String? = "center"
    ) {
        self.imageUrl = imageUrl
        self.altText = altText
        self.width = width
        self.height = height
        self.alignment = alignment
    }
}

/// Metadata for link chips
struct LinkChipMetadata: Codable {
    let url: String
    let displayText: String?
    let openInNewTab: Bool?
    let style: String? // "text" or "button"
    
    init(
        url: String,
        displayText: String? = nil,
        openInNewTab: Bool? = true,
        style: String? = "text"
    ) {
        self.url = url
        self.displayText = displayText
        self.openInNewTab = openInNewTab
        self.style = style
    }
}

/// Metadata for datetime chips
struct DateTimeChipMetadata: Codable {
    let format: String // e.g., "MMM dd, yyyy", "HH:mm"
    let timezone: String?
    let defaultValue: String? // "now", "tomorrow", "next_week", etc.
    
    init(
        format: String,
        timezone: String? = nil,
        defaultValue: String? = "now"
    ) {
        self.format = format
        self.timezone = timezone
        self.defaultValue = defaultValue
    }
}

/// Metadata for variable chips
struct VariableChipMetadata: Codable {
    let variableName: String
    let defaultValue: String?
    let editable: Bool?
    
    init(
        variableName: String,
        defaultValue: String? = nil,
        editable: Bool? = true
    ) {
        self.variableName = variableName
        self.defaultValue = defaultValue
        self.editable = editable
    }
}

/// Metadata for attachment chips
struct AttachmentChipMetadata: Codable {
    let filePath: String
    let fileName: String
    let fileSize: Int?
    let mimeType: String?
    
    init(
        filePath: String,
        fileName: String,
        fileSize: Int? = nil,
        mimeType: String? = nil
    ) {
        self.filePath = filePath
        self.fileName = fileName
        self.fileSize = fileSize
        self.mimeType = mimeType
    }
}

// MARK: - AnyCodable Helper

/// Allows encoding/decoding of Any type for flexible metadata
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
}

// MARK: - Smart Chip Utilities

extension SmartChip {
    /// Creates a contact field chip
    static func contactField(
        field: String,
        startIndex: Int,
        endIndex: Int,
        displayText: String
    ) -> SmartChip {
        return SmartChip(
            type: .contactField,
            startIndex: startIndex,
            endIndex: endIndex,
            displayText: displayText,
            field: field
        )
    }
    
    /// Creates an image chip
    static func image(
        startIndex: Int,
        endIndex: Int,
        displayText: String,
        metadata: ImageChipMetadata
    ) -> SmartChip {
        let metadataDict = try! JSONDecoder().decode([String: AnyCodable].self, from: JSONEncoder().encode(metadata))
        return SmartChip(
            type: .image,
            startIndex: startIndex,
            endIndex: endIndex,
            displayText: displayText,
            metadata: metadataDict
        )
    }
    
    /// Creates a link chip
    static func link(
        startIndex: Int,
        endIndex: Int,
        displayText: String,
        metadata: LinkChipMetadata
    ) -> SmartChip {
        let metadataDict = try! JSONDecoder().decode([String: AnyCodable].self, from: JSONEncoder().encode(metadata))
        return SmartChip(
            type: .link,
            startIndex: startIndex,
            endIndex: endIndex,
            displayText: displayText,
            metadata: metadataDict
        )
    }
    
    /// Creates a datetime chip
    static func datetime(
        startIndex: Int,
        endIndex: Int,
        displayText: String,
        metadata: DateTimeChipMetadata
    ) -> SmartChip {
        let metadataDict = try! JSONDecoder().decode([String: AnyCodable].self, from: JSONEncoder().encode(metadata))
        return SmartChip(
            type: .datetime,
            startIndex: startIndex,
            endIndex: endIndex,
            displayText: displayText,
            metadata: metadataDict
        )
    }
    
    /// Creates a variable chip
    static func variable(
        startIndex: Int,
        endIndex: Int,
        displayText: String,
        metadata: VariableChipMetadata
    ) -> SmartChip {
        let metadataDict = try! JSONDecoder().decode([String: AnyCodable].self, from: JSONEncoder().encode(metadata))
        return SmartChip(
            type: .variable,
            startIndex: startIndex,
            endIndex: endIndex,
            displayText: displayText,
            metadata: metadataDict
        )
    }
    
    /// Creates an attachment chip
    static func attachment(
        startIndex: Int,
        endIndex: Int,
        displayText: String,
        metadata: AttachmentChipMetadata
    ) -> SmartChip {
        let metadataDict = try! JSONDecoder().decode([String: AnyCodable].self, from: JSONEncoder().encode(metadata))
        return SmartChip(
            type: .attachment,
            startIndex: startIndex,
            endIndex: endIndex,
            displayText: displayText,
            metadata: metadataDict
        )
    }
}
