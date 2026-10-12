import SwiftUI

struct FilterBuilderView: View {
    @Binding var filterModel: FilterModel
    let entityType: GridEntityType
    @Environment(\.dismiss) private var dismiss
    var onApply: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Filter Builder")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    onApply?()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Filter Builder Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FilterGroupView(
                        group: $filterModel.rootGroup,
                        entityType: entityType,
                        nestingLevel: 0
                    )
                }
                .padding()
            }
            .frame(minWidth: 600, minHeight: 400)
        }
        .frame(width: 700, height: 600)
    }
}

// MARK: - Filter Group View

struct FilterGroupView: View {
    @Binding var group: FilterGroup
    let entityType: GridEntityType
    let nestingLevel: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group Header
            HStack {
                if nestingLevel > 0 {
                    Text("Group")
                        .font(.headline)
                } else {
                    Text("Conditions")
                        .font(.headline)
                }
                
                Spacer()
                
                // Add Condition Button
                Button {
                    addCondition()
                } label: {
                    Label("Add Condition", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                
                // Add Group Button
                Button {
                    addNestedGroup()
                } label: {
                    Label("Add Group", systemImage: "plus.square.on.square")
                }
                .buttonStyle(.bordered)
                
            }
            
            // Conditions with AND/OR between them
            ForEach(Array($group.conditions.enumerated()), id: \.element.id) { index, $condition in
                VStack(spacing: 8) {
                    // Show AND/OR picker between items (not before first item)
                    if index > 0 && totalItemsInGroup > 1 {
                        HStack {
                            Spacer()
                            // Conjunction Picker
                            Picker("", selection: $group.conjunction) {
                                ForEach(FilterConjunction.allCases, id: \.self) { conjunction in
                                    Text(conjunction.displayName).tag(conjunction)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    
                    FilterConditionView(
                        condition: $condition,
                        entityType: entityType,
                        onRemove: {
                            group.conditions.removeAll { $0.id == condition.id }
                        }
                    )
                }
            }
            
            // Nested Groups with AND/OR between them
            ForEach(Array($group.nestedGroups.enumerated()), id: \.element.id) { index, $nestedGroup in
                VStack(spacing: 8) {
                    // Show AND/OR picker between items (not before first item)
                    let itemIndex = group.conditions.count + index
                    if itemIndex > 0 && totalItemsInGroup > 1 {
                        HStack {
                            Spacer()
                            // Conjunction Picker
                            Picker("", selection: $group.conjunction) {
                                ForEach(FilterConjunction.allCases, id: \.self) { conjunction in
                                    Text(conjunction.displayName).tag(conjunction)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    
                    HStack(alignment: .top, spacing: 8) {
                        FilterGroupView(
                            group: $nestedGroup,
                            entityType: entityType,
                            nestingLevel: nestingLevel + 1
                        )
                        .padding(.leading, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        )
                        .padding(.vertical, 8)
                        
                        Button {
                            group.nestedGroups.removeAll { $0.id == nestedGroup.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                }
            }
            
            // Empty State
            if group.conditions.isEmpty && group.nestedGroups.isEmpty {
                Text("No conditions. Click 'Add Condition' or 'Add Group' to get started.")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
                    )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(nestingLevel == 0 ? 0 : 0.3))
        )
    }
    
    private func addCondition() {
        let fieldId = availableFields.first?.id ?? ""
        let field = availableFields.first(where: { $0.id == fieldId })
        let defaultOperator = FieldMetadataProvider.operators(for: field?.type ?? .text).first ?? .contains
        
        // Set default dateValueType for date fields
        let dateValueType: DateValueType? = (field?.type == .date) ? .absolute : nil
        
        let newCondition = FilterCondition(
            field: fieldId,
            operator: defaultOperator,
            value: "",
            dateValueType: dateValueType
        )
        group.conditions.append(newCondition)
    }
    
    private func addNestedGroup() {
        let newGroup = FilterGroup(
            conjunction: .and,
            conditions: [],
            nestedGroups: []
        )
        group.nestedGroups.append(newGroup)
    }
    
    private var availableFields: [FieldMetadata] {
        FieldMetadataProvider.fields(for: entityType)
    }
    
    private var totalItemsInGroup: Int {
        group.conditions.count + group.nestedGroups.count
    }
}

// MARK: - Filter Condition View

struct FilterConditionView: View {
    @Binding var condition: FilterCondition
    let entityType: GridEntityType
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Field Selector
            Picker("Field", selection: Binding(
                get: { condition.field },
                set: { newField in
                    condition.field = newField
                    // Reset operator to a valid one for the new field type
                    if let field = availableFields.first(where: { $0.id == newField }) {
                        let validOperators = FieldMetadataProvider.operators(for: field.type)
                        if !validOperators.contains(condition.`operator`) {
                            condition.`operator` = validOperators.first ?? .contains
                        }
                        // Set dateValueType for date fields
                        if field.type == .date {
                            condition.dateValueType = condition.dateValueType ?? .absolute
                        } else {
                            condition.dateValueType = nil
                        }
                    }
                }
            )) {
                ForEach(availableFields, id: \.id) { field in
                    Text(field.displayName).tag(field.id)
                }
            }
            .frame(width: 180)
            
            // Operator Selector
            Picker("", selection: Binding(
                get: { condition.`operator` },
                set: { newOperator in
                    condition.`operator` = newOperator
                    // Auto-set dateValueType for relative date operators
                    if let field = availableFields.first(where: { $0.id == condition.field }),
                       field.type == .date {
                        if newOperator.isRelativeDate {
                            condition.dateValueType = .relative
                        } else if condition.dateValueType == nil {
                            condition.dateValueType = .absolute
                        }
                    }
                }
            )) {
                ForEach(availableOperators, id: \.self) { op in
                    Text(op.displayName).tag(op)
                }
            }
            .frame(width: 150)
            
            // Value Input
            if condition.`operator`.requiresValue {
                if condition.`operator`.requiresMultiSelect {
                    MultiSelectValueInputView(
                        condition: $condition,
                        entityType: entityType
                    )
                } else {
                    FilterValueInputView(
                        condition: $condition,
                        entityType: entityType
                    )
                }
            }
            
            Spacer()
            
            // Remove Button
            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
    }
    
    private var availableFields: [FieldMetadata] {
        FieldMetadataProvider.fields(for: entityType)
    }
    
    private var availableOperators: [FilterOperator] {
        guard let field = availableFields.first(where: { $0.id == condition.field }) else {
            return FilterOperator.allCases
        }
        return FieldMetadataProvider.operators(for: field.type)
    }
}

// MARK: - Filter Value Input View

struct FilterValueInputView: View {
    @Binding var condition: FilterCondition
    let entityType: GridEntityType
    
    var body: some View {
        Group {
            // Check if this is a date field
            if let field = FieldMetadataProvider.fields(for: entityType).first(where: { $0.id == condition.field }),
               field.type == .date {
                // For date fields, use the date value input view (which handles relative/absolute)
                DateValueInputView(condition: $condition)
            } else if condition.`operator` == .between {
                BetweenValueInputView(condition: $condition, entityType: entityType)
            } else {
                StandardValueInputView(condition: $condition, entityType: entityType)
            }
        }
    }
}

// MARK: - Standard Value Input

struct StandardValueInputView: View {
    @Binding var condition: FilterCondition
    let entityType: GridEntityType
    
    var body: some View {
        Group {
            if let field = FieldMetadataProvider.fields(for: entityType).first(where: { $0.id == condition.field }) {
                switch field.type {
                case .text:
                    TextField("Value", text: Binding(
                        get: { condition.value ?? "" },
                        set: { condition.value = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(width: 200)
                    
                case .number:
                    TextField("Value", text: Binding(
                        get: { condition.value ?? "" },
                        set: { condition.value = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(width: 120)
                    
                case .date:
                    DateValueInputView(condition: $condition)
                    
                case .phone, .email, .smartchip:
                    TextField("Value", text: Binding(
                        get: { condition.value ?? "" },
                        set: { condition.value = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(width: 200)
                }
            } else {
                TextField("Value", text: Binding(
                    get: { condition.value ?? "" },
                    set: { condition.value = $0.isEmpty ? nil : $0 }
                ))
                .frame(width: 200)
            }
        }
    }
}

// MARK: - Between Value Input

struct BetweenValueInputView: View {
    @Binding var condition: FilterCondition
    let entityType: GridEntityType
    
    var body: some View {
        HStack {
            TextField("Min", text: Binding(
                get: { condition.value ?? "" },
                set: { condition.value = $0.isEmpty ? nil : $0 }
            ))
            .frame(width: 100)
            
            Text("and")
                .foregroundColor(.secondary)
            
            TextField("Max", text: Binding(
                get: { condition.secondValue ?? "" },
                set: { condition.secondValue = $0.isEmpty ? nil : $0 }
            ))
            .frame(width: 100)
        }
    }
}

// MARK: - Date Value Input

struct DateValueInputView: View {
    @Binding var condition: FilterCondition
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date Value Type Picker (Absolute or Relative)
            Picker("Date Type", selection: Binding(
                get: { condition.dateValueType ?? .absolute },
                set: { 
                    condition.dateValueType = $0
                    // Clear the opposite value type when switching
                    if $0 == .relative {
                        condition.value = nil
                    } else {
                        condition.relativeDateValue = nil
                    }
                }
            )) {
                ForEach(DateValueType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            
            // Show appropriate input based on type
            if condition.dateValueType == .relative {
                RelativeDateInputView(condition: $condition)
            } else {
                // Absolute date picker
                DatePicker("", selection: Binding(
                    get: {
                        if let value = condition.value,
                           let date = ISO8601DateFormatter().date(from: value) {
                            return date
                        }
                        return Date()
                    },
                    set: {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        condition.value = formatter.string(from: $0)
                    }
                ), displayedComponents: [.date, .hourAndMinute])
                .frame(width: 250)
            }
        }
    }
}

// MARK: - Relative Date Input

struct RelativeDateInputView: View {
    @Binding var condition: FilterCondition
    
    var body: some View {
        Group {
            if condition.`operator` == .lastNDaysAgo {
                HStack {
                    TextField("Amount", value: Binding(
                        get: { condition.relativeDateValue?.amount },
                        set: {
                            if condition.relativeDateValue == nil {
                                condition.relativeDateValue = RelativeDateValue()
                            }
                            condition.relativeDateValue?.amount = $0
                        }
                    ), format: .number)
                    .frame(width: 80)
                    
                    Picker("", selection: Binding(
                        get: { condition.relativeDateValue?.unit ?? .days },
                        set: {
                            if condition.relativeDateValue == nil {
                                condition.relativeDateValue = RelativeDateValue()
                            }
                            condition.relativeDateValue?.unit = $0
                        }
                    )) {
                        ForEach(RelativeDateValue.RelativeDateUnit.allCases, id: \.self) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .frame(width: 100)
                    
                    Text("ago")
                        .foregroundColor(.secondary)
                }
            } else {
                // For lastWeek, lastMonth, lastYear - no input needed
                Text(condition.`operator`.displayName)
                    .foregroundColor(.secondary)
                    .frame(width: 150)
            }
        }
    }
}

// MARK: - Multi-Select Value Input

struct MultiSelectValueInputView: View {
    @Binding var condition: FilterCondition
    let entityType: GridEntityType
    @State private var availableOptions: [String] = []
    @State private var isLoading: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ProgressView()
                    .frame(width: 200)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(availableOptions, id: \.self) { option in
                            HStack {
                                Button {
                                    toggleSelection(option)
                                } label: {
                                    Image(systemName: isSelected(option) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(isSelected(option) ? .blue : .secondary)
                                }
                                .buttonStyle(.plain)
                                
                                Text(option)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleSelection(option)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 200)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
        }
        .frame(width: 300)
        .onAppear {
            loadAvailableOptions()
        }
        .onChange(of: condition.field) { _ in
            loadAvailableOptions()
        }
    }
    
    private func isSelected(_ option: String) -> Bool {
        condition.selectedValues?.contains(option) ?? false
    }
    
    private func toggleSelection(_ option: String) {
        if condition.selectedValues == nil {
            condition.selectedValues = []
        }
        
        if let index = condition.selectedValues?.firstIndex(of: option) {
            condition.selectedValues?.remove(at: index)
        } else {
            condition.selectedValues?.append(option)
        }
    }
    
    private func loadAvailableOptions() {
        isLoading = true
        Task {
            let options = await SmartChipOptionsProvider.fetchOptions(for: condition.field, entityType: entityType)
            await MainActor.run {
                availableOptions = options
                isLoading = false
            }
        }
    }
}

// MARK: - Smart Chip Options Provider

struct SmartChipOptionsProvider {
    static func fetchOptions(for fieldId: String, entityType: GridEntityType) async -> [String] {
        switch fieldId {
        case "contact.groups":
            return await fetchGroupNames()
        case "contact.tags":
            return await fetchContactTags()
        case "contact.relationships":
            return await fetchRelationshipTypes()
        case "group.participants":
            return await fetchParticipantNames()
        case "group.tags":
            return await fetchGroupTags()
        case "group.children":
            return await fetchGroupNames() // Children are groups
        case "group.parents":
            return await fetchGroupNames() // Parents are groups
        default:
            return []
        }
    }
    
    private static func fetchGroupNames() async -> [String] {
        let dbManager = GRDBDatabaseManager.shared
        
        do {
            return try await dbManager.read { db in
                do {
                    let groups = try ContactGroup.fetchAll(db)
                    return groups.map { $0.name }.sorted()
                } catch {
                    return []
                }
            }
        } catch {
            return []
        }
    }
    
    @MainActor
    private static func fetchContactTags() async -> [String] {
        let tagRepo = TagRepository()
        do {
            let tags = try await tagRepo.fetchAll()
            return tags.map { $0.name }.sorted()
        } catch {
            return []
        }
    }
    
    @MainActor
    private static func fetchRelationshipTypes() async -> [String] {
        let relationshipRepo = RelationshipRepository()
        do {
            let relationships = try await relationshipRepo.fetchAll()
            return relationships.map { $0.name }.sorted()
        } catch {
            return []
        }
    }
    
    private static func fetchParticipantNames() async -> [String] {
        let dbManager = GRDBDatabaseManager.shared
        
        do {
            return try await dbManager.read { db in
                do {
                    let contacts = try Contact.fetchAll(db)
                    return contacts.map { $0.displayName }.filter { !$0.isEmpty }.sorted()
                } catch {
                    return []
                }
            }
        } catch {
            return []
        }
    }
    
    @MainActor
    private static func fetchGroupTags() async -> [String] {
        let tagRepo = TagRepository()
        do {
            let tags = try await tagRepo.fetchAll()
            return tags.map { $0.name }.sorted()
        } catch {
            return []
        }
    }
}

// MARK: - Field Metadata

struct FieldMetadata {
    let id: String
    let displayName: String
    let type: FieldType
}

enum FieldType {
    case text
    case number
    case date
    case phone
    case email
    case smartchip
}

// MARK: - Field Metadata Provider

struct FieldMetadataProvider {
    static func fields(for entityType: GridEntityType) -> [FieldMetadata] {
        switch entityType {
        case .contacts:
            return [
                FieldMetadata(id: "contact.name", displayName: "Name", type: .text),
                FieldMetadata(id: "contact.first_name", displayName: "First Name", type: .text),
                FieldMetadata(id: "contact.last_name", displayName: "Last Name", type: .text),
                FieldMetadata(id: "contact.nickname", displayName: "Nickname", type: .text),
                FieldMetadata(id: "contact.phone", displayName: "Phone", type: .phone),
                FieldMetadata(id: "contact.email", displayName: "Email", type: .email),
                FieldMetadata(id: "contact.address", displayName: "Address", type: .text),
                FieldMetadata(id: "contact.notes", displayName: "Notes", type: .text),
                FieldMetadata(id: "contact.creation_date", displayName: "Creation Date", type: .date),
                FieldMetadata(id: "contact.birthday", displayName: "Birthday", type: .date),
                FieldMetadata(id: "contact.total_messages", displayName: "Total Messages", type: .number),
                FieldMetadata(id: "contact.messages_sent", displayName: "Messages Sent", type: .number),
                FieldMetadata(id: "contact.messages_received", displayName: "Messages Received", type: .number),
                FieldMetadata(id: "contact.last_message_received", displayName: "Last Message Received", type: .date),
                FieldMetadata(id: "contact.last_message_sent", displayName: "Last Message Sent", type: .date),
                FieldMetadata(id: "contact.groups", displayName: "Groups", type: .smartchip),
                FieldMetadata(id: "contact.tags", displayName: "Tags", type: .smartchip),
                FieldMetadata(id: "contact.relationships", displayName: "Relationships", type: .smartchip)
            ]
        case .groups:
            return [
                FieldMetadata(id: "group.name", displayName: "Name", type: .text),
                FieldMetadata(id: "group.participants", displayName: "Participants", type: .smartchip),
                FieldMetadata(id: "group.color", displayName: "Color", type: .text),
                FieldMetadata(id: "group.created_at", displayName: "Created At", type: .date),
                FieldMetadata(id: "group.size", displayName: "Size", type: .number),
                FieldMetadata(id: "group.tags", displayName: "Tags", type: .smartchip),
                FieldMetadata(id: "group.children", displayName: "Children", type: .smartchip),
                FieldMetadata(id: "group.parents", displayName: "Parents", type: .smartchip)
            ]
        }
    }
    
    static func operators(for fieldType: FieldType) -> [FilterOperator] {
        switch fieldType {
        case .text, .phone, .email:
            return [.contains, .equals, .startsWith, .endsWith, .isEmpty, .isNotEmpty]
        case .number:
            return [.equals, .greaterThan, .lessThan, .between]
        case .date:
            return [.is, .before, .after, .onOrBefore, .onOrAfter, .lastNDaysAgo, .lastWeek, .lastMonth, .lastYear]
        case .smartchip:
            return [.contains, .equals, .isEmpty, .isNotEmpty, .containsAnyOf, .containsNoneOf]
        }
    }
}

