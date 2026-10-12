import SwiftUI

struct GroupEditDialog: View {
    @ObservedObject var groupEditingService: GroupEditingService
    @State private var groupName: String = ""
    @State private var selectedColor: Color = .blue
    @State private var isUpdating: Bool = false
    @State private var errorMessage: String?
    @State private var showingError: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Edit Group")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    groupEditingService.cancelEditing()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            
            if let group = groupEditingService.editingGroup {
                // Group Name Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Group Name")
                        .font(.headline)
                    
                    TextField("Enter group name", text: $groupName)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            groupName = group.name
                        }
                }
                
                // Color Selection Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Group Color")
                        .font(.headline)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(GroupEditingService.availableColors, id: \.self) { color in
                            ColorButton(
                                color: color,
                                isSelected: selectedColor.toHexString() == color.toHexString(),
                                onTap: {
                                    selectedColor = color
                                }
                            )
                        }
                    }
                }
                
                // Current Selection Preview
                VStack(spacing: 8) {
                    Text("Preview")
                        .font(.headline)
                    
                    HStack {
                        Circle()
                            .fill(selectedColor.opacity(0.2))
                            .stroke(selectedColor, lineWidth: 2)
                            .frame(width: 40, height: 40)
                        
                        Text(groupName.isEmpty ? "Group Name" : groupName)
                            .font(.body)
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Error Message
                if showingError, let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
                
                // Action Buttons
                HStack {
                    Button("Cancel") {
                        groupEditingService.cancelEditing()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Save Changes") {
                        Task {
                            await saveChanges()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUpdating)
                }
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
        .onAppear {
            if let group = groupEditingService.editingGroup {
                groupName = group.name
                selectedColor = group.color
            }
        }
    }
    
    private func saveChanges() async {
        guard let group = groupEditingService.editingGroup else { return }
        
        isUpdating = true
        errorMessage = nil
        showingError = false
        
        do {
            try await groupEditingService.updateGroup(
                group.id,
                name: groupName,
                color: selectedColor
            )
            
            // Success - close dialog
            groupEditingService.finishEditing()
            
        } catch {
            // Handle error
            errorMessage = error.localizedDescription
            showingError = true
        }
        
        isUpdating = false
    }
}

struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(color)
                .stroke(isSelected ? Color.primary : Color.clear, lineWidth: isSelected ? 3 : 1)
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Preview

struct GroupEditDialog_Previews: PreviewProvider {
    static var previews: some View {
        let _ = SQLiteDataProvider()
        let groupEditingService = GroupEditingService()
        
        // Create a sample group for preview
        let sampleGroup = ContactGroup(name: "Sample Group", color: .blue)
        
        return GroupEditDialog(groupEditingService: groupEditingService)
            .onAppear {
                groupEditingService.startEditingGroup(sampleGroup)
            }
    }
}
