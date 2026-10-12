import SwiftUI
import Foundation

struct SmartChipTextView: NSViewRepresentable {
    @Binding var text: String
    let availableFields: [String]
    @Binding var fieldSuggestions: [String]
    @Binding var showingFieldSuggestions: Bool
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textContainer = NSTextContainer()
        let textView = SmartChipNSTextView(frame: .zero, textContainer: textContainer)
        
        textView.delegate = context.coordinator
        textView.availableFields = availableFields
        textView.onFieldSuggestionsChange = { (suggestions: [String], showing: Bool) in
            fieldSuggestions = suggestions
            showingFieldSuggestions = showing
        }
        
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
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = CGSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? SmartChipNSTextView else { return }
        
        if textView.string != text {
            textView.string = text
            textView.styleFieldReferences()
        }
        
        textView.availableFields = availableFields
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SmartChipTextView
        
        init(_ parent: SmartChipTextView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? SmartChipNSTextView else { return }
            parent.text = textView.string
            textView.styleFieldReferences()
        }
        
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let smartTextView = textView as? SmartChipNSTextView else { return true }
            return smartTextView.handleTextChange(in: affectedCharRange, replacement: replacementString)
        }
    }
}

class SmartChipNSTextView: NSTextView {
    var availableFields: [String] = []
    var onFieldSuggestionsChange: (([String], Bool) -> Void)?
    
    private var currentFieldInput: String = ""
    private var fieldInputRange: NSRange?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupTextView()
    }
    
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setupTextView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextView()
    }
    
    private func setupTextView() {
        isRichText = true
        allowsUndo = true
        isEditable = true
        isSelectable = true
        font = NSFont.systemFont(ofSize: 14)
        textColor = NSColor.textColor
        backgroundColor = NSColor.textBackgroundColor
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = CGSize(width: frame.width, height: CGFloat.greatestFiniteMagnitude)
        
        // Make sure the text view can receive focus
        // These properties are read-only, so we'll override the methods instead
    }
    
    func handleTextChange(in range: NSRange, replacement: String?) -> Bool {
        // Handle field input detection
        let currentText = string
        let newText: String
        
        if let replacement = replacement {
            let nsString = currentText as NSString
            newText = nsString.replacingCharacters(in: range, with: replacement)
        } else {
            newText = currentText
        }
        
        // Check for @field input
        let cursorPosition = range.location + (replacement?.count ?? 0)
        checkForFieldInput(in: newText, at: cursorPosition)
        
        return true
    }
    
    private func checkForFieldInput(in text: String, at position: Int) {
        // Look for @ symbol before cursor
        if let atIndex = findLastAtSymbol(in: text, before: position) {
            let fieldStart = text.index(text.startIndex, offsetBy: atIndex + 1)
            let fieldEnd = text.index(text.startIndex, offsetBy: position)
            
            if fieldStart < fieldEnd {
                currentFieldInput = String(text[fieldStart..<fieldEnd])
                fieldInputRange = NSRange(location: atIndex, length: position - atIndex)
                updateFieldSuggestions()
            } else {
                hideFieldSuggestions()
            }
        } else {
            hideFieldSuggestions()
        }
    }
    
    private func findLastAtSymbol(in text: String, before position: Int) -> Int? {
        let searchRange = max(0, position - 20)
        let searchText = String(text.prefix(position).suffix(20))
        
        if let range = searchText.range(of: "@", options: .backwards) {
            let relativeIndex = searchText.distance(from: searchText.startIndex, to: range.lowerBound)
            return searchRange + relativeIndex
        }
        
        return nil
    }
    
    private func updateFieldSuggestions() {
        let suggestions: [String]
        if currentFieldInput.isEmpty {
            suggestions = availableFields
        } else {
            suggestions = availableFields.filter { field in
                field.localizedCaseInsensitiveContains(currentFieldInput)
            }
        }
        
        onFieldSuggestionsChange?(suggestions, !suggestions.isEmpty)
    }
    
    private func hideFieldSuggestions() {
        onFieldSuggestionsChange?([], false)
        currentFieldInput = ""
        fieldInputRange = nil
    }
    
    func insertField(_ field: String) {
        guard let range = fieldInputRange else { return }
        
        // Replace the @partial_field with @field
        let fullFieldText = "@\(field)"
        
        if shouldChangeText(in: range, replacementString: fullFieldText) {
            replaceCharacters(in: range, with: fullFieldText)
            styleFieldReferences()
        }
        
        hideFieldSuggestions()
    }
    
    func styleFieldReferences() {
        guard let textStorage = textStorage else { return }
        
        let text = string
        let fullRange = NSRange(location: 0, length: text.count)
        
        // Reset all attributes
        textStorage.removeAttribute(.backgroundColor, range: fullRange)
        textStorage.removeAttribute(.foregroundColor, range: fullRange)
        textStorage.removeAttribute(.font, range: fullRange)
        
        // Set default attributes
        textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
        
        // Find and style @field references
        let pattern = "@(\\w+)"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let matches = regex.matches(in: text, options: [], range: fullRange)
            
            for match in matches {
                let fieldRange = match.range(at: 1) // Get the field name without @
                let fullMatchRange = match.range(at: 0) // Get the full @field
                
                if fieldRange.location != NSNotFound {
                    let fieldName = (text as NSString).substring(with: fieldRange)
                    
                    if availableFields.contains(fieldName) {
                        // Style as a chip
                        styleAsChip(range: fullMatchRange, in: textStorage)
                    }
                }
            }
        } catch {
            print("Error creating regex: \(error)")
        }
    }
    
    private func styleAsChip(range: NSRange, in textStorage: NSTextStorage) {
        // Create chip appearance
        let chipColor = NSColor.systemBlue.withAlphaComponent(0.2)
        let textColor = NSColor.systemBlue
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        
        textStorage.addAttribute(.backgroundColor, value: chipColor, range: range)
        textStorage.addAttribute(.foregroundColor, value: textColor, range: range)
        textStorage.addAttribute(.font, value: font, range: range)
        
        // Add some padding effect with a custom attribute
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
    }
    
    override func keyDown(with event: NSEvent) {
        // Handle special keys for field suggestions
        if onFieldSuggestionsChange != nil && !currentFieldInput.isEmpty {
            switch event.keyCode {
            case 36: // Return key
                if let firstSuggestion = availableFields.first(where: { $0.localizedCaseInsensitiveContains(currentFieldInput) }) {
                    insertField(firstSuggestion)
                    return
                }
            case 53: // Escape key
                hideFieldSuggestions()
                return
            default:
                break
            }
        }
        
        super.keyDown(with: event)
    }
    
    override func didChangeText() {
        super.didChangeText()
        styleFieldReferences()
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        return super.becomeFirstResponder()
    }
}
