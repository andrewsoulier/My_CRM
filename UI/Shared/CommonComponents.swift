import SwiftUI

// MARK: - Common UI Components

/// Standard search field component used across the app
struct StandardSearchField: View {
    @Binding var searchText: String
    let placeholder: String
    let onSearch: (String) -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $searchText)
                .textFieldStyle(.plain)
                .onChange(of: searchText) { _, newValue in
                    onSearch(newValue)
                }
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    onSearch("")
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

/// Standard segmented picker component
struct StandardSegmentedPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let optionLabels: [String]
    let onSelectionChange: (T) -> Void
    
    var body: some View {
        Picker("", selection: $selection) {
            ForEach(Array(zip(options, optionLabels)), id: \.0) { option, label in
                Text(label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selection) { _, newValue in
            onSelectionChange(newValue)
        }
    }
}

/// Standard toggle with description
struct StandardToggle: View {
    @Binding var isOn: Bool
    let title: String
    let description: String
    let onToggle: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .onChange(of: isOn) { _, newValue in
                    onToggle(newValue)
                }
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// Standard alert button component
struct StandardAlertButton: View {
    let title: String
    let message: String
    let destructive: Bool
    let action: () -> Void
    
    @State private var showingAlert = false
    
    var body: some View {
        Button(title) {
            showingAlert = true
        }
        .foregroundColor(destructive ? .red : .primary)
        .alert(title, isPresented: $showingAlert) {
            Button("Cancel", role: .cancel) { }
            Button(destructive ? "Delete" : "OK", role: destructive ? .destructive : nil) {
                action()
            }
        } message: {
            Text(message)
        }
    }
}
