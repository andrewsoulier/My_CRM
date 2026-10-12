import SwiftUI

struct GridViewPage: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = GridViewViewModel()
    @State private var newColumnName = ""
    @State private var newColumnType: GridColumnDataType = .text
    @FocusState private var isSearchFieldFocused: Bool
    @State private var editingViewId: UUID?
    @State private var editingName: String = ""
    @FocusState private var isNameFieldFocused: Bool
    
    var body: some View {
        mainContent
            .modifier(SearchOverlayModifier(viewModel: viewModel, isSearchFieldFocused: $isSearchFieldFocused))
            .modifier(ErrorOverlayModifier(viewModel: viewModel))
            .modifier(KeyboardShortcutsModifier(viewModel: viewModel, editingViewId: $editingViewId))
            .onAppear {
                // Ensure filters are loaded and filter button state is updated when page appears
                viewModel.updateFilterButtonState()
            }
            .sheet(isPresented: $viewModel.showingFilterBuilder) {
                if let activeView = viewModel.activeView {
                    FilterBuilderSheetView(
                        viewModel: viewModel,
                        entityType: activeView.entityType
                    )
                }
            }
            .sheet(isPresented: $viewModel.showingAddColumnSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("New Column")
                    .font(.headline)

                TextField("Name", text: $newColumnName)
                    .textFieldStyle(.roundedBorder)

                Picker("Type", selection: $newColumnType) {
                    ForEach(GridColumnDataType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        viewModel.hideAddColumnSheet()
                        dismissNewColumnSheet()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Create") {
                        let trimmedName = newColumnName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty else { return }
                        viewModel.createCustomColumn(name: trimmedName, dataType: newColumnType)
                        viewModel.hideAddColumnSheet()
                        dismissNewColumnSheet()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newColumnName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 360)
        }
    }
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            viewPresetList
            columnControls
            Spacer()
        }
    }
    
    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Grid Views")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.toggleGridToolbar()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.bold())
                        .padding(6)
                        .background(
                            Circle()
                                .fill(Color.secondary.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
                .help("Collapse Grid Views toolbar")
            }
            
            Picker("Entity", selection: Binding(
                get: { viewModel.selectedEntity },
                set: { viewModel.switchEntity($0) }
            )) {
                Text("Contacts").tag(GridEntityType.contacts)
                Text("Groups").tag(GridEntityType.groups)
            }
            .pickerStyle(.segmented)
            
            Button {
                Task {
                    await viewModel.createNewView()
                }
            } label: {
                Label("New View", systemImage: "plus.square.on.square")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
            .help("Create a new \(viewModel.selectedEntity == .contacts ? "contacts" : "groups") grid view")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    private var viewPresetList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.availableViews.filter { $0.entityType == viewModel.selectedEntity }) { preset in
                    presetRow(for: preset)
                        .id(preset.id) // Ensure view updates when preset changes
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }
    
    @ViewBuilder
    private func presetRow(for preset: GridViewConfig) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if editingViewId == preset.id {
                    TextField("View name", text: $editingName)
                        .textFieldStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .focused($isNameFieldFocused)
                        .onSubmit {
                            saveViewName(preset)
                        }
                        .onAppear {
                            editingName = preset.name
                            // Select all text for easy editing
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                isNameFieldFocused = true
                            }
                        }
                        .onChange(of: editingViewId) { oldValue, newValue in
                            if newValue == preset.id {
                                // Just started editing this view
                                editingName = preset.name
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    isNameFieldFocused = true
                                }
                            }
                        }
                } else {
                    Text(preset.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Text(preset.entityType == .contacts ? "Contacts" : "Groups")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.activeView?.id == preset.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(viewModel.activeView?.id == preset.id ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture(count: 2)
                .onEnded {
                    // Double click - start editing
                    print("🖱️ GridViewPage: Double-tap detected on view '\(preset.name)'")
                    startEditingName(for: preset)
                }
        )
        .onTapGesture {
            // Single click - select view (only if not editing)
            if editingViewId != preset.id {
                // Cancel editing if clicking on a different view
                if editingViewId != nil {
                    editingViewId = nil
                }
                viewModel.selectView(preset)
            }
        }
        .onChange(of: editingViewId) { oldValue, newValue in
            if newValue == nil && oldValue == preset.id {
                // Editing was cancelled, restore original name
                editingName = preset.name
            }
        }
    }

    private var columnControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Columns")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    GridViewPage()
        .environmentObject(AppState())
}

private extension GridViewPage {
    var sidebarBackgroundColor: Color {
        Color(nsColor: NSColor.controlBackgroundColor)
    }
    
    var gridBackgroundColor: Color {
        switch colorScheme {
        case .dark:
            return Color(nsColor: NSColor.windowBackgroundColor)
        default:
            return Color(nsColor: NSColor.textBackgroundColor)
        }
    }
    
    var collapsedSidebarToggle: some View {
        VStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.toggleGridToolbar()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .padding(8)
                    .background(
                        Circle()
                            .fill(Color.secondary.opacity(0.2))
                    )
            }
            .buttonStyle(.plain)
            .help("Expand Grid Views toolbar")
            .padding(.top, 12)
            
