import SwiftUI

struct CanvasManagementView: View {
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    @State private var canvases: [Canvas] = []
    
    // Use centralized canvas service to prevent StateObject issues
    private var canvasService: CanvasUpdateService {
        globalCanvasService.canvasService
    }
    @State private var showingCreateCanvas = false
    @State private var searchText = ""
    @State private var selectedCanvasType: CanvasType = .groupMap
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedCanvasId: String?
    @State private var showingDeleteConfirmation = false
    
    var filteredCanvases: [Canvas] {
        if searchText.isEmpty {
            return canvases.filter { $0.canvasType == selectedCanvasType }
        } else {
            return canvases.filter { 
                $0.canvasType == selectedCanvasType && 
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with search and filters
                VStack(spacing: 12) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search canvases...", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .padding(.horizontal)
                    
                    // Canvas type filter
                    Picker("Canvas Type", selection: $selectedCanvasType) {
                        ForEach(CanvasType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                }
                .padding(.vertical)
                .background(Color(NSColor.controlBackgroundColor))
                
                // Canvas list
                if isLoading {
                    Spacer()
                    ProgressView("Loading canvases...")
                    Spacer()
                } else if filteredCanvases.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "No canvases yet" : "No matching canvases")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        if searchText.isEmpty {
                            Text("Create your first canvas to get started")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    Spacer()
                } else {
                    List(filteredCanvases, selection: $selectedCanvasId) { canvas in
                        CanvasRowView(canvas: canvas, canvasService: canvasService, onDelete: {
                            loadCanvases()
                        })
                        .tag(canvas.id)
                    }
                }
            }
            .navigationTitle("Canvas Management")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingCreateCanvas = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreateCanvas) {
                CreateCanvasView(canvasService: canvasService)
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .alert("Delete Canvas", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteSelectedCanvas()
                }
            } message: {
                if let canvasToDelete = canvases.first(where: { $0.id == selectedCanvasId }) {
                    Text("Are you sure you want to delete '\(canvasToDelete.name)'? This action cannot be undone.")
                }
            }
            .onDeleteCommand {
                if selectedCanvasId != nil {
                    showingDeleteConfirmation = true
                }
            }
            .onAppear {
                loadCanvases()
            }
            .refreshable {
                loadCanvases()
            }
        }
    }
    
    private func loadCanvases() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedCanvases = self.globalCanvasService.canvasService.getAllCanvases()
            DispatchQueue.main.async {
                self.canvases = loadedCanvases
                self.isLoading = false
            }
        }
    }
    
    private func deleteSelectedCanvas() {
        guard let canvasId = selectedCanvasId else { return }
        
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let success = self.globalCanvasService.canvasService.deleteCanvas(id: canvasId)
            DispatchQueue.main.async {
                if success {
                    // Remove from local array
                    self.canvases.removeAll { $0.id == canvasId }
                    self.selectedCanvasId = nil
                } else {
                    self.errorMessage = "Failed to delete canvas. Please try again."
                }
                self.isLoading = false
            }
        }
    }
}

struct CanvasRowView: View {
    let canvas: Canvas
    let canvasService: CanvasUpdateService
    let onDelete: () -> Void
    @State private var showingDeleteAlert = false
    @State private var isDeleting = false
    
    var body: some View {
        NavigationLink(destination: CanvasEditorView(canvas: canvas, canvasService: canvasService)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(canvas.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(canvas.canvasType.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(canvas.elementCounts.all) elements")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(canvas.dateUpdated, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Element type breakdown
                HStack(spacing: 12) {
                    if canvas.elementCounts.contacts > 0 {
                        Label("\(canvas.elementCounts.contacts)", systemImage: "person")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    
                    if canvas.elementCounts.groups > 0 {
                        Label("\(canvas.elementCounts.groups)", systemImage: "circle.hexagongrid")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    

                }
            }
            .padding(.vertical, 4)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Canvas", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteCanvas()
            }
        } message: {
            Text("Are you sure you want to delete '\(canvas.name)'? This action cannot be undone.")
        }
        .disabled(isDeleting)
    }
    
    private func deleteCanvas() {
        isDeleting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let success = canvasService.deleteCanvas(id: canvas.id)
            DispatchQueue.main.async {
                isDeleting = false
                if success {
                    onDelete()
                } else {
                    // Handle error
                }
            }
        }
    }
}

struct CreateCanvasView: View {
    let canvasService: CanvasUpdateService
    @Environment(\.dismiss) private var dismiss
    
    @State private var canvasName = ""
    @State private var selectedType: CanvasType = .groupMap
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            Form {
                Section("Canvas Details") {
                    TextField("Canvas Name", text: $canvasName)
                        .focused($isTextFieldFocused)
                        .onAppear {
                            // Automatically focus the text field when the view appears
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isTextFieldFocused = true
                            }
                        }
                    
                    Picker("Canvas Type", selection: $selectedType) {
                        ForEach(CanvasType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }
                
                Section {
                    Text("Canvas types help organize your visual maps:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Group Map - Visualize contact groups and relationships", systemImage: "circle.hexagongrid")

                        Label("Contact Map - Individual contact visualization", systemImage: "person")
                        Label("Custom - Create your own canvas type", systemImage: "slider.horizontal.3")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Create Canvas")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createCanvas()
                    }
                    .disabled(canvasName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    private func createCanvas() {
        let trimmedName = canvasName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        isCreating = true
        DispatchQueue.global(qos: .userInitiated).async {
            let canvas = canvasService.createCanvas(name: trimmedName, type: selectedType)
            DispatchQueue.main.async {
                isCreating = false
                if canvas != nil {
                    dismiss()
                } else {
                    errorMessage = "Failed to create canvas. Please try again."
                }
            }
        }
    }
}

// MARK: - Extensions

extension CanvasType {
    var displayName: String {
        switch self {
        case .groupMap:
            return "Group Map"

        case .contactMap:
            return "Contact Map"
        case .custom:
            return "Custom"
        }
    }
}

#Preview {
    CanvasManagementView()
}
