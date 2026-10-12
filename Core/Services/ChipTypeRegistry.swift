import Foundation
import SwiftUI

/// Registry for managing different chip types, their parsing, display, and validation
class ChipTypeRegistry: ObservableObject {
    static let shared = ChipTypeRegistry()
    
    private let logger = LogManager.shared
    
    private init() {
        setupChipTypes()
    }
    
    // MARK: - Chip Type Definitions
    
    private var chipTypes: [ChipType: ChipTypeHandler] = [:]
    
    private func setupChipTypes() {
        chipTypes[.contactField] = ContactFieldHandler()
        chipTypes[.image] = ImageChipHandler()
        chipTypes[.link] = LinkChipHandler()
        chipTypes[.datetime] = DateTimeChipHandler()
        chipTypes[.variable] = VariableChipHandler()
        chipTypes[.attachment] = AttachmentChipHandler()
    }
    
    // MARK: - Public Interface
    
    /// Get handler for a specific chip type
    func handler(for type: ChipType) -> ChipTypeHandler? {
        return chipTypes[type]
    }
    
    /// Parse a chip from text and metadata
    func parseChip(
        type: ChipType,
        displayText: String,
        metadata: [String: Any]
    ) -> SmartChip? {
        guard let handler = handler(for: type) else {
            logger.error("❌ ChipTypeRegistry: No handler found for type \(type.rawValue)")
            return nil
        }
        
        return handler.parseChip(displayText: displayText, metadata: metadata)
    }
    
    /// Validate chip metadata
    func validateChip(_ chip: SmartChip) -> ChipValidationResult {
        guard let handler = handler(for: chip.type) else {
            return ChipValidationResult(isValid: false, errors: ["Unknown chip type: \(chip.type.rawValue)"])
        }
        
        return handler.validate(chip)
    }
    
    /// Create chip UI view
    func createChipView(_ chip: SmartChip) -> AnyView {
        guard let handler = handler(for: chip.type) else {
            return AnyView(
                Text(chip.displayText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(4)
            )
        }
        
        return handler.createChipView(chip)
    }
    
    /// Get available fields for contact field chips
    func getAvailableContactFields() -> [String] {
        return [
            "name", "first_name", "last_name", "phone", "email",
            "business", "address", "birthday", "contact_group", "notes"
        ]
    }
    
    /// Generate next chip identifier for a given type
    func generateChipIdentifier(for type: ChipType, in text: String) -> String {
        guard let handler = handler(for: type) else {
            return "@\(type.rawValue)_\(UUID().uuidString.prefix(4))"
        }
        
        return handler.generateIdentifier(in: text)
    }
    
    /// Parse existing text to find and create chips
    func parseExistingChips(in text: String) -> [SmartChip] {
        var chips: [SmartChip] = []
        
        // Parse contact field chips (@name, @phone, etc.)
        let contactFields = getAvailableContactFields()
        let contactFieldPattern = "@(\\w+)"
        
        do {
            let regex = try NSRegularExpression(pattern: contactFieldPattern, options: [])
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
            
            for match in matches {
                let fieldRange = match.range(at: 1)
                if fieldRange.location != NSNotFound {
                    let fieldName = (text as NSString).substring(with: fieldRange)
                    if contactFields.contains(fieldName) {
                        let fullMatchRange = match.range(at: 0)
                        let chip = SmartChip.contactField(
                            field: fieldName,
                            startIndex: fullMatchRange.location,
                            endIndex: fullMatchRange.location + fullMatchRange.length,
                            displayText: (text as NSString).substring(with: fullMatchRange)
                        )
                        chips.append(chip)
                    }
                }
            }
        } catch {
            logger.error("❌ ChipTypeRegistry: Error parsing contact field chips: \(error)")
        }
        
        // Parse other chip types based on their patterns
        for (type, handler) in chipTypes {
            if type != .contactField {
                let handlerChips = handler.parseExistingChips(in: text)
                chips.append(contentsOf: handlerChips)
            }
        }
        
        return chips.sorted { $0.startIndex < $1.startIndex }
    }
}

// MARK: - Chip Type Handler Protocol

protocol ChipTypeHandler {
    func parseChip(displayText: String, metadata: [String: Any]) -> SmartChip?
    func validate(_ chip: SmartChip) -> ChipValidationResult
    func createChipView(_ chip: SmartChip) -> AnyView
    func generateIdentifier(in text: String) -> String
    func parseExistingChips(in text: String) -> [SmartChip]
}

// MARK: - Chip Validation Result

struct ChipValidationResult {
    let isValid: Bool
    let errors: [String]
    