            Spacer()
        }
    }
    
    func dismissNewColumnSheet() {
        newColumnName = ""
        newColumnType = .text
    }
    
    private func startEditingName(for preset: GridViewConfig) {
        print("✏️ GridViewPage: Starting to edit view name for '\(preset.name)'")
        editingViewId = preset.id
        editingName = preset.name
    }
    
    private func saveViewName(_ preset: GridViewConfig) {
        let trimmedName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != preset.name else {
            print("⚠️ GridViewPage: saveViewName - name unchanged or empty, cancelling edit")
            // Cancel editing if name is empty or unchanged
            editingViewId = nil
            return
        }
        
        print("💾 GridViewPage: Saving view name '\(preset.name)' -> '\(trimmedName)'")
        
        Task {
            do {
                try await viewModel.updateViewName(preset, newName: trimmedName)
                await MainActor.run {
                    print("✅ GridViewPage: View name saved successfully")
                    editingViewId = nil
                }
            } catch {
                print("❌ GridViewPage: Failed to save view name: \(error)")
                await MainActor.run {
                    viewModel.lastError = "Failed to save view name: \(error.localizedDescription)"
                    editingViewId = nil
                }
            }
        }
    }
    
    private var mainContent: some View {
        HStack(spacing: 0) {
            if appState.isGridToolbarVisible {
                sidebar
                    .frame(width: 260)
                    .background(sidebarBackgroundColor)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                collapsedSidebarToggle
                    .frame(width: 36)
                    .background(sidebarBackgroundColor)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            
            Divider()
            
            ZStack {
                GridWebView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(gridBackgroundColor)
                
                if viewModel.showingColumnMenu {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                viewModel.showingColumnMenu = false
                            }
                        }
                        .zIndex(999)
                    
                    ColumnVisibilityMenu(viewModel: viewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, 18)
                        .padding(.top, 48) // Position just below the header (typical header height ~40px + small gap)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing)),
                            removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing))
                        ))
                        .zIndex(1000)
                }
            }
            .onChange(of: viewModel.selectedEntity) { _, _ in
                // Close menu when switching entities
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.showingColumnMenu = false
                }
            }
            .onChange(of: viewModel.activeView?.id) { _, _ in
                // Close menu when switching views
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.showingColumnMenu = false
                }
            }
        }
    }
    
}

// MARK: - View Modifiers

private struct SearchOverlayModifier: ViewModifier {
    @ObservedObject var viewModel: GridViewViewModel
    @FocusState.Binding var isSearchFieldFocused: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if viewModel.isSearchActive {
                    SearchBarView(viewModel: viewModel, isSearchFieldFocused: $isSearchFieldFocused)
                        .padding()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: viewModel.searchText) { oldValue, newValue in
                viewModel.performSearch(newValue)
                // Ensure search field maintains focus after search
                if viewModel.isSearchActive {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isSearchFieldFocused = true
                    }
                }
            }
            .onChange(of: viewModel.isSearchActive) { oldValue, newValue in
                if newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isSearchFieldFocused = true
                    }
                }
            }
            .onChange(of: viewModel.currentSearchIndex) { oldValue, newValue in
                // When navigating between search results, ensure search field keeps focus
                if viewModel.isSearchActive && newValue >= 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isSearchFieldFocused = true
                    }
                }
            }
    }
}

private struct ErrorOverlayModifier: ViewModifier {
    @ObservedObject var viewModel: GridViewViewModel
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if let error = viewModel.lastError {
                    VStack {
                        HStack(spacing: 8) {
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(.white)
                                .lineLimit(3)
                            
                            Button(action: {
                                viewModel.lastError = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.8))
                                    .font(.footnote)
                            }
                            .buttonStyle(.plain)
                            .help("Dismiss error")
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding()
                        Spacer()
                    }
                    .transition(.move(edge: .top))
                    .animation(.easeInOut, value: viewModel.lastError)
                }
            }
    }
}

private struct KeyboardShortcutsModifier: ViewModifier {
    @ObservedObject var viewModel: GridViewViewModel
    @Binding var editingViewId: UUID?
    
    func body(content: Content) -> some View {
        content
            .onKeyPress(.escape) {
                if viewModel.showingColumnMenu {
                    viewModel.showingColumnMenu = false
                    return .handled
                }
                if editingViewId != nil {
                    editingViewId = nil
                    return .handled
                }
                if viewModel.isSearchActive {
                    viewModel.clearSearch()
                    return .handled
                }
                return .ignored
            }
            .background(
                Group {
                    Button("") {
                        viewModel.isSearchActive = true
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .hidden()
                    
                    Button("") {
                        if viewModel.isSearchActive && !viewModel.searchResults.isEmpty {
                            viewModel.navigateToNextResult()
                        }
                    }
                    .keyboardShortcut("g", modifiers: .command)
                    .hidden()
                    
                    Button("") {
                        if viewModel.isSearchActive && !viewModel.searchResults.isEmpty {
                            viewModel.navigateToPreviousResult()
                        }
                    }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .hidden()
                    
                    Button("") {
                        viewModel.handleCopy()
                    }
                    .keyboardShortcut("c", modifiers: .command)
                    .hidden()
                    
                    Button("") {
                        viewModel.handlePaste()
                    }
                    .keyboardShortcut("v", modifiers: .command)
                    .hidden()
                }
            )
    }
}

private struct ColumnVisibilityMenu: View {
    @ObservedObject var viewModel: GridViewViewModel
    @State private var draggedColumn: String?
    @State private var localColumnOrder: [String] = []
    @State private var dragOverColumn: String?
    
