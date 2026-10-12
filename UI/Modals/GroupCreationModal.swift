import SwiftUI

struct GroupCreationModal: View {
    let initialName: String
    @Binding var isPresented: Bool
    let onGroupCreated: (ContactGroup) -> Void
    
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var appState: AppState
    
    @State private var name: String = ""
    @State private var selectedColor: Color = .blue
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    
    private let availableColors: [Color] = [
        .blue, .green, .orange, .red, .purple, .pink, .yellow, .cyan, .indigo, .mint
    ]
    
    private let logger = LogManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Create New Group")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section(header: Text("Group Information")) {
                    TextField("Group Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    
                    // Color picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            ForEach(availableColors, id: \.self) { color in
                                Button(action: {
                                    selectedColor = color
                                }) {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle()
                                                .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 3)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            
            // Error message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: createGroup) {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Create Group")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || isCreating)
            }
            .padding()
        }
        .frame(width: 400, height: 400)
        .onAppear {
            // Pre-fill name if provided
            if !initialName.isEmpty {
                name = initialName
            }
        }
    }
    
    private func createGroup() {
        guard !name.isEmpty else {
            errorMessage = "Group name is required"
            return
        }
        
        // Check if group with this name already exists
        if dataProvider.groups.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            errorMessage = "A group with this name already exists"
            return
        }
        
        isCreating = true
        errorMessage = nil
        
        Task {
            do {
                // Create group
                let group = ContactGroup(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    color: selectedColor
                )
                
                // Save to database (refresh happens automatically in createGroup)
                try await dataProvider.createGroup(group)
                
                // Find the created group
                if let createdGroup = dataProvider.groups.first(where: { $0.id == group.id }) {
                    logger.info("✅ GroupCreationModal: Created group: \(createdGroup.name)")
                    
                    await MainActor.run {
                        isCreating = false
                        onGroupCreated(createdGroup)
                        isPresented = false
                    }
                } else {
                    throw NSError(domain: "GroupCreationModal", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to retrieve created group"])
                }
            } catch {
                logger.error("❌ GroupCreationModal: Error creating group: \(error.localizedDescription)")
                await MainActor.run {
                    isCreating = false
                    errorMessage = "Failed to create group: \(error.localizedDescription)"
                }
            }
        }
    }
}

