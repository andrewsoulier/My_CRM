import SwiftUI
import AppKit

// MARK: - SwiftUI Wrapper
struct ChipTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var chipMetadata: ChipMetadata?
    let availableFields: [String]
    @Binding var showingDropdown: Bool
    @Binding var dropdownPosition: CGPoint
    @Binding var dropdownFilter: String
    @Binding var selectedDropdownIndex: Int
    var totalFilteredItems: Int = 0  // Total count of filtered items for bounds checking
    var onChipEdit: ((SmartChip) -> Void)?
    var onKeyboardSelect: (() -> Void)?  // Callback when Enter/Tab is pressed
    var onCoordinatorReady: ((Coordinator) -> Void)?  // Callback to provide coordinator reference
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = ChipNSTextView(frame: .zero)
        
        textView.delegate = context.coordinator
        textView.availableFields = availableFields
        textView.onTextChange = { newText in
            text = newText
        }
        textView.onChipMetadataChange = { newMetadata in
            chipMetadata = newMetadata
        }
        textView.onDropdownStateChange = { showing, position, filter in
            showingDropdown = showing
            dropdownPosition = position
            dropdownFilter = filter
            if showing {
                selectedDropdownIndex = 0
            }
        }
        textView.onChipEdit = onChipEdit
        textView.onKeyboardSelect = onKeyboardSelect
        textView.onSelectedIndexChange = { newIndex in
            selectedDropdownIndex = newIndex
        }
        
        // Configure text view for editing
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isRichText = true
        textView.allowsUndo = true
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 4
        textView.minSize = NSSize(width: 0, height: 100)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        // Store reference in coordinator for chip insertion
        context.coordinator.textView = textView
        
        // Provide coordinator to parent view
        DispatchQueue.main.async {
            onCoordinatorReady?(context.coordinator)
        }
        
        // Configure scroll view
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ChipNSTextView else { return }
        
        textView.availableFields = availableFields
        textView.selectedDropdownIndex = selectedDropdownIndex
        textView.totalFilteredItems = totalFilteredItems
        textView.onKeyboardSelect = onKeyboardSelect
        textView.onSelectedIndexChange = { newIndex in
            selectedDropdownIndex = newIndex
        }
        
        // Update text if it changed externally
        if textView.plainText != text {
            textView.setTextPreservingChips(text)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChipTextView
        var textView: ChipNSTextView?  // Reference to the NSTextView for chip insertion
        
        init(_ parent: ChipTextView) {
            self.parent = parent
        }
        
        // Method to insert chip from parent view
        func insertChip(chipType: ChipType, chipData: ChipData) {
            textView?.insertSelectedChip(chipType: chipType, chipData: chipData)
        }
        
        func textDidChange(_ notification: Notification) {
            // Handled by ChipNSTextView callbacks
        }
    }
}

// MARK: - Custom NSTextView
class ChipNSTextView: NSTextView {
    var availableFields: [String] = []
    var onTextChange: ((String) -> Void)?
    var onChipMetadataChange: ((ChipMetadata?) -> Void)?
    var onDropdownStateChange: ((Bool, CGPoint, String) -> Void)?
    var onChipEdit: ((SmartChip) -> Void)?
    var onKeyboardSelect: (() -> Void)?  // Called when Enter/Tab is pressed
    var onSelectedIndexChange: ((Int) -> Void)?  // Called when arrow keys change selection
    
    var selectedDropdownIndex: Int = 0
    var totalFilteredItems: Int = 0  // Total count for bounds checking
    
    private var chips: [ChipAttachment] = []
    private var isShowingDropdown = false
    private var currentAtSymbolRange: NSRange?
    private var currentFilterText = ""
    private let registry = ChipTypeRegistry.shared
    
    var plainText: String {
        return string
    }
    
    override func keyDown(with event: NSEvent) {
        if isShowingDropdown {
            handleDropdownKeyEvent(event)
        } else {
            super.keyDown(with: event)
        }
    }
    
    override func didChangeText() {
        super.didChangeText()
        
        detectAtSymbol()
        updateChipMetadata()
        // Keep the rich text string for display, but store plain text in metadata
        onTextChange?(string)
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        
        // Check if clicked on a chip
        let location = convert(event.locationInWindow, from: nil)
        let characterIndex = characterIndexForInsertion(at: location)
        
        if let chip = findChipAt(characterIndex) {
            onChipEdit?(chip)
        }
    }
    
