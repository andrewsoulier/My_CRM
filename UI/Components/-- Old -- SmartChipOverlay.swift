import SwiftUI

struct SmartChipOverlay: View {
    let text: String
    let availableFields: [String]
    
    var body: some View {
        // For now, let's create a simple overlay that shows chips
        // This is a simplified version - in a full implementation you'd need
        // to calculate exact text positions
        VStack(alignment: .leading, spacing: 0) {
            if !fieldReferences.isEmpty {
                HStack {
                    Text("Fields used: ")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    ForEach(fieldReferences, id: \.self) { field in
                        Text("@\(field)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.blue.opacity(0.8))
                            )
                    }
                    
                    Spacer()
                }
                .padding(.top, 4)
                .padding(.horizontal, 4)
            }
            
            Spacer()
        }
    }
    
    private var fieldReferences: [String] {
        let pattern = "@(\\w+)"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
            
            var fields: [String] = []
            for match in matches {
                let fieldRange = match.range(at: 1)
                if fieldRange.location != NSNotFound {
                    let fieldName = (text as NSString).substring(with: fieldRange)
                    if availableFields.contains(fieldName) && !fields.contains(fieldName) {
                        fields.append(fieldName)
                    }
                }
            }
            return fields
        } catch {
            return []
        }
    }
}
