import SwiftUI

struct ChipDropdownView: View {
    let position: CGPoint
    let filterText: String
    @Binding var selectedIndex: Int
    let availableFields: [String]
    let onSelectChip: (ChipDropdownItem) -> Void
    let onFilteredItemsChange: (([ChipDropdownItem]) -> Void)?
    
    @State private var filteredItems: [ChipDropdownSection] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(filteredItems.enumerated()), id: \.offset) { sectionIndex, section in
                            if !section.items.isEmpty {
                                // Section header
                                Text(section.title)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .padding(.top, sectionIndex > 0 ? 4 : 0)
                                
                                // Section items
                                ForEach(Array(section.items.enumerated()), id: \.element.id) { itemIndex, item in
                                    let globalIndex = calculateGlobalIndex(sectionIndex: sectionIndex, itemIndex: itemIndex)
                                    
                                    let _ = print("📺 DEBUG: Rendering item: \(item.displayText), globalIndex: \(globalIndex), isSelected: \(globalIndex == selectedIndex)")
                                    
                                    ChipDropdownRow(
                                        item: item,
                                        isSelected: globalIndex == selectedIndex,
                                        onSelect: {
                                            onSelectChip(item)
                                        }
                                    )
                                    .id(globalIndex)  // Give each row a unique ID for scrolling
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
                .onChange(of: selectedIndex) { _, newIndex in
                    // Auto-scroll to the selected item
                    withAnimation(.easeInOut(duration: 0.15)) {
                        scrollProxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .id("dropdown-\(filterText)-\(selectedIndex)")  // Force re-render on changes
        .frame(width: 250)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        .onAppear {
            updateFilteredItems()
        }
        .onChange(of: filterText) { oldValue, newValue in
            print("📥 DEBUG: filterText changed from '\(oldValue)' to '\(newValue)'")
            updateFilteredItems()
            // Reset selection to first item when filter changes
            selectedIndex = 0
        }
    }
    
    private func updateFilteredItems() {
        let allSections = createAllSections()
        
        if filterText.isEmpty {
            filteredItems = allSections
        } else {
            // Filter items based on text
            filteredItems = allSections.map { section in
                let filtered = section.items.filter { item in
                    item.matchText.localizedCaseInsensitiveContains(filterText)
                }
                return ChipDropdownSection(title: section.title, items: filtered)
            }
        }
        
        // Get all items for reporting
        let allItems = filteredItems.flatMap { $0.items }
        let totalItems = allItems.count
        
        // Ensure selected index is valid (but don't reset here - that's handled in onChange)
        if selectedIndex >= totalItems && totalItems > 0 {
            selectedIndex = totalItems - 1
        } else if totalItems == 0 {
            selectedIndex = 0
        }
        
        // Notify parent of filtered items for keyboard navigation
        onFilteredItemsChange?(allItems)
        
        print("🔍 DEBUG: Filtered items updated - total: \(totalItems), selectedIndex: \(selectedIndex)")
        print("🔍 DEBUG: Filter text: '\(filterText)'")
        print("🔍 DEBUG: All filtered items: \(allItems.map { $0.displayText })")
    }
    
    private func createAllSections() -> [ChipDropdownSection] {
        var sections: [ChipDropdownSection] = []
        
        // Contact Fields section
        let contactFieldItems = availableFields.map { field in
            ChipDropdownItem(
                id: "contact_\(field)",
                displayText: "@\(field)",
                description: fieldDescription(for: field),
                icon: "person.fill",
                chipType: .contactField,
                matchText: field,
                fieldName: field
            )
        }
        sections.append(ChipDropdownSection(title: "Contact Fields", items: contactFieldItems))
        
        // Media section
        let mediaItems = [
            ChipDropdownItem(
                id: "image",
                displayText: "Image",
                description: "Insert an image",
                icon: "photo.fill",
                chipType: .image,
                matchText: "image"
            ),
            ChipDropdownItem(
                id: "attachment",
                displayText: "Attachment",
                description: "Attach a file",
                icon: "doc.fill",
                chipType: .attachment,
                matchText: "attachment file"
            )
        ]
        sections.append(ChipDropdownSection(title: "Media", items: mediaItems))
        
        // Date & Time section
        let dateTimeItems = [
            ChipDropdownItem(
                id: "datetime",
                displayText: "Date & Time",
                description: "Insert date/time",
                icon: "calendar",
                chipType: .datetime,
                matchText: "date time datetime"
            )
        ]
        sections.append(ChipDropdownSection(title: "Date & Time", items: dateTimeItems))
        
        // Variables section
        let variableItems = [
            ChipDropdownItem(
                id: "variable",
                displayText: "Variable",
                description: "Custom variable",
                icon: "textformat.abc",
                chipType: .variable,
                matchText: "variable var"
            )
        ]
        sections.append(ChipDropdownSection(title: "Variables", items: variableItems))
        
        // Links section
        let linkItems = [
            ChipDropdownItem(
                id: "link",
                displayText: "Link",
                description: "Insert a link",
                icon: "link",
                chipType: .link,
                matchText: "link url"
            )
        ]
        sections.append(ChipDropdownSection(title: "Links", items: linkItems))
        
        return sections
    }
    
    private func calculateGlobalIndex(sectionIndex: Int, itemIndex: Int) -> Int {
        var index = 0
        for i in 0..<sectionIndex {
            index += filteredItems[i].items.count
        }
        index += itemIndex
        return index
    }
    
    private func fieldDescription(for field: String) -> String {
        switch field {
        case "name": return "Full name"
        case "first_name": return "First name"
        case "last_name": return "Last name"
        case "phone": return "Phone number"
        case "email": return "Email address"
        case "business": return "Business/Company"
        case "address": return "Address"
        case "birthday": return "Birthday"
        case "contact_group": return "Contact group"
        case "notes": return "Notes"
        default: return field.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - Dropdown Row
struct ChipDropdownRow: View {
    let item: ChipDropdownItem
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Icon
                Image(systemName: item.icon)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(width: 16)
                
                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayText)
                        .font(.body)
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(item.description)
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Data Structures
struct ChipDropdownSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [ChipDropdownItem]
}

struct ChipDropdownItem: Identifiable {
    let id: String
    let displayText: String
    let description: String
    let icon: String
    let chipType: ChipType
    let matchText: String
    
    // Contact field specific
    var fieldName: String?
    
    init(
        id: String,
        displayText: String,
        description: String,
        icon: String,
        chipType: ChipType,
        matchText: String,
        fieldName: String? = nil
    ) {
        self.id = id
        self.displayText = displayText
        self.description = description
        self.icon = icon
        self.chipType = chipType
        self.matchText = matchText
        self.fieldName = fieldName
    }
}

// MARK: - Window Overlay Helper
struct ChipDropdownWindow: View {
    let position: CGPoint
    let filterText: String
    @Binding var selectedIndex: Int
    let availableFields: [String]
    let onSelectChip: (ChipDropdownItem) -> Void
    let onFilteredItemsChange: (([ChipDropdownItem]) -> Void)?
    @Binding var isVisible: Bool
    
    var body: some View {
        if isVisible {
            GeometryReader { geometry in
                ChipDropdownView(
                    position: position,
                    filterText: filterText,
                    selectedIndex: $selectedIndex,
                    availableFields: availableFields,
                    onSelectChip: onSelectChip,
                    onFilteredItemsChange: onFilteredItemsChange
                )
                .position(x: position.x, y: geometry.size.height - position.y)
            }
        }
    }
}