    func setTextPreservingChips(_ newText: String) {
        string = newText
        updateChipMetadata()
    }
    
    // MARK: - @ Symbol Detection
    private func detectAtSymbol() {
        let cursorPosition = selectedRange().location
        
        print("🔍 DEBUG: detectAtSymbol called, cursor at position \(cursorPosition), text: '\(string)'")
        
        // Look for @ symbol before cursor
        if let atRange = findAtSymbolRange(beforePosition: cursorPosition) {
            let startIndex = atRange.location + 1
            let endIndex = cursorPosition
            
            print("✅ DEBUG: Found @ at range \(atRange), startIndex: \(startIndex), endIndex: \(endIndex)")
            
            if endIndex >= startIndex {
                let filterStart = string.index(string.startIndex, offsetBy: startIndex)
                let filterEnd = string.index(string.startIndex, offsetBy: endIndex)
                currentFilterText = String(string[filterStart..<filterEnd])
                currentAtSymbolRange = atRange
                
                print("📝 DEBUG: Filter text: '\(currentFilterText)', showing dropdown")
                showDropdown(at: atRange.location)
            } else {
                print("❌ DEBUG: endIndex < startIndex, hiding dropdown")
                hideDropdown()
            }
        } else {
            print("❌ DEBUG: No @ symbol found, hiding dropdown")
            hideDropdown()
        }
    }
    
    private func findAtSymbolRange(beforePosition position: Int) -> NSRange? {
        guard position > 0 else { return nil }
        
        let searchStart = max(0, position - 50)
        let searchLength = position - searchStart
        let searchRange = NSRange(location: searchStart, length: searchLength)
        let searchText = (string as NSString).substring(with: searchRange)
        
        // Find the last @ symbol that isn't part of a chip
        var lastAtIndex: Int?
        for (index, char) in searchText.enumerated() {
            if char == "@" {
                let absoluteIndex = searchStart + index
                // Check if this @ is inside a chip attachment
                if !isPositionInsideChip(absoluteIndex) {
                    lastAtIndex = absoluteIndex
                }
            } else if char.isWhitespace || char.isNewline {
                // Reset if we hit whitespace
                lastAtIndex = nil
            }
        }
        
        if let atIndex = lastAtIndex {
            return NSRange(location: atIndex, length: 1)
        }
        
        return nil
    }
    
    private func isPositionInsideChip(_ position: Int) -> Bool {
        // Check if position is inside a chip attachment
        guard let storage = textStorage else { return false }
        
        if position >= storage.length {
            return false
        }
        
        let attachment = storage.attribute(.attachment, at: position, effectiveRange: nil)
        return attachment != nil
    }
    
    // MARK: - Dropdown Management
    private func showDropdown(at position: Int) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else {
            print("❌ DEBUG: No layoutManager or textContainer")
            return
        }
        
