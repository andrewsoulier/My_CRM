import SwiftUI

struct RecipientChipView: View {
    let recipient: RecipientChip
    let onRemove: () -> Void
    
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    
    // Computed property for chip color - fetch latest from dataProvider
    private var chipColor: Color {
        switch recipient.type {
        case .contact:
            return Color(NSColor.systemGray)
        case .group:
            // Try to fetch the latest group data from dataProvider for current color
            if let groupId = recipient.group?.id,
               let currentGroup = dataProvider.groups.first(where: { $0.id == groupId }) {
                return currentGroup.color
            }
            // Fallback to stored color or default
            return recipient.group?.color ?? Color.green
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Icon based on type
            Image(systemName: recipient.type == .contact ? "person.fill" : "person.3.fill")
                .font(.caption)
                .foregroundColor(.white)
            
            // Display name
            Text(recipient.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(chipColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}
