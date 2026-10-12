import SwiftUI

struct CanvasEditorView: View {
    let canvas: Canvas
    let canvasService: CanvasUpdateService
    
    @State private var currentCanvas: Canvas
    @State private var selectedElements: Set<String> = []
    @State private var showingAddElement = false
    @State private var showingCanvasSettings = false
    @State private var isUpdating = false
    @State private var errorMessage: String?
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    
    init(canvas: Canvas, canvasService: CanvasUpdateService) {
        self.canvas = canvas
        self.canvasService = canvasService
        self._currentCanvas = State(initialValue: canvas)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            CanvasToolbarView(
                canvas: currentCanvas,
                selectedElements: selectedElements,
                onAddElement: { showingAddElement = true },
                onSettings: { showingCanvasSettings = true },
                onDeleteSelected: deleteSelectedElements
            )
            
            // Canvas area
            CanvasAreaView(
                canvas: $currentCanvas,
                selectedElements: $selectedElements,
                dragOffset: $dragOffset,
                isDragging: $isDragging,
                isSelectionMode: true, // Canvas editor is always in selection mode
                onElementMoved: handleElementMoved,
                onElementSelected: handleElementSelected,
                onElementDeselected: handleElementDeselected
            )
        }
        .navigationTitle(currentCanvas.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveCanvas()
                }
                .disabled(isUpdating)
            }
        }
        .sheet(isPresented: $showingAddElement) {
            AddElementView(canvas: currentCanvas, canvasService: canvasService) { newElement in
                addElement(newElement)
            }
        }
        .sheet(isPresented: $showingCanvasSettings) {
            CanvasSettingsView(canvas: $currentCanvas, canvasService: canvasService)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .onChange(of: currentCanvas.id) { oldId, newId in
            // Auto-save on changes (debounced by the service)
            saveCanvas()
        }
    }
    
    private func handleElementMoved(_ elementId: String, newLocation: CGPoint) {
        guard let index = currentCanvas.elements.firstIndex(where: { $0.id == elementId }) else { return }
        currentCanvas.elements[index].location = newLocation
    }
    
    private func handleElementSelected(_ elementId: String) {
        selectedElements.insert(elementId)
    }
    
    private func handleElementDeselected(_ elementId: String) {
        selectedElements.remove(elementId)
    }
    
    private func addElement(_ element: CanvasElement) {
        currentCanvas.elements.append(element)
        selectedElements.removeAll()
        selectedElements.insert(element.id)
    }
    
    private func deleteSelectedElements() {
        currentCanvas.elements.removeAll { selectedElements.contains($0.id) }
        selectedElements.removeAll()
    }
    
    private func saveCanvas() {
        isUpdating = true
        DispatchQueue.global(qos: .userInitiated).async {
            let success = canvasService.updateCanvas(currentCanvas)
            DispatchQueue.main.async {
                isUpdating = false
                if !success {
                    errorMessage = "Failed to save canvas changes"
                }
            }
        }
    }
}

