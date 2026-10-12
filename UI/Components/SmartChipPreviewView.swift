import SwiftUI
import Foundation

struct SmartChipPreviewView: NSViewRepresentable {
    let text: String
    let availableFields: [String]
    let isTemplate: Bool // true for template view, false for processed view
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = isTemplate ? NSColor.controlBackgroundColor : NSColor.systemBlue.withAlphaComponent(0.05)
        textView.isRichText = true
        textView.string = text
        
        // Set proper frame sizing for textView to be visible
        textView.frame = scrollView.contentView.bounds
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        if textView.string != text {
            textView.string = text
            styleText(textView: textView)
        }
    }
    
    private func styleText(textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        
        let text = textView.string
        let fullRange = NSRange(location: 0, length: text.count)
        
        // Only remove chip-specific attributes, preserve base styling
        textStorage.removeAttribute(.backgroundColor, range: fullRange)
        
        // Set default attributes without removing existing paragraph styles
        textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
        
        if isTemplate {
            // Style @field references as chips for template view
            styleFieldReferences(in: textStorage, text: text)
        } else {
            // For processed view, just show regular text (fields are already replaced)
            // But we can highlight where fields were replaced
            highlightReplacedFields(in: textStorage, text: text)
        }
    }
    
    private func styleFieldReferences(in textStorage: NSTextStorage, text: String) {
        let pattern = "@(\\w+)"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
            
            for match in matches {
                let fieldRange = match.range(at: 1) // Get the field name without @
                let fullMatchRange = match.range(at: 0) // Get the full @field
                
                if fieldRange.location != NSNotFound {
                    let fieldName = (text as NSString).substring(with: fieldRange)
                    
                    if availableFields.contains(fieldName) {
                        // Style as a contact field chip (blue)
                        styleAsChip(range: fullMatchRange, in: textStorage, chipType: .contactField)
                    }
                }
            }
        } catch {
            print("Error creating regex: \(error)")
        }
    }
    
    private func highlightReplacedFields(in textStorage: NSTextStorage, text: String) {
        // Lightly highlight segments that were likely replaced by tokens (heuristic):
        // We detect common patterns like emails, phone numbers, and capitalized name tokens.
        let patterns = [
            "[A-Z][a-z]+(\\s[A-Z][a-z]+)?",      // Names (simple heuristic)
            "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", // Emails
            "\\+?[0-9][0-9 .\\-()]{5,}"           // Phone-like (simplified)
        ]
        let fullRange = NSRange(location: 0, length: text.count)
        for pattern in patterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let matches = regex.matches(in: text, options: [], range: fullRange)
                for match in matches {
                    textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
                    textStorage.addAttribute(.underlineColor, value: NSColor.systemBlue.withAlphaComponent(0.4), range: match.range)
                }
            } catch {
                print("Error creating highlight regex: \(error)")
            }
        }
    }
    
    private func styleAsChip(range: NSRange, in textStorage: NSTextStorage, chipType: ChipType) {
        // Create chip appearance with type-specific color
        let baseColor = chipType.nsColor
        let chipColor = baseColor.withAlphaComponent(0.2)
        let textColor = baseColor
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        
        textStorage.addAttribute(.backgroundColor, value: chipColor, range: range)
        textStorage.addAttribute(.foregroundColor, value: textColor, range: range)
        textStorage.addAttribute(.font, value: font, range: range)
        
        // Add rounded corners effect (this is approximate in NSTextView)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
    }
}