        // Get the glyph range for the character
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: position, length: 1), actualCharacterRange: nil)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        
        // Convert to window coordinates
        var dropdownPoint = convert(CGPoint(x: glyphRect.minX, y: glyphRect.maxY), to: nil)
        
        // Convert to screen coordinates
        if let window = window {
            dropdownPoint = window.convertPoint(toScreen: dropdownPoint)
        }
        
        print("✅ DEBUG: Showing dropdown at position \(dropdownPoint), filter: '\(currentFilterText)'")
        
        isShowingDropdown = true
        onDropdownStateChange?(true, dropdownPoint, currentFilterText)
    }
    
    private func hideDropdown() {
        if isShowingDropdown {
            isShowingDropdown = false
            currentAtSymbolRange = nil
            currentFilterText = ""
            onDropdownStateChange?(false, .zero, "")
        }
    }
    
    // MARK: - Keyboard Handling for Dropdown
    private func handleDropdownKeyEvent(_ event: NSEvent) {
        let key = event.keyCode
        
        print("🎹 DEBUG: Key pressed during dropdown: \(key)")
        
        switch key {
        case 125: // Down arrow
            let newIndex = min(selectedDropdownIndex + 1, max(0, totalFilteredItems - 1))
            print("⬇️ DEBUG: Down arrow - moving from \(selectedDropdownIndex) to \(newIndex) (total: \(totalFilteredItems))")
            selectedDropdownIndex = newIndex
            onSelectedIndexChange?(newIndex)
            return
            
        case 126: // Up arrow
            let newIndex = max(0, selectedDropdownIndex - 1)
            print("⬆️ DEBUG: Up arrow - moving from \(selectedDropdownIndex) to \(newIndex)")
            selectedDropdownIndex = newIndex
            onSelectedIndexChange?(newIndex)
            return
            
        case 53: // Escape
            print("⎋ DEBUG: Escape pressed - hiding dropdown")
            hideDropdown()
            return
            
        case 36, 48: // Enter or Tab
            print("⏎ DEBUG: Enter/Tab pressed - triggering selection at index \(selectedDropdownIndex)")
            onKeyboardSelect?()
            hideDropdown()
            return
            
        default:
            // Let normal text input continue - don't hide dropdown yet
            // detectAtSymbol() will handle hiding if needed after text changes
            print("⌨️ DEBUG: Regular key pressed - continuing normal input")
            super.keyDown(with: event)
        }
    }
    
    // MARK: - Chip Insertion
    func insertSelectedChip(chipType: ChipType, chipData: ChipData) {
        guard let atRange = currentAtSymbolRange else { return }
        
        // Calculate the full range to replace (@ symbol + filter text)
        let replaceStart = atRange.location
        let replaceEnd = selectedRange().location
        let replaceRange = NSRange(location: replaceStart, length: replaceEnd - replaceStart)
        
        // Create the chip
        let chip = createChip(type: chipType, data: chipData)
        let chipAttachment = ChipAttachment(chip: chip)
        
        // Create attributed string with the chip
        let attachmentString = NSAttributedString(attachment: chipAttachment)
        
        // Replace the @... text with the chip
        textStorage?.replaceCharacters(in: replaceRange, with: attachmentString)
        
        // Set default typing attributes for text after the chip
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor
        ]
        typingAttributes = defaultAttributes
        
        // Move cursor after the chip (no space added)
        let cursorLocation = replaceRange.location + 1
        setSelectedRange(NSRange(location: cursorLocation, length: 0))
        
        // Store chip reference
        chips.append(chipAttachment)
        
        hideDropdown()
        updateChipMetadata()
        
        didChangeText()
    }
    
    private func createChip(type: ChipType, data: ChipData) -> SmartChip {
        let displayText = data.displayText
        
        switch type {
        case .contactField:
            return SmartChip.contactField(
                field: data.fieldName ?? "name",
                startIndex: 0,
                endIndex: displayText.count,
                displayText: displayText
            )
            
        case .image:
            let metadata = ImageChipMetadata(
                imageUrl: data.imageUrl ?? "",
                altText: data.altText,
                width: data.width,
                height: data.height,
                alignment: data.alignment
            )
            return SmartChip.image(
                startIndex: 0,
                endIndex: displayText.count,
                displayText: displayText,
                metadata: metadata
            )
            
        case .link:
            let metadata = LinkChipMetadata(
                url: data.linkUrl ?? "",
                displayText: data.linkDisplayText,
                openInNewTab: data.openInNewTab,
                style: data.linkStyle
            )
            return SmartChip.link(
                startIndex: 0,
                endIndex: displayText.count,
                displayText: displayText,
                metadata: metadata
            )
            
        case .datetime:
            let metadata = DateTimeChipMetadata(
                format: data.dateFormat ?? "MMM dd, yyyy",
                timezone: data.timezone,
                defaultValue: data.dateDefaultValue
            )
            return SmartChip.datetime(
                startIndex: 0,
                endIndex: displayText.count,
                displayText: displayText,
                metadata: metadata
            )
            
        case .variable:
            let metadata = VariableChipMetadata(
                variableName: data.variableName ?? "variable",
                defaultValue: data.variableDefaultValue,
                editable: data.variableEditable
            )
            return SmartChip.variable(
                startIndex: 0,
                endIndex: displayText.count,
                displayText: displayText,
                metadata: metadata
            )
            
        case .attachment:
            let metadata = AttachmentChipMetadata(
                filePath: data.filePath ?? "",
                fileName: data.fileName ?? "file",
                fileSize: data.fileSize,
                mimeType: data.mimeType
            )
            return SmartChip.attachment(
                startIndex: 0,
                endIndex: displayText.count,
                displayText: displayText,
                metadata: metadata
            )
        }
    }
    
    // MARK: - Chip Metadata Management
    private func updateChipMetadata() {
        // Extract chips from NSTextAttachment objects in the attributed string
        guard let storage = textStorage else {
            onChipMetadataChange?(ChipMetadata(chips: [], version: "2.0"))
            return
        }
        
        var extractedChips: [SmartChip] = []
        let fullRange = NSRange(location: 0, length: storage.length)
        
        storage.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            if let chipAttachment = value as? ChipAttachment {
                // Create a new chip with updated indices
                let originalChip = chipAttachment.chip
                let updatedChip = SmartChip(
                    type: originalChip.type,
                    startIndex: range.location,
                    endIndex: range.location + range.length,
                    displayText: originalChip.displayText,
                    field: originalChip.field,
                    metadata: originalChip.metadata.mapValues { $0.value }
                )
                extractedChips.append(updatedChip)
                print("📍 ChipTextView: Found chip '\(originalChip.displayText)' (field: \(originalChip.field ?? "nil")) at range \(range.location)-\(range.location + range.length)")
            }
        }
        
        print("✅ ChipTextView: Extracted \(extractedChips.count) chip(s) from text storage")
        let metadata = ChipMetadata(chips: extractedChips, version: "2.0")
        onChipMetadataChange?(metadata)
    }
    
    private func findChipAt(_ characterIndex: Int) -> SmartChip? {
        guard let storage = textStorage else { return nil }
        
        if characterIndex >= storage.length {
            return nil
        }
        
        if let attachment = storage.attribute(.attachment, at: characterIndex, effectiveRange: nil) as? ChipAttachment {
            return attachment.chip
        }
        
        return nil
    }
}

