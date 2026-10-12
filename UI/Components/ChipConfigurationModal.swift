import SwiftUI

struct ChipConfigurationModal: View {
    let item: ChipDropdownItem
    @Binding var isPresented: Bool
    let onConfirm: (ChipData) -> Void
    
    @State private var chipData: ChipData
    
    init(item: ChipDropdownItem, isPresented: Binding<Bool>, onConfirm: @escaping (ChipData) -> Void) {
        self.item = item
        self._isPresented = isPresented
        self.onConfirm = onConfirm
        
        // Initialize with default values based on chip type
        var data = ChipData(displayText: item.displayText)
        
        switch item.chipType {
        case .contactField:
            data.fieldName = item.fieldName ?? "name"
            data.displayText = "@\(data.fieldName!)"
            
        case .image:
            data.imageUrl = ""
            data.altText = ""
            data.alignment = "center"
            data.displayText = "@image"
            
        case .link:
            data.linkUrl = ""
            data.linkDisplayText = ""
            data.openInNewTab = true
            data.linkStyle = "text"
            data.displayText = "@link"
            
        case .datetime:
            data.dateFormat = "MMM dd, yyyy"
            data.timezone = TimeZone.current.identifier
            data.dateDefaultValue = "now"
            data.displayText = "@date"
            
        case .variable:
            data.variableName = "variable"
            data.variableDefaultValue = ""
            data.variableEditable = true
            data.displayText = "@\(data.variableName!)"
            
        case .attachment:
            data.fileName = ""
            data.filePath = ""
            data.displayText = "@attachment"
        }
        
        self._chipData = State(initialValue: data)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: item.icon)
                    .font(.title2)
                Text("Configure \(item.displayText)")
                    .font(.headline)
            }
            .padding(.top)
            
            Divider()
            
            // Configuration form based on chip type
            ScrollView {
                configurationForm
                    .padding()
            }
            .frame(minHeight: 200, maxHeight: 400)
            
            Divider()
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Button("Insert") {
                    onConfirm(chipData)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding(.bottom)
        }
        .frame(width: 450)
        .padding()
    }
    
    @ViewBuilder
    private var configurationForm: some View {
        switch item.chipType {
        case .contactField:
            contactFieldForm
        case .image:
            imageForm
        case .link:
            linkForm
        case .datetime:
            dateTimeForm
        case .variable:
            variableForm
        case .attachment:
            attachmentForm
        }
    }
    
    // MARK: - Contact Field Form
    private var contactFieldForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Field")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Picker("Field", selection: Binding(
                get: { chipData.fieldName ?? "name" },
                set: { newValue in
                    chipData.fieldName = newValue
                    chipData.displayText = "@\(newValue)"
                }
            )) {
                Text("Full Name").tag("name")
                Text("First Name").tag("first_name")
                Text("Last Name").tag("last_name")
                Text("Phone").tag("phone")
                Text("Email").tag("email")
                Text("Business").tag("business")
                Text("Address").tag("address")
                Text("Birthday").tag("birthday")
                Text("Contact Group").tag("contact_group")
                Text("Notes").tag("notes")
            }
            .pickerStyle(.menu)
            
            Text("This field will be replaced with the contact's \(fieldDescription(chipData.fieldName ?? "name")) when sent.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Image Form
    private var imageForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Image URL")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextField("https://example.com/image.jpg", text: Binding(
                    get: { chipData.imageUrl ?? "" },
                    set: { chipData.imageUrl = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Alt Text (Optional)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextField("Description", text: Binding(
                    get: { chipData.altText ?? "" },
                    set: { chipData.altText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Width (Optional)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    TextField("200", value: Binding(
                        get: { chipData.width ?? 0 },
                        set: { chipData.width = $0 > 0 ? $0 : nil }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Height (Optional)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    TextField("150", value: Binding(
                        get: { chipData.height ?? 0 },
                        set: { chipData.height = $0 > 0 ? $0 : nil }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Alignment")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Picker("Alignment", selection: Binding(
                    get: { chipData.alignment ?? "center" },
                    set: { chipData.alignment = $0 }
                )) {
                    Text("Left").tag("left")
                    Text("Center").tag("center")
                    Text("Right").tag("right")
                }
                .pickerStyle(.segmented)
            }
        }
    }
    
    // MARK: - Link Form
    private var linkForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextField("https://example.com", text: Binding(
                    get: { chipData.linkUrl ?? "" },
                    set: { chipData.linkUrl = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Display Text (Optional)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextField("Click here", text: Binding(
                    get: { chipData.linkDisplayText ?? "" },
                    set: { chipData.linkDisplayText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            
            Toggle("Open in new tab", isOn: Binding(
                get: { chipData.openInNewTab ?? true },
                set: { chipData.openInNewTab = $0 }
            ))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Style")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Picker("Style", selection: Binding(
                    get: { chipData.linkStyle ?? "text" },
                    set: { chipData.linkStyle = $0 }
                )) {
                    Text("Text").tag("text")
                    Text("Button").tag("button")
                }
                .pickerStyle(.segmented)
            }
        }
    }
    
    // MARK: - DateTime Form
    private var dateTimeForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Date Format")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Picker("Format", selection: Binding(
                    get: { chipData.dateFormat ?? "MMM dd, yyyy" },
                    set: { chipData.dateFormat = $0 }
                )) {
                    Text("Jan 15, 2025").tag("MMM dd, yyyy")
                    Text("01/15/2025").tag("MM/dd/yyyy")
                    Text("2025-01-15").tag("yyyy-MM-dd")
                    Text("14:30").tag("HH:mm")
                    Text("2:30 PM").tag("h:mm a")
                    Text("Jan 15, 2025 at 2:30 PM").tag("MMM dd, yyyy 'at' h:mm a")
                }
                .pickerStyle(.menu)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Default Value")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Picker("Default", selection: Binding(
                    get: { chipData.dateDefaultValue ?? "now" },
                    set: { chipData.dateDefaultValue = $0 }
                )) {
                    Text("Now").tag("now")
                    Text("Today").tag("today")
                    Text("Tomorrow").tag("tomorrow")
                    Text("Next Week").tag("next_week")
                    Text("Next Month").tag("next_month")
                }
                .pickerStyle(.menu)
            }
            
            Text("The date/time will be calculated when the message is sent.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Variable Form
    private var variableForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Variable Name")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextField("company_name", text: Binding(
                    get: { chipData.variableName ?? "" },
                    set: { newValue in
                        chipData.variableName = newValue
                        chipData.displayText = "@\(newValue)"
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Default Value (Optional)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextField("Default text", text: Binding(
                    get: { chipData.variableDefaultValue ?? "" },
                    set: { chipData.variableDefaultValue = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            
            Toggle("Editable at send time", isOn: Binding(
                get: { chipData.variableEditable ?? true },
                set: { chipData.variableEditable = $0 }
            ))
            
            Text("Variables can be used to insert custom text that applies to all recipients.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Attachment Form
    private var attachmentForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("File")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                HStack {
                    TextField("No file selected", text: Binding(
                        get: { chipData.fileName ?? "" },
                        set: { chipData.fileName = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
                    
                    Button("Choose File") {
                        selectFile()
                    }
                }
            }
            
            if let filePath = chipData.filePath, !filePath.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("File Path")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(filePath)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Text("The file will be attached to each message when sent.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Validation
    private var isValid: Bool {
        switch item.chipType {
        case .contactField:
            return chipData.fieldName != nil
        case .image:
            return !(chipData.imageUrl?.isEmpty ?? true)
        case .link:
            return !(chipData.linkUrl?.isEmpty ?? true)
        case .datetime:
            return chipData.dateFormat != nil
        case .variable:
            return !(chipData.variableName?.isEmpty ?? true)
        case .attachment:
            return !(chipData.fileName?.isEmpty ?? true) && !(chipData.filePath?.isEmpty ?? true)
        }
    }
    
    // MARK: - Helpers
    private func fieldDescription(_ field: String) -> String {
        switch field {
        case "name": return "full name"
        case "first_name": return "first name"
        case "last_name": return "last name"
        case "phone": return "phone number"
        case "email": return "email address"
        case "business": return "business/company"
        case "address": return "address"
        case "birthday": return "birthday"
        case "contact_group": return "contact group"
        case "notes": return "notes"
        default: return field.replacingOccurrences(of: "_", with: " ")
        }
    }
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let url = panel.url {
            chipData.filePath = url.path
            chipData.fileName = url.lastPathComponent
            
            // Get file size
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileSize = attributes[.size] as? Int {
                chipData.fileSize = fileSize
            }
            
            // Get MIME type
            chipData.mimeType = url.mimeType
            chipData.displayText = "@\(url.lastPathComponent)"
        }
    }
}

// MARK: - URL Extension for MIME Type
extension URL {
    var mimeType: String {
        if let mimeType = UTType(filenameExtension: self.pathExtension)?.preferredMIMEType {
            return mimeType
        }
        return "application/octet-stream"
    }
}

import UniformTypeIdentifiers