struct CanvasToolbarView: View {
    let canvas: Canvas
    let selectedElements: Set<String>
    let onAddElement: () -> Void
    let onSettings: () -> Void
    let onDeleteSelected: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Canvas info
            VStack(alignment: .leading, spacing: 2) {
                Text(canvas.canvasType.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(canvas.elementCounts.all) elements")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: onAddElement) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(.bordered)
                
                if !selectedElements.isEmpty {
                    Button(action: onDeleteSelected) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(action: onSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
}

struct CanvasAreaView: View {
    @Binding var canvas: Canvas
    @Binding var selectedElements: Set<String>
    @Binding var dragOffset: CGSize
    @Binding var isDragging: Bool
    
    let isSelectionMode: Bool
    let onElementMoved: (String, CGPoint) -> Void
    let onElementSelected: (String) -> Void
    let onElementDeselected: (String) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Canvas background
                CanvasBackgroundView(canvas: canvas)
                
                // Canvas elements
                ForEach(canvas.elements) { element in
                    CanvasElementView(
                        element: element,
                        isSelected: selectedElements.contains(element.id),
                        isSelectionMode: isSelectionMode,
                        onTap: {
                            if selectedElements.contains(element.id) {
                                onElementDeselected(element.id)
                            } else {
                                onElementSelected(element.id)
                            }
                        },
                        onDragChanged: { offset in
                            dragOffset = offset
                            isDragging = true
                        },
                        onDragEnded: { offset in
                            let newLocation = CGPoint(
                                x: element.location.x + offset.width,
                                y: element.location.y + offset.height
                            )
                            onElementMoved(element.id, newLocation)
                            isDragging = false
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }
}

struct CanvasBackgroundView: View {
    let canvas: Canvas
    
    var body: some View {
        ZStack {
            // Grid background
            if canvas.canvasState.gridEnabled {
                CanvasGridBackground(gridSize: canvas.canvasState.gridSize)
            }
            
            // Canvas state overlay
            CanvasStateOverlay(canvas: canvas)
        }
    }
}

struct CanvasGridBackground: View {
    let gridSize: CGFloat
    
    var body: some View {
        SwiftUI.Canvas { context, size in
            let width = size.width
            let height = size.height
            
            // Draw vertical lines
            for x in stride(from: 0, through: width, by: gridSize) {
                let path = Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
                context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
            }
            
            // Draw horizontal lines
            for y in stride(from: 0, through: height, by: gridSize) {
                let path = Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
                context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
            }
        }
    }
}

struct CanvasStateOverlay: View {
    let canvas: Canvas
    
    var body: some View {
        // This would show zoom level, pan position, etc.
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Zoom: \(String(format: "%.1f", canvas.canvasState.zoom))x")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Grid: \(canvas.canvasState.gridEnabled ? "On" : "Off")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .cornerRadius(8)
                .padding()
            }
        }
    }
}

struct CanvasElementView: View {
    let element: CanvasElement
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void
    
    var body: some View {
        Group {
            switch element.elementType {
            case .contact:
                ContactElementView(element: element, isSelected: isSelected)
            case .group:
                GroupElementView(element: element, isSelected: isSelected)

            case .custom:
                CustomElementView(element: element, isSelected: isSelected)
            }
        }
        .position(element.location)
        .scaleEffect(element.scale)
        .rotationEffect(.radians(element.rotation))
        .onTapGesture {
            onTap()
        }
        .simultaneousGesture(
            // Enable drag gesture when in selection mode
            isSelectionMode ? DragGesture(minimumDistance: 0)
                .onChanged { value in
                    onDragChanged(value.translation)
                }
                .onEnded { value in
                    onDragEnded(value.translation)
                } : nil
        )
        .overlay(
            // Blue selection glow - unified pattern
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.blue, lineWidth: 3)
                .opacity(isSelected ? 0.8 : 0)
                .blur(radius: 2)
        )
    }
}

struct ContactElementView: View {
    let element: CanvasElement
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(Color(hex: element.color) ?? .blue)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 20))
                )
            
            Text("Contact")
                .font(.caption2)
                .foregroundColor(.primary)
        }
        .frame(width: element.width, height: element.height)
    }
}

struct GroupElementView: View {
    let element: CanvasElement
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(Color(hex: element.color) ?? .green)
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "circle.hexagongrid.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 24))
                )
            
            Text("Group")
                .font(.caption2)
                .foregroundColor(.primary)
        }
        .frame(width: element.width, height: element.height)
    }
}



struct CustomElementView: View {
    let element: CanvasElement
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: element.color) ?? .purple)
                .frame(width: 45, height: 45)
                .overlay(
                    Image(systemName: "star.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 20))
                )
            
            Text("Custom")
                .font(.caption2)
                .foregroundColor(.primary)
        }
        .frame(width: element.width, height: element.height)
    }
}

#Preview {
    let sampleCanvas = Canvas(
        name: "Sample Canvas",
        elements: [
            CanvasElement(
                elementType: .contact,
                location: CGPoint(x: 100, y: 100),
                color: "#007AFF"
            ),
            CanvasElement(
                elementType: .group,
                location: CGPoint(x: 200, y: 200),
                color: "#34C759"
            )
        ],
        canvasType: .groupMap
    )
    
    CanvasEditorView(
        canvas: sampleCanvas,
        canvasService: CanvasUpdateService()
    )
}
