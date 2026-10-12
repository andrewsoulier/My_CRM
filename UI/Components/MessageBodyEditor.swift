import SwiftUI

struct MessageBodyEditor: View {
    @Binding var text: String
    @Binding var chipMetadata: ChipMetadata?
    let availableFields: [String]
    @Binding var fieldSuggestions: [String]
    @Binding var showingFieldSuggestions: Bool
    
    @State private var showingDropdown = false
    @State private var dropdownPosition: CGPoint = .zero
    @State private var dropdownFilter: String = ""
    @State private var selectedDropdownIndex: Int = 0
    @State private var showingConfigModal = false
    @State private var selectedChipItem: ChipDropdownItem?
    @State private var editingChip: SmartChip?
    
    // Reference to the ChipTextView coordinator for inserting chips
    @State private var chipTextViewCoordinator: ChipTextView.Coordinator?
    
    // Filtered items for keyboard navigation
    @State private var currentFilteredItems: [ChipDropdownItem] = []
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main text editor
            ChipTextView(
                text: $text,
                chipMetadata: $chipMetadata,
                availableFields: availableFields,
                showingDropdown: $showingDropdown,
                dropdownPosition: $dropdownPosition,
                dropdownFilter: $dropdownFilter,
                selectedDropdownIndex: $selectedDropdownIndex,
                totalFilteredItems: currentFilteredItems.count,
                onChipEdit: { chip in
                    handleChipEdit(chip)
                },
                onKeyboardSelect: {
                    handleKeyboardSelection()
                },
                onCoordinatorReady: { coordinator in
                    chipTextViewCoordinator = coordinator
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Dropdown overlay
            if showingDropdown {
                dropdownOverlay
                    .zIndex(1000)
                    .onAppear {
                        print("🎨 DEBUG: Dropdown overlay appeared")
                    }
            }
        }
        .onChange(of: showingDropdown) { oldValue, newValue in
            print("🔄 DEBUG: showingDropdown changed from \(oldValue) to \(newValue)")
        }
        .sheet(isPresented: $showingConfigModal) {
            if let item = selectedChipItem {
                ChipConfigurationModal(
                    item: item,
                    isPresented: $showingConfigModal,
                    onConfirm: { chipData in
                        insertChipWithData(item: item, chipData: chipData)
                    }
                )
            }
        }
    }
    
    // MARK: - Dropdown Overlay
    private var dropdownOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
                .frame(height: 10) // Small offset from top
            
            HStack(alignment: .top, spacing: 0) {
                Spacer()
                    .frame(width: 20) // Left offset
                
ChipDropdownView(
                    position: dropdownPosition,
                    filterText: dropdownFilter,
                    selectedIndex: $selectedDropdownIndex,
                    availableFields: availableFields,
                    onSelectChip: { item in
                        handleDropdownSelection(item)
                    },
                    onFilteredItemsChange: { items in
                        currentFilteredItems = items
                    }
                )
                
                Spacer()
            }
            