    init(isValid: Bool, errors: [String] = []) {
        self.isValid = isValid
        self.errors = errors
    }
}

// MARK: - Contact Field Handler

class ContactFieldHandler: ChipTypeHandler {
    private let availableFields = [
        "name", "first_name", "last_name", "phone", "email",
        "business", "address", "birthday", "contact_group", "notes"
    ]
    
    func parseChip(displayText: String, metadata: [String: Any]) -> SmartChip? {
        // Extract field name from @field format
        guard displayText.hasPrefix("@") else { return nil }
        let fieldName = String(displayText.dropFirst())
        
        guard availableFields.contains(fieldName) else { return nil }
        
        return SmartChip(
            type: .contactField,
            startIndex: 0, // Will be set by caller
            endIndex: displayText.count, // Will be set by caller
            displayText: displayText,
            field: fieldName
        )
    }
    
    func validate(_ chip: SmartChip) -> ChipValidationResult {
        guard let field = chip.field else {
            return ChipValidationResult(isValid: false, errors: ["Contact field chip missing field name"])
        }
        
        guard availableFields.contains(field) else {
            return ChipValidationResult(isValid: false, errors: ["Invalid contact field: \(field)"])
        }
        
        return ChipValidationResult(isValid: true)
    }
    
    func createChipView(_ chip: SmartChip) -> AnyView {
        AnyView(
            HStack(spacing: 4) {
                Image(systemName: "person.fill")
                    .font(.caption)
                Text(chip.displayText)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.8))
            .cornerRadius(4)
        )
    }
    
    func generateIdentifier(in text: String) -> String {
        var counter = 1
        var identifier = "@name"
        
        while text.contains(identifier) {
            counter += 1
            identifier = "@\(availableFields[0])_\(counter)"
        }
        
        return identifier
    }
    
    func parseExistingChips(in text: String) -> [SmartChip] {
        // This is handled by the main registry for contact fields
        return []
    }
}

// MARK: - Image Chip Handler

class ImageChipHandler: ChipTypeHandler {
    func parseChip(displayText: String, metadata: [String: Any]) -> SmartChip? {
        guard let imageUrl = metadata["imageUrl"] as? String, !imageUrl.isEmpty else {
            return nil
        }
        
        let imageMetadata = ImageChipMetadata(
            imageUrl: imageUrl,
            altText: metadata["altText"] as? String,
            width: metadata["width"] as? Int,
            height: metadata["height"] as? Int,
            alignment: metadata["alignment"] as? String
        )
        
        return SmartChip.image(
            startIndex: 0,
            endIndex: displayText.count,
            displayText: displayText,
            metadata: imageMetadata
        )
    }
    
    func validate(_ chip: SmartChip) -> ChipValidationResult {
        guard let imageUrl = chip.metadata["imageUrl"]?.value as? String, !imageUrl.isEmpty else {
            return ChipValidationResult(isValid: false, errors: ["Image chip missing URL"])
        }
        
        // Basic URL validation
        guard URL(string: imageUrl) != nil else {
            return ChipValidationResult(isValid: false, errors: ["Invalid image URL"])
        }
        
        return ChipValidationResult(isValid: true)
    }
    
    func createChipView(_ chip: SmartChip) -> AnyView {
        AnyView(
            HStack(spacing: 4) {
                Image(systemName: "photo.fill")
                    .font(.caption)
                Text(chip.displayText)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.8))
            .cornerRadius(4)
        )
    }
    
    func generateIdentifier(in text: String) -> String {
        var counter = 1
        var identifier = "@image_1"
        
        while text.contains(identifier) {
            counter += 1
            identifier = "@image_\(counter)"
        }
        
        return identifier
    }
    
    func parseExistingChips(in text: String) -> [SmartChip] {
        // Parse @image_1, @image_2, etc. patterns
        let pattern = "@image_\\d+"
        return parseChipsWithPattern(pattern, in: text, type: .image)
    }
}