    var body: some View {
        let columns = viewModel.getAllColumns()
        
        VStack(alignment: .leading, spacing: 0) {
            Text("Column Visibility")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(columns, id: \.id) { column in
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .frame(width: 16)
                            
                            Toggle("", isOn: Binding(
                                get: { column.isVisible },
                                set: { _ in
                                    viewModel.toggleColumnVisibility(column.id)
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            
                            Text(column.name)
                                .font(.subheadline)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .background(
                            Group {
                                if draggedColumn == column.id {
                                    Color.accentColor.opacity(0.2)
                                } else if dragOverColumn == column.id {
                                    Color.accentColor.opacity(0.05)
                                } else {
                                    Color.clear
                                }
                            }
                        )
                        .opacity(draggedColumn == column.id ? 0.5 : 1.0)
                        .scaleEffect(draggedColumn == column.id ? 0.98 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: draggedColumn)
                        .animation(.easeInOut(duration: 0.15), value: dragOverColumn)
                        .onTapGesture {
                            viewModel.toggleColumnVisibility(column.id)
                        }
                        .onDrag {
                            draggedColumn = column.id
                            return NSItemProvider(object: column.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: ColumnDropDelegate(
                            columnId: column.id,
                            columns: columns,
                            viewModel: viewModel,
                            draggedColumn: $draggedColumn,
                            dragOverColumn: $dragOverColumn
                        ))
                    }
                }
                .padding(.vertical, 8)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: columns.map { $0.id })
            }
            .frame(maxHeight: 400)
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .onAppear {
            // Initialize local order when menu appears
            localColumnOrder = columns.map { $0.id }
        }
    }
}

private struct ColumnDropDelegate: DropDelegate {
    let columnId: String
    let columns: [(id: String, name: String, isVisible: Bool)]
    let viewModel: GridViewViewModel
    @Binding var draggedColumn: String?
    @Binding var dragOverColumn: String?
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedColumn = draggedColumn else {
            dragOverColumn = nil
            return false
        }
        
        guard let draggedIndex = columns.firstIndex(where: { $0.id == draggedColumn }),
              let targetIndex = columns.firstIndex(where: { $0.id == columnId }),
              draggedIndex != targetIndex else {
            self.draggedColumn = nil
            dragOverColumn = nil
            return false
        }
        
        // Reorder columns with animation
        var newOrder = columns.map { $0.id }
        newOrder.remove(at: draggedIndex)
        newOrder.insert(draggedColumn, at: targetIndex)
        
        // Update column order in view model with animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            viewModel.updateColumnOrder(newOrder)
        }
        
        self.draggedColumn = nil
        dragOverColumn = nil
        return true
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.text])
    }
    
    func dropEntered(info: DropInfo) {
        dragOverColumn = columnId
    }
    
    func dropExited(info: DropInfo) {
        if dragOverColumn == columnId {
            dragOverColumn = nil
        }
    }
}

private struct FilterBuilderSheetView: View {
    @ObservedObject var viewModel: GridViewViewModel
    let entityType: GridEntityType
    @State private var localFilterModel: FilterModel
    @Environment(\.dismiss) private var dismiss
    
    init(viewModel: GridViewViewModel, entityType: GridEntityType) {
        self.viewModel = viewModel
        self.entityType = entityType
        if let activeView = viewModel.activeView {
            self._localFilterModel = State(initialValue: activeView.advancedFilterModel)
        } else {
            self._localFilterModel = State(initialValue: FilterModel(entityType: entityType))
        }
    }
    
    var body: some View {
        FilterBuilderView(
            filterModel: $localFilterModel,
            entityType: entityType,
            onApply: {
                viewModel.updateFilterModel(localFilterModel)
            }
        )
    }
}

private struct SearchBarView: View {
    @ObservedObject var viewModel: GridViewViewModel
    @FocusState.Binding var isSearchFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search...", text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.searchText = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isSearchFieldFocused)
                .onSubmit {
                    viewModel.navigateToNextResult()
                }
                
                if !viewModel.searchText.isEmpty {
                    HStack(spacing: 8) {
                        if !viewModel.searchResults.isEmpty {
                            Text("\(viewModel.currentSearchIndex + 1) of \(viewModel.searchResults.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                viewModel.navigateToPreviousResult()
                            }) {
                                Image(systemName: "chevron.up")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Previous (Shift+Command+G)")
                            
                            Button(action: {
                                viewModel.navigateToNextResult()
                            }) {
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Next (Command+G)")
                        } else {
                            Text("No results")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Button(action: {
                            viewModel.clearSearch()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Close search (Escape)")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            )
        }
        .frame(maxWidth: 500)
    }
}