            Spacer()
        }
    }
    
    // MARK: - Dropdown Selection Handling
    private func handleDropdownSelection(_ item: ChipDropdownItem) {
        // Check if this chip type needs configuration
        if needsConfiguration(item.chipType) {
            selectedChipItem = item
            showingConfigModal = true
        } else {
            // Insert directly for simple chips (like contact fields)
            let chipData = createDefaultChipData(for: item)
            insertChipWithData(item: item, chipData: chipData)
        }
        
        showingDropdown = false
    }
    
    // MARK: - Keyboard Selection Handling
    private func handleKeyboardSelection() {
        print("⌨️ DEBUG: handleKeyboardSelection called with index \(selectedDropdownIndex), total items: \(currentFilteredItems.count)")
        
        guard selectedDropdownIndex >= 0 && selectedDropdownIndex < currentFilteredItems.count else {
            print("❌ DEBUG: Invalid index \(selectedDropdownIndex) for \(currentFilteredItems.count) items")
            return
        }
        
        let selectedItem = currentFilteredItems[selectedDropdownIndex]
        print("✅ DEBUG: Selected item: \(selectedItem.displayText)")
        
        handleDropdownSelection(selectedItem)
    }
    
    private func needsConfiguration(_ chipType: ChipType) -> Bool {
        switch chipType {
        case .contactField:
            return false // Can insert with default field
        case .image, .link, .datetime, .variable, .attachment:
            return true
        }
    }
    
    private func createDefaultChipData(for item: ChipDropdownItem) -> ChipData {
        var data = ChipData(displayText: item.displayText)
        
        switch item.chipType {
        case .contactField:
            data.fieldName = item.fieldName ?? "name"
            data.displayText = "@\(data.fieldName!)"
        default:
            break
        }
        
        return data
    }
    
    private func insertChipWithData(item: ChipDropdownItem, chipData: ChipData) {
        // Use the coordinator to insert the actual chip pill
        chipTextViewCoordinator?.insertChip(chipType: item.chipType, chipData: chipData)
    }
    
    private func updateChipMetadataWithNewChip(chipData: ChipData, chipType: ChipType) {
        var chips = chipMetadata?.chips ?? []
        
        let newChip = createSmartChip(chipType: chipType, chipData: chipData)
        chips.append(newChip)
        
        chipMetadata = ChipMetadata(chips: chips, version: "2.0")
    }
    
    private func createSmartChip(chipType: ChipType, chipData: ChipData) -> SmartChip {
        let displayText = chipData.displayText
        
        switch chipType {
        case .contactField:
            return SmartChip.contactField(
                field: chipData.fieldName ?? "name",
                startIndex: 0,
                endIndex: displayText.count,
                displayText: displayText
            )
            
        case .image:
            let metadata = ImageChipMetadata(
                imageUrl: chipData.imageUrl ?? "",
                altText: chipData.altText,
                width: chipData.width,
                height: chipData.height,
                alignment: chipData.alignment
            )
            return SmartChip.image(
                startIndex: 0,
                endIndex: displayText.count,
                displayText: displayText,
                metadata: metadata
            )
            
        case .link:
            let metadata = LinkChipMetadata(
                url: chipData.linkUrl ?? "",
                displayText: chipData.linkDisplayText,
                openInNewTab: chipData.openInNewTab,
                style: chipData.linkStyle
            )
            return SmartChip.link(
                startIndex: 0,
                endIndex: displayText.count,
                displayText: displayText,
                metadata: metadata
            )
            
        case .datetime:
            let metadata = DateTimeChipMetadata(
                format: chipData.dateFormat ?? "MMM dd, yyyy",
                timezone: chipData.timezone,
                defaultValue: chipData.dateDefaultValue
            )
            return SmartChip.datetime(
                startIndex: 0,
                endIndex: displayText.count,
                displayText: displayText,
                metadata: metadata
            )
            
        case .variable:
            let metadata = VariableChipMetadata(
                variableName: chipData.variableName ?? "variable",
                defaultValue: chipData.variableDefaultValue,
                editable: chipData.variableEditable
            )
            return SmartChip.variable(
                startIndex: 0,
                endIndex: displayText.count,
                displayText: displayText,
                metadata: metadata
            )
            
        case .attachment:
            let metadata = AttachmentChipMetadata(
                filePath: chipData.filePath ?? "",
                fileName: chipData.fileName ?? "file",
                fileSize: chipData.fileSize,
                mimeType: chipData.mimeType
            )
            return SmartChip.attachment(
                startIndex: 0,
                endIndex: displayText.count,
                displayText: displayText,
                metadata: metadata
            )
        }
    }
    
    // MARK: - Chip Editing
    private func handleChipEdit(_ chip: SmartChip) {
        editingChip = chip
        
        // Create a ChipDropdownItem from the chip for editing
        let item = createDropdownItemFromChip(chip)
        selectedChipItem = item
        showingConfigModal = true
    }
    
    private func createDropdownItemFromChip(_ chip: SmartChip) -> ChipDropdownItem {
        let icon = chip.type.icon
        let displayText = chip.displayText
        let description = chip.type.displayName
        
        return ChipDropdownItem(
            id: chip.id,
            displayText: displayText,
            description: description,
            icon: icon,
            chipType: chip.type,
            matchText: displayText,
            fieldName: chip.field
        )
    }
}
