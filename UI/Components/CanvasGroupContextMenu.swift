import SwiftUI

struct CanvasGroupContextMenu: View {
    let group: GroupCircle
    @ObservedObject var groupEditingService: GroupEditingService
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    let onViewDetails: (() -> Void)?
    
    init(group: GroupCircle, 
         groupEditingService: GroupEditingService,
         onEdit: (() -> Void)? = nil,
         onDelete: (() -> Void)? = nil,
         onViewDetails: (() -> Void)? = nil) {
        self.group = group
        self.groupEditingService = groupEditingService
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onViewDetails = onViewDetails
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group Info Header
            HStack {
                Circle()
                    .fill(group.color.opacity(0.2))
                    .stroke(group.color, lineWidth: 2)
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("\(group.members.count) members")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Menu Items
            VStack(alignment: .leading, spacing: 0) {
                // Edit Group
                Button(action: {
                    onEdit?()
                }) {
                    HStack {
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                            .frame(width: 16)
                        Text("Edit Group")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                
                // View Details
                if onViewDetails != nil {
                    Button(action: {
                        onViewDetails?()
                    }) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.green)
                                .frame(width: 16)
                            Text("View Details")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        if isHovered {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                }
                
                Divider()
                
                // Delete Group
                if onDelete != nil {
                    Button(action: {
                        onDelete?()
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .frame(width: 16)
                            Text("Delete Group")
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        if isHovered {
                            NSCursor.pointingHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 5)
        .frame(minWidth: 180)
    }
}

// MARK: - Preview

struct CanvasGroupContextMenu_Previews: PreviewProvider {
    static var previews: some View {
        let _ = SQLiteDataProvider() // Not needed since GroupEditingService uses shared dataProvider
        let groupEditingService = GroupEditingService()
        let sampleGroup = GroupCircle(name: "Sample Canvas Group", color: .blue)
        
        return CanvasGroupContextMenu(
            group: sampleGroup,
            groupEditingService: groupEditingService,
            onEdit: { print("Edit tapped") },
            onDelete: { print("Delete tapped") },
            onViewDetails: { print("View details tapped") }
        )
        .padding()
    }
}
