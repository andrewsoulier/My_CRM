import SwiftUI

struct CanvasSettingsView: View {
    @Binding var canvas: Canvas
    let canvasService: CanvasUpdateService
    
    @Environment(\.dismiss) private var dismiss
    @State private var isUpdating = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            Form {
                Section("Canvas Information") {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(canvas.name)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Type")
                        Spacer()
                        Text(canvas.canvasType.displayName)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Created")
                        Spacer()
                        Text(canvas.dateCreated, style: .date)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Last Updated")
                        Spacer()
                        Text(canvas.dateUpdated, style: .relative)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Display Settings") {
                    Toggle("Show Grid", isOn: $canvas.canvasState.gridEnabled)
                    
                    if canvas.canvasState.gridEnabled {
                        HStack {
                            Text("Grid Size")
                            Spacer()
                            Slider(value: $canvas.canvasState.gridSize, in: 4...20, step: 2)
                            Text("\(Int(canvas.canvasState.gridSize))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Toggle("Snap to Grid", isOn: $canvas.canvasState.snapToGrid)
                    }
                    
                    HStack {
                        Text("Zoom Level")
                        Spacer()
                        Slider(value: $canvas.canvasState.zoom, in: 0.02...3.0, step: 0.01)
                        Text("\(String(format: "%.2f", canvas.canvasState.zoom))x")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Element Statistics") {
                    HStack {
                        Text("Total Elements")
                        Spacer()
                        Text("\(canvas.elementCounts.all)")
                            .foregroundColor(.secondary)
                    }
                    
                    if canvas.elementCounts.contacts > 0 {
                        HStack {
                            Label("Contacts", systemImage: "person")
                            Spacer()
                            Text("\(canvas.elementCounts.contacts)")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if canvas.elementCounts.groups > 0 {
                        HStack {
                            Label("Groups", systemImage: "circle.hexagongrid")
                            Spacer()
                            Text("\(canvas.elementCounts.groups)")
                                .foregroundColor(.secondary)
                        }
                    }
                    

                }
                
                Section("Actions") {
                    Button("Reset Canvas State") {
                        resetCanvasState()
                    }
                    .foregroundColor(.orange)
                    
                    Button("Export Canvas Data") {
                        exportCanvasData()
                    }
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("Canvas Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSettings()
                    }
                    .disabled(isUpdating)
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
    
    private func saveSettings() {
        isUpdating = true
        DispatchQueue.global(qos: .userInitiated).async {
            let success = canvasService.updateCanvas(canvas)
            DispatchQueue.main.async {
                isUpdating = false
                if success {
                    dismiss()
                } else {
                    errorMessage = "Failed to save settings"
                }
            }
        }
    }
    
    private func resetCanvasState() {
        var resetState = CanvasState()
        resetState.mode = .select // Ensure default mode is selection
        canvas.canvasState = resetState
    }
    
    private func exportCanvasData() {
        // This would export the canvas data as JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let data = try encoder.encode(canvas)
            if let jsonString = String(data: data, encoding: .utf8) {
                // In a real app, you'd save this to a file or share it
                print("Canvas Data:")
                print(jsonString)
            }
        } catch {
            errorMessage = "Failed to export canvas data"
        }
    }
}

#Preview {
    let sampleCanvas = Canvas(
        name: "Sample Canvas",
        elements: [
            CanvasElement(elementType: .contact, location: CGPoint(x: 100, y: 100)),
            CanvasElement(elementType: .group, location: CGPoint(x: 200, y: 200))
        ],
        canvasType: .groupMap
    )
    
    CanvasSettingsView(
        canvas: .constant(sampleCanvas),
        canvasService: CanvasUpdateService()
    )
}