// MARK: - Link Chip Handler

class LinkChipHandler: ChipTypeHandler {
    func parseChip(displayText: String, metadata: [String: Any]) -> SmartChip? {
        guard let url = metadata["url"] as? String, !url.isEmpty else {
            return nil
        }
        
        let linkMetadata = LinkChipMetadata(
            url: url,
            displayText: metadata["displayText"] as? String,
            openInNewTab: metadata["openInNewTab"] as? Bool,
            style: metadata["style"] as? String
        )
        
        return SmartChip.link(
            startIndex: 0,
            endIndex: displayText.count,
            displayText: displayText,
            metadata: linkMetadata
        )
    }
    
    func validate(_ chip: SmartChip) -> ChipValidationResult {
        guard let url = chip.metadata["url"]?.value as? String, !url.isEmpty else {
            return ChipValidationResult(isValid: false, errors: ["Link chip missing URL"])
        }
        
        // Basic URL validation
        guard URL(string: url) != nil else {
            return ChipValidationResult(isValid: false, errors: ["Invalid link URL"])
        }
        
        return ChipValidationResult(isValid: true)
    }
    
    func createChipView(_ chip: SmartChip) -> AnyView {
        AnyView(
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.caption)
                Text(chip.displayText)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.8))
            .cornerRadius(4)
        )
    }
    
    func generateIdentifier(in text: String) -> String {
        var counter = 1
        var identifier = "@link_1"
        
        while text.contains(identifier) {
            counter += 1
            identifier = "@link_\(counter)"
        }
        
        return identifier
    }
    
    func parseExistingChips(in text: String) -> [SmartChip] {
        // Parse @link_1, @link_2, etc. patterns
        let pattern = "@link_\\d+"
        return parseChipsWithPattern(pattern, in: text, type: .link)
    }
}

// MARK: - DateTime Chip Handler

class DateTimeChipHandler: ChipTypeHandler {
    func parseChip(displayText: String, metadata: [String: Any]) -> SmartChip? {
        let dateMetadata = DateTimeChipMetadata(
            format: metadata["format"] as? String ?? "MMM dd, yyyy",
            timezone: metadata["timezone"] as? String,
            defaultValue: metadata["defaultValue"] as? String
        )
        
        return SmartChip.datetime(
            startIndex: 0,
            endIndex: displayText.count,
            displayText: displayText,
            metadata: dateMetadata
        )
    }
    
    func validate(_ chip: SmartChip) -> ChipValidationResult {
        // Date format validation could be added here
        return ChipValidationResult(isValid: true)
    }
    
    func createChipView(_ chip: SmartChip) -> AnyView {
        AnyView(
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption)
                Text(chip.displayText)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.8))
            .cornerRadius(4)
        )
    }
    
    func generateIdentifier(in text: String) -> String {
        var counter = 1
        var identifier = "@datetime_1"
        
        while text.contains(identifier) {
            counter += 1
            identifier = "@datetime_\(counter)"
        }
        
        return identifier
    }
    
    func parseExistingChips(in text: String) -> [SmartChip] {
        // Parse @datetime_1, @date_1, etc. patterns
        let patterns = ["@datetime_\\d+", "@date_\\d+", "@time_\\d+"]
        var chips: [SmartChip] = []
        
        for pattern in patterns {
            chips.append(contentsOf: parseChipsWithPattern(pattern, in: text, type: .datetime))
        }
        
        return chips
    }
}

// MARK: - Variable Chip Handler

class VariableChipHandler: ChipTypeHandler {
    func parseChip(displayText: String, metadata: [String: Any]) -> SmartChip? {
        let variableMetadata = VariableChipMetadata(
            variableName: metadata["variableName"] as? String ?? "variable",
            defaultValue: metadata["defaultValue"] as? String,
            editable: metadata["editable"] as? Bool
        )
        
        return SmartChip.variable(
            startIndex: 0,
            endIndex: displayText.count,
            displayText: displayText,
            metadata: variableMetadata
        )
    }
    
