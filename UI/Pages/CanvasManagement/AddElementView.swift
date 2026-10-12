import SwiftUI

struct AddElementView: View {
    let canvas: Canvas
    let canvasService: CanvasUpdateService
    let onElementAdded: (CanvasElement) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedType: ElementType = .contact
    @State private var selectedColor: String = "#007AFF"
    @State private var elementSize: CGFloat = 60
    @State private var elementName = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    
    private let availableColors = [
        "#007AFF", "#34C759", "#FF3B30", "#FF9500", 
        "#AF52DE", "#FF2D92", "#5856D6", "#FF6B35"
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section("Element Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(ElementType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.iconName)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Element Properties") {
                    HStack {
                        Text("Size")
                        Spacer()
                        Slider(value: $elementSize, in: 30...120, step: 5)
                        Text("\(Int(elementSize))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Color")
                        Spacer()
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                            ForEach(availableColors, id: \.self) { color in
                                Circle()
                                    .fill(Color(hex: color) ?? .blue)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        selectedColor = color
                                    }
                            }
                        }
                    }
                }
                
                if selectedType == .custom {
                    Section("Custom Element") {
                        TextField("Element Name", text: $elementName)
                    }
                }
                
                Section("Preview") {
                    HStack {
                        Spacer()
                        ElementPreviewView(
                            type: selectedType,
                            color: selectedColor,
                            size: elementSize,
                            name: elementName.isEmpty ? selectedType.displayName : elementName
                        )
                        Spacer()
                    }
                    .padding(.vertical)
                }
                
                Section {
                    Button("Add Element") {
                        addElement()
                    }
                    .disabled(isAdding)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Add Element")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
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
    
    private func addElement() {
        isAdding = true
        
        // Calculate position in center of canvas
        let centerPosition = CGPoint(x: 200, y: 200) // This would be calculated based on canvas size
        
        let newElement = CanvasElement(
            elementType: selectedType,
            location: centerPosition,
            scale: 1.0,
            width: elementSize,
            height: elementSize,
            rotation: 0,
            color: selectedColor
        )
        
        DispatchQueue.global(qos: .userInitiated).async {
            canvasService.addElement(newElement, to: canvas.id)
            DispatchQueue.main.async {
                isAdding = false
                onElementAdded(newElement)
                dismiss()
            }
        }
    }
}

struct ElementPreviewView: View {
    let type: ElementType
    let color: String
    let size: CGFloat
    let name: String
    
    var body: some View {
        VStack(spacing: 8) {
            Group {
                switch type {
                case .contact:
                    Circle()
                        .fill(Color(hex: color) ?? .blue)
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white)
                                .font(.system(size: size * 0.4))
                        )
                case .group:
                    Circle()
                        .fill(Color(hex: color) ?? .green)
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: "circle.hexagongrid.fill")
                                .foregroundColor(.white)
                                .font(.system(size: size * 0.4))
                        )

                case .custom:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: color) ?? .purple)
                        .frame(width: size * 0.75, height: size * 0.75)
                        .overlay(
                            Image(systemName: "star.fill")
                                .foregroundColor(.white)
                                .font(.system(size: size * 0.3))
                        )
                }
            }
            
            Text(name)
                .font(.caption)
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Extensions

extension ElementType {
    var displayName: String {
        switch self {
        case .contact:
            return "Contact"
        case .group:
            return "Group"

        case .custom:
            return "Custom"
        }
    }
    
    var iconName: String {
        switch self {
        case .contact:
            return "person"
        case .group:
            return "circle.hexagongrid"

        case .custom:
            return "star"
        }
    }
}

#Preview {
    let sampleCanvas = Canvas(name: "Test Canvas", canvasType: .groupMap)
    AddElementView(
        canvas: sampleCanvas,
        canvasService: CanvasUpdateService()
    ) { _ in }
}