// MARK: - Chip Attachment
class ChipAttachment: NSTextAttachment {
    let chip: SmartChip
    
    init(chip: SmartChip) {
        self.chip = chip
        super.init(data: nil, ofType: nil)
        
        // Create the chip image
        self.image = createChipImage()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func createChipImage() -> NSImage {
        let displayText = chip.displayText
        // Match the font size to surrounding text (14pt)
        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let textColor = NSColor.white
        let backgroundColor = chip.type.nsColor
        
        // Calculate size
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        let textSize = (displayText as NSString).size(withAttributes: attributes)
        // Reduce padding to make chip height closer to text height
        let horizontalPadding: CGFloat = 6
        let verticalPadding: CGFloat = 2
        let imageSize = NSSize(
            width: textSize.width + horizontalPadding * 2,
            height: textSize.height + verticalPadding * 2
        )
        
        // Create image
        let image = NSImage(size: imageSize)
        image.lockFocus()
        
        // Draw background
        let rect = NSRect(origin: .zero, size: imageSize)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        backgroundColor.setFill()
        path.fill()
        
        // Draw text
        let textRect = NSRect(
            x: horizontalPadding,
            y: verticalPadding,
            width: textSize.width,
            height: textSize.height
        )
        (displayText as NSString).draw(in: textRect, withAttributes: attributes)
        
        image.unlockFocus()
        
        return image
    }
    
    // Override to properly align chip on text baseline
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> NSRect {
        guard let image = image else {
            return .zero
        }
        
        // Match the surrounding editor font metrics
        let font = NSFont.systemFont(ofSize: 14)
        
        // Center the chip relative to the text's visual center.
        // Using capHeight better matches perceived text height for uppercase/lowercase mixes.
        let yOffset = (font.capHeight - image.size.height) / 2
        
        return NSRect(
            x: 0,
            y: yOffset,
            width: image.size.width,
            height: image.size.height
        )
    }
}

// MARK: - Chip Data Structure
struct ChipData {
    var displayText: String
    
    // Contact field
    var fieldName: String?
    
    // Image
    var imageUrl: String?
    var altText: String?
    var width: Int?
    var height: Int?
    var alignment: String?
    
    // Link
    var linkUrl: String?
    var linkDisplayText: String?
    var openInNewTab: Bool?
    var linkStyle: String?
    
    // DateTime
    var dateFormat: String?
    var timezone: String?
    var dateDefaultValue: String?
    
    // Variable
    var variableName: String?
    var variableDefaultValue: String?
    var variableEditable: Bool?
    
    // Attachment
    var filePath: String?
    var fileName: String?
    var fileSize: Int?
    var mimeType: String?
    
    init(displayText: String) {
        self.displayText = displayText
    }
}