    func validate(_ chip: SmartChip) -> ChipValidationResult {
        guard let variableName = chip.metadata["variableName"]?.value as? String, !variableName.isEmpty else {
            return ChipValidationResult(isValid: false, errors: ["Variable chip missing variable name"])
        }
        
        return ChipValidationResult(isValid: true)
    }
    
    func createChipView(_ chip: SmartChip) -> AnyView {
        AnyView(
            HStack(spacing: 4) {
                Image(systemName: "textformat.abc")
                    .font(.caption)
                Text(chip.displayText)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.teal.opacity(0.8))
            .cornerRadius(4)
        )
    }
    
    func generateIdentifier(in text: String) -> String {
        var counter = 1
        var identifier = "@var_1"
        
        while text.contains(identifier) {
            counter += 1
            identifier = "@var_\(counter)"
        }
        
        return identifier
    }
    
    func parseExistingChips(in text: String) -> [SmartChip] {
        // Parse @var_*, @company, @location, etc. patterns
        let patterns = ["@var_\\d+", "@var_\\w+"]
        var chips: [SmartChip] = []
        
        for pattern in patterns {
            chips.append(contentsOf: parseChipsWithPattern(pattern, in: text, type: .variable))
        }
        
        return chips
    }
}

// MARK: - Attachment Chip Handler

class AttachmentChipHandler: ChipTypeHandler {
    func parseChip(displayText: String, metadata: [String: Any]) -> SmartChip? {
        guard let filePath = metadata["filePath"] as? String, !filePath.isEmpty,
              let fileName = metadata["fileName"] as? String, !fileName.isEmpty else {
            return nil
        }
        
        let attachmentMetadata = AttachmentChipMetadata(
            filePath: filePath,
            fileName: fileName,
            fileSize: metadata["fileSize"] as? Int,
            mimeType: metadata["mimeType"] as? String
        )
        
        return SmartChip.attachment(
            startIndex: 0,
            endIndex: displayText.count,
            displayText: displayText,
            metadata: attachmentMetadata
        )
    }
    
    func validate(_ chip: SmartChip) -> ChipValidationResult {
        guard let filePath = chip.metadata["filePath"]?.value as? String, !filePath.isEmpty else {
            return ChipValidationResult(isValid: false, errors: ["Attachment chip missing file path"])
        }
        
        guard let fileName = chip.metadata["fileName"]?.value as? String, !fileName.isEmpty else {
            return ChipValidationResult(isValid: false, errors: ["Attachment chip missing file name"])
        }
        
        return ChipValidationResult(isValid: true)
    }
    
    func createChipView(_ chip: SmartChip) -> AnyView {
        AnyView(
            HStack(spacing: 4) {
                Image(systemName: "doc.fill")
                    .font(.caption)
                Text(chip.displayText)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.8))
            .cornerRadius(4)
        )
    }
    
    func generateIdentifier(in text: String) -> String {
        var counter = 1
        var identifier = "@attachment_1"
        
        while text.contains(identifier) {
            counter += 1
            identifier = "@attachment_\(counter)"
        }
        
        return identifier
    }
    
    func parseExistingChips(in text: String) -> [SmartChip] {
        // Parse @attachment_1, @file_1, etc. patterns
        let patterns = ["@attachment_\\d+", "@file_\\d+"]
        var chips: [SmartChip] = []
        
        for pattern in patterns {
            chips.append(contentsOf: parseChipsWithPattern(pattern, in: text, type: .attachment))
        }
        
        return chips
    }
}

// MARK: - Helper Extensions

extension ChipTypeHandler {
    func parseChipsWithPattern(_ pattern: String, in text: String, type: ChipType) -> [SmartChip] {
        var chips: [SmartChip] = []
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
            
            for match in matches {
                let displayText = (text as NSString).substring(with: match.range)
                let chip = SmartChip(
                    type: type,
                    startIndex: match.range.location,
                    endIndex: match.range.location + match.range.length,
                    displayText: displayText
                )
                chips.append(chip)
            }
        } catch {
            LogManager.shared.error("❌ Error parsing chips with pattern \(pattern): \(error)")
        }
        
        return chips
    }
}
