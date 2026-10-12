import Foundation
import Combine
import AppKit

@MainActor
final class GridViewViewModel: ObservableObject {
    @Published var selectedEntity: GridEntityType = .contacts
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    @Published var activeView: GridViewConfig?
    @Published var availableViews: [GridViewConfig] = []
    @Published var searchText: String = ""
    @Published var searchResults: [GridSearchResult] = []
    @Published var currentSearchIndex: Int = -1
    @Published var isSearchActive: Bool = false
    @Published var showingColumnMenu: Bool = false
    @Published var showingFilterBuilder: Bool = false
    
    private(set) var sessionId = UUID()
    
    private let gridService: GridViewService
    private var cancellables: Set<AnyCancellable> = []
    private var activeCustomColumns: [GridCustomColumn] = []
    private let notificationCenter = NotificationCenter.default
    private var databaseObserver: NSObjectProtocol?
    private var lastPresentedErrorMessage: String?
    private var lastPresentedErrorDate: Date?
    
    private struct PendingEditError {
        let error: GridViewService.GridViewServiceError
        let edit: GridEditPayload
    }
    
    private var pendingEditErrors: [PendingEditError] = []
    private var errorAggregationTask: Task<Void, Never>?
    private var currentGridData: [[String: Any]] = []
    private var currentPageOffset: Int = 0
    private var currentPageLimit: Int = 200
    
    weak var coordinator: GridWebView.Coordinator? {
        didSet {
            coordinator?.viewModel = self
        }
    }
    
    init(gridService: GridViewService? = nil) {
        self.gridService = gridService ?? GridViewService()
        observeDatabaseConnection()
    }
    
    deinit {
        if let databaseObserver {
            notificationCenter.removeObserver(databaseObserver)
        }
    }
    
    // MARK: - Web Events
    
    func webViewReady(for entityType: GridEntityType) {
        selectedEntity = entityType
        Task {
            await loadInitialData()
        }
    }
    
    func requestPage(entityType: GridEntityType, offset: Int, limit: Int, sorts: [GridSortDescriptor]? = nil, filters: [String: AnyCodable]? = nil) {
        Task {
            // ALWAYS use the active view's filters - ignore any filters passed from web view
            // This ensures filters are view-specific and don't leak between views
            if let activeView = activeView, activeView.entityType == entityType {
                let filterModel = activeView.advancedFilterModel
                // Use the view's filter model (even if empty) to ensure consistency
                await sendPage(entityType: entityType, offset: offset, limit: limit, sorts: sorts ?? activeView.sortModel, filterModel: filterModel.isEmpty ? nil : filterModel)
                return
            }
            // Fall back to old filter format only if no active view
            await sendPage(entityType: entityType, offset: offset, limit: limit, sorts: sorts, filters: filters)
        }
    }
    
    func handleEdit(_ edit: GridEditPayload) {
        Task {
            await processEdit(edit)
        }
    }
    
    func handleUndo() {
        Task {
            do {
                if let entry = try await gridService.undoLatest(sessionId: sessionId) {
                    let rowPayload: [String: Any]?
                    switch entry.entityType {
                    case .contacts:
                        if let contact = try? await gridService.fetchContact(recordIdentifier: entry.recordId) {
                            var row = contact.toGridDictionary()
                            row[GridViewService.ContactColumns.groups] = try? await gridService.groupsWithColors(for: contact)
                            row[GridViewService.ContactColumns.tags] = gridService.tagNames(for: contact)
                            row[GridViewService.ContactColumns.relationships] = gridService.relationshipNames(for: contact)
                            rowPayload = row
                        } else {
                            rowPayload = nil
                        }
                    case .groups:
                        if let group = try? await gridService.fetchGroup(recordIdentifier: entry.recordId) {
                            var row = group.toGridDictionary()
                            row[GridViewService.GroupColumns.tags] = gridService.tagNames(for: group)
                            row[GridViewService.GroupColumns.children] = try? await gridService.childGroupNames(for: group)
                            row[GridViewService.GroupColumns.parents] = try? await gridService.parentGroupNames(for: group)
                            rowPayload = row
                        } else {
                            rowPayload = nil
                        }
                    }
                    let payload: [String: Any] = [
                        "sessionId": sessionId.uuidString,
                        "entityType": entry.entityType.rawValue,
                        "columnId": entry.columnId,
                        "recordId": entry.recordId,
                        "previousValue": entry.previousValue as Any,
                        "nextValue": entry.nextValue as Any,
                        "row": rowPayload as Any
                    ]
                    coordinator?.send(event: "undoApplied", payload: payload)
                } else {
                    coordinator?.send(event: "undoUnavailable", payload: [:])
                }
            } catch {
                await report(error: error)
            }
        }
    }
    
    func handleRedo() {
        Task {
            do {
                if let entry = try await gridService.redoLatest(sessionId: sessionId) {
                    let rowPayload: [String: Any]?
                    switch entry.entityType {
                    case .contacts:
                        if let contact = try? await gridService.fetchContact(recordIdentifier: entry.recordId) {
                            var row = contact.toGridDictionary()
                            row[GridViewService.ContactColumns.groups] = try? await gridService.groupsWithColors(for: contact)
                            row[GridViewService.ContactColumns.tags] = gridService.tagNames(for: contact)
                            row[GridViewService.ContactColumns.relationships] = gridService.relationshipNames(for: contact)
                            rowPayload = row
                        } else {
                            rowPayload = nil
                        }
                    case .groups:
                        if let group = try? await gridService.fetchGroup(recordIdentifier: entry.recordId) {
                            var row = group.toGridDictionary()
                            row[GridViewService.GroupColumns.tags] = gridService.tagNames(for: group)
                            row[GridViewService.GroupColumns.children] = try? await gridService.childGroupNames(for: group)
                            row[GridViewService.GroupColumns.parents] = try? await gridService.parentGroupNames(for: group)
                            rowPayload = row
                        } else {
                            rowPayload = nil
                        }
                    }
                    let payload: [String: Any] = [
                        "sessionId": sessionId.uuidString,
                        "entityType": entry.entityType.rawValue,
                        "columnId": entry.columnId,
                        "recordId": entry.recordId,
                        "previousValue": entry.previousValue as Any,
                        "nextValue": entry.nextValue as Any,
                        "row": rowPayload as Any
                    ]
                    coordinator?.send(event: "redoApplied", payload: payload)
                } else {
                    coordinator?.send(event: "redoUnavailable", payload: [:])
                }
            } catch {
                await report(error: error)
            }
        }
    }
    
    func handleDeleteRows(recordIds: [String]) {
        Task {
            do {
                switch selectedEntity {
                case .contacts:
                    try await gridService.deleteContacts(recordIds: recordIds)
                case .groups:
                    try await gridService.deleteGroups(recordIds: recordIds)
                }
                
                // Notify web view that rows were deleted
                coordinator?.send(event: "rowsDeleted", payload: [
                    "entityType": selectedEntity.rawValue,
                    "recordIds": recordIds
                ])
                
                // Reload the current page to reflect deletions
                await sendPage(
                    entityType: selectedEntity,
                    offset: currentPageOffset,
                    limit: currentPageLimit,
                    sorts: activeView?.sortModel,
                    filterModel: activeView?.advancedFilterModel.isEmpty == false ? activeView?.advancedFilterModel : nil
                )
            } catch {
                await report(error: error)
            }
        }
    }
    
    func handleCopy() {
        // Request selected cells from the web view
        coordinator?.send(event: "requestCopy", payload: [:])
    }
    
    func handlePaste() {
        // Get clipboard content and send to web view
        let pasteboard = NSPasteboard.general
        guard let clipboardString = pasteboard.string(forType: .string) else {
            return
        }
        
        // Send paste data to web view
        coordinator?.send(event: "requestPaste", payload: [
            "clipboardData": clipboardString
        ])
    }
    
    func createCustomColumn(name: String, dataType: GridColumnDataType) {
        guard let activeView else { return }
        let column = GridCustomColumn(
            viewId: activeView.id,
            entityType: activeView.entityType,
            userId: activeView.userId,
            name: name,
            dataType: dataType
        )
        Task {
            do {
                try await persistCustomColumn(column)
            } catch {
                await report(error: error)
            }
        }
    }
    
    func createCustomColumn(request: CreateCustomColumnRequest) {
        Task {
            await processCreateCustomColumn(request: request)
        }
    }
    
    func switchEntity(_ entity: GridEntityType) {
        guard selectedEntity != entity else { return }
        showingColumnMenu = false // Close menu when switching entities
        selectedEntity = entity
        sessionId = UUID()
        coordinator?.send(event: "entityChanged", payload: [
            "entityType": entity.rawValue,
            "sessionId": sessionId.uuidString
        ])
        Task {
            await loadInitialData()
        }
    }
    
    func selectView(_ view: GridViewConfig) {
        showingColumnMenu = false // Close menu when switching views
        
        // Update active view immediately
        activeView = view
        
        // If entity type changed, update entity without triggering full reload
        // (We don't call switchEntity here because it would trigger loadInitialData
        //  which could conflict with our view selection)
        if view.entityType != selectedEntity {
            selectedEntity = view.entityType
            sessionId = UUID()
            coordinator?.send(event: "entityChanged", payload: [
                "entityType": view.entityType.rawValue,
                "sessionId": sessionId.uuidString
            ])
        }
        
        // Notify web view of view change immediately
        coordinator?.send(event: "activeViewChanged", payload: ["view": view.toDictionary()])
        
        // Update filter button state for the new view
        updateFilterButtonState()
        
        Task {
            // Reload custom columns for the new view
            await reloadCustomColumns(for: view)
            
            // CRITICAL: Force refresh by sending a page request with the new view's filters
            // This ensures the new view's filters are applied immediately, not cached data
            let filterModel = view.advancedFilterModel
            await sendPage(
                entityType: view.entityType, // Use view's entity type, not selectedEntity
                offset: 0,
                limit: 200,
                sorts: view.sortModel,
                filterModel: filterModel.isEmpty ? nil : filterModel
            )
        }
    }
    
    func createNewView() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            var template = activeView ?? availableViews.first
            if template == nil {
                template = defaultViewConfiguration(for: selectedEntity)
            }
            
            let baseName: String
            if let activeView, template?.id == activeView.id {
                baseName = "\(activeView.name) Copy"
            } else if let template {
                baseName = "\(template.name) Copy"
            } else {
                baseName = defaultViewBaseName(for: selectedEntity)
            }
            
            var newView = template ?? defaultViewConfiguration(for: selectedEntity)
            newView.id = UUID()
            newView.databaseId = nil
            newView.name = uniqueViewName(basedOn: baseName)
            newView.entityType = selectedEntity
            newView.createdAt = Date()
            newView.updatedAt = Date()
            
            // IMPORTANT: Clear filters when creating a new view - each view should have its own filters
            newView.filterModelData = nil
            newView.filterModel = [:]
            
            if newView.columnOrder.isEmpty {
                newView.columnOrder = defaultColumnOrder(for: selectedEntity)
            }
            if newView.visibleColumns.isEmpty {
                newView.visibleColumns = newView.columnOrder
            }
            if newView.frozenColumns.isEmpty {
                newView.frozenColumns = defaultFrozenColumns(for: selectedEntity)
            }
            if newView.sortModel.isEmpty {
                newView.sortModel = [defaultSortDescriptor(for: selectedEntity)]
            }
            
            try await gridService.save(view: newView)
            if let persisted = try await gridService.fetchView(uuid: newView.id) {
                newView = persisted
            }
            
            let refreshed = try await gridService.fetchViews(for: selectedEntity)
            availableViews = refreshed
            activeView = refreshed.first(where: { $0.id == newView.id }) ?? newView
            
            coordinator?.send(event: "viewsLoaded", payload: ["views": availableViews.map { $0.toDictionary() }])
            if let activeView {
                coordinator?.send(event: "activeViewChanged", payload: ["view": activeView.toDictionary()])
                await reloadCustomColumns(for: activeView)
                
                // Update filter button state
                updateFilterButtonState()
                
                // Apply the view's filters immediately - each view has its own filters
                let filterModel = activeView.advancedFilterModel
                await sendPage(
                    entityType: activeView.entityType, // Use view's entity type for consistency
                    offset: 0,
                    limit: 200,
                    sorts: activeView.sortModel,
                    filterModel: filterModel.isEmpty ? nil : filterModel
                )
            } else {
                updateFilterButtonState() // Update button state even if no view
            }
        } catch {
            await report(error: error)
        }
    }

    func updateColumnState(for entity: GridEntityType, columnOrder: [String], visibleColumns: [String], frozenColumns: [String]) {
        guard var view = activeView, view.entityType == entity else { return }
        let allowed = allowedColumnIds(for: entity)
        view.columnOrder = sanitizeColumnList(columnOrder, allowed: allowed)
        view.visibleColumns = sanitizeColumnList(visibleColumns, allowed: allowed)
        view.frozenColumns = sanitizeColumnList(frozenColumns, allowed: allowed)
        view.updatedAt = Date()
        activeView = view
        if let index = availableViews.firstIndex(where: { $0.id == view.id }) {
            availableViews[index] = view
        }
        coordinator?.send(event: "activeViewChanged", payload: ["view": view.toDictionary()])
        Task {
            do {
                try await gridService.save(view: view)
            } catch {
                await report(error: error)
            }
        }
    }
    
    func updateViewName(_ view: GridViewConfig, newName: String) async throws {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != view.name else {
            print("⚠️ GridViewViewModel: updateViewName - name unchanged or empty")
            return // No change needed
        }
        
        print("📝 GridViewViewModel: Updating view name from '\(view.name)' to '\(trimmedName)'")
        
        var updatedView = view
        updatedView.name = trimmedName
        updatedView.updatedAt = Date()
        
        // Save to database
        try await gridService.save(view: updatedView)
        print("✅ GridViewViewModel: View name saved to database")
        
        // Refresh from database to ensure we have the latest data
        if let refreshed = try? await gridService.fetchView(uuid: updatedView.id) {
            updatedView = refreshed
            print("✅ GridViewViewModel: Refreshed view from database: '\(refreshed.name)'")
        }
        
        // Update local state
        if let index = availableViews.firstIndex(where: { $0.id == view.id }) {
            availableViews[index] = updatedView
            print("✅ GridViewViewModel: Updated availableViews array")
        }
        if activeView?.id == view.id {
            activeView = updatedView
            print("✅ GridViewViewModel: Updated activeView")
        }
        
        // Notify web view
        coordinator?.send(event: "activeViewChanged", payload: ["view": updatedView.toDictionary()])
        print("✅ GridViewViewModel: Notified web view of name change")
    }
    
    func showColumnMenu() {
        showingColumnMenu = true
    }
    
    @Published var showingAddColumnSheet: Bool = false
    
    func showAddColumnSheet() {
        showingAddColumnSheet = true
    }
    
    func hideAddColumnSheet() {
        showingAddColumnSheet = false
    }
    
    func showFilterBuilder() {
        showingFilterBuilder = true
    }
    
    func hideFilterBuilder() {
        showingFilterBuilder = false
    }
    
    func updateFilterModel(_ filterModel: FilterModel) {
        guard var view = activeView else { return }
        
        // Update the view's filter model immediately
        view.setAdvancedFilterModel(filterModel)
        view.updatedAt = Date()
        activeView = view
        
        // Update availableViews array to keep it in sync
        if let index = availableViews.firstIndex(where: { $0.id == view.id }) {
            availableViews[index] = view
        }
        
        // Notify web view of the change immediately
        coordinator?.send(event: "activeViewChanged", payload: ["view": view.toDictionary()])
        
        // Update filter button state
        updateFilterButtonState()
        
        // Reload data with new filters IMMEDIATELY (don't wait for save)
        Task {
            // Reload data first for instant feedback
            await sendPage(entityType: selectedEntity, offset: 0, limit: 200, sorts: view.sortModel, filterModel: filterModel)
            
            // Save to database in background (non-blocking)
            do {
                try await gridService.save(view: view)
            } catch {
                await report(error: error)
            }
        }
    }
    
    /// Update the filter button state in the web view based on whether filters are active
    func updateFilterButtonState() {
        let hasActiveFilters: Bool
        if let activeView = activeView {
            hasActiveFilters = !activeView.advancedFilterModel.isEmpty
        } else {
            hasActiveFilters = false
        }
        
        coordinator?.send(event: "filterButtonState", payload: [
            "hasActiveFilters": hasActiveFilters
        ])
    }
    
    func getAllColumns() -> [(id: String, name: String, isVisible: Bool)] {
        guard let view = activeView else { return [] }
        let allColumnIds = Array(allowedColumnIds(for: view.entityType))
        let visibleSet = Set(view.visibleColumns)
        
        // Use columnOrder from view to maintain the same order as the grid
        let orderedColumns: [String]
        if !view.columnOrder.isEmpty {
            // Start with columns in columnOrder (preserving order)
            var ordered = view.columnOrder.filter { allColumnIds.contains($0) }
            // Add any remaining columns that aren't in columnOrder (new columns, etc.)
            let remaining = allColumnIds.filter { !ordered.contains($0) }
            ordered.append(contentsOf: remaining)
            orderedColumns = ordered
        } else {
            // Fallback to default order if columnOrder is empty
            orderedColumns = allColumnIds
        }
        
        return orderedColumns.map { columnId in
            let displayName = columnDisplayName(columnId, for: view.entityType)
            return (id: columnId, name: displayName, isVisible: visibleSet.contains(columnId))
        }
    }
    
    func updateColumnOrder(_ newOrder: [String]) {
        guard var view = activeView else { return }
        let allowed = allowedColumnIds(for: view.entityType)
        view.columnOrder = sanitizeColumnList(newOrder, allowed: allowed)
        view.updatedAt = Date()
        activeView = view
        
        if let index = availableViews.firstIndex(where: { $0.id == view.id }) {
            availableViews[index] = view
        }
        
        // Update the web view
        coordinator?.send(event: "activeViewChanged", payload: ["view": view.toDictionary()])
        
        // Save to database
        Task {
            do {
                try await gridService.save(view: view)
            } catch {
                await report(error: error)
            }
        }
    }
    
    func toggleColumnVisibility(_ columnId: String) {
        guard var view = activeView else { return }
        var visibleColumns = view.visibleColumns
        
        if visibleColumns.contains(columnId) {
            visibleColumns.removeAll { $0 == columnId }
        } else {
            visibleColumns.append(columnId)
        }
        
        view.visibleColumns = visibleColumns
        view.updatedAt = Date()
        activeView = view
        
        if let index = availableViews.firstIndex(where: { $0.id == view.id }) {
            availableViews[index] = view
        }
        
        // Update the web view
        coordinator?.send(event: "activeViewChanged", payload: ["view": view.toDictionary()])
        
        // Save to database
        Task {
            do {
                try await gridService.save(view: view)
            } catch {
                await report(error: error)
            }
        }
    }
    
    private func columnDisplayName(_ columnId: String, for entity: GridEntityType) -> String {
        // Check if it's a custom column
        if let customColumn = activeCustomColumns.first(where: { $0.id.uuidString == columnId }) {
            return customColumn.name
        }
        
        // Standard columns
        switch entity {
        case .contacts:
            switch columnId {
            case GridViewService.ContactColumns.name: return "Name"
            case GridViewService.ContactColumns.firstName: return "First Name"
            case GridViewService.ContactColumns.lastName: return "Last Name"
            case GridViewService.ContactColumns.nickname: return "Nickname"
            case GridViewService.ContactColumns.phone: return "Phone"
            case GridViewService.ContactColumns.email: return "Email"
            case GridViewService.ContactColumns.address: return "Address"
            case GridViewService.ContactColumns.notes: return "Notes"
            case GridViewService.ContactColumns.creationDate: return "Creation Date"
            case GridViewService.ContactColumns.birthday: return "Birthday"
            case GridViewService.ContactColumns.groups: return "Groups"
            case GridViewService.ContactColumns.tags: return "Tags"
            case GridViewService.ContactColumns.relationships: return "Relationships"
            case GridViewService.ContactColumns.totalMessages: return "Total Messages"
            case GridViewService.ContactColumns.messagesSent: return "Messages Sent"
            case GridViewService.ContactColumns.messagesReceived: return "Messages Received"
            case GridViewService.ContactColumns.lastMessageReceived: return "Last Message Received"
            case GridViewService.ContactColumns.lastMessageSent: return "Last Message Sent"
            case GridViewService.ContactColumns.profilePhoto: return "Profile Photo"
            default: return columnId.replacingOccurrences(of: "contact.", with: "").capitalized
            }
        case .groups:
            switch columnId {
            case GridViewService.GroupColumns.name: return "Name"
            case GridViewService.GroupColumns.participants: return "Participants"
            case GridViewService.GroupColumns.color: return "Color"
            case GridViewService.GroupColumns.createdAt: return "Created At"
            case GridViewService.GroupColumns.size: return "Size"
            case GridViewService.GroupColumns.tags: return "Tags"
            case GridViewService.GroupColumns.children: return "Children"
            case GridViewService.GroupColumns.parents: return "Parents"
            default: return columnId.replacingOccurrences(of: "group.", with: "").capitalized
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadInitialData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Ensure GRDBDatabaseManager is connected to the user's configured database path
            // This handles cases where the user changed the database path or GRDB isn't connected yet
            try await gridService.ensureGRDBConnected()
            
            let views = try await gridService.fetchViews(for: selectedEntity)
            availableViews = views
            let viewPayload = views.map { $0.toDictionary() }
            coordinator?.send(event: "viewsLoaded", payload: ["views": viewPayload])
            
            if let firstView = views.first(where: { $0.entityType == selectedEntity }) ?? views.first {
                activeView = firstView
                coordinator?.send(event: "activeViewChanged", payload: ["view": firstView.toDictionary()])
                
                // Update filter button state
                updateFilterButtonState()
                
                // Apply the view's filters immediately when loading initial data
                // Each view has its own filters - apply them instantly
                await reloadCustomColumns(for: firstView)
                let filterModel = firstView.advancedFilterModel
                await sendPage(
                    entityType: firstView.entityType, // Use view's entity type for consistency
                    offset: 0,
                    limit: 200,
                    sorts: firstView.sortModel,
                    filterModel: filterModel.isEmpty ? nil : filterModel
                )
            } else {
                // No view found - send empty page
                updateFilterButtonState() // Update button state even if no view
                await sendPage(entityType: selectedEntity, offset: 0, limit: 200)
            }
        } catch {
            await report(error: error)
        }
    }
    
    private func observeDatabaseConnection() {
        databaseObserver = notificationCenter.addObserver(
            forName: .grdbDatabaseDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                if self.isLoading { return }
                if !self.availableViews.isEmpty && self.lastError == nil {
                    return
                }
                await self.loadInitialData()
            }
        }
    }
    
    private func sendPage(entityType: GridEntityType, offset: Int, limit: Int, sorts: [GridSortDescriptor]? = nil, filters: [String: AnyCodable]? = nil, filterModel: FilterModel? = nil) async {
        do {
            let effectiveSorts = sorts ?? activeView?.sortModel ?? []
            
            // Determine which filter model to use
            // Priority: 1) Explicitly passed filterModel, 2) Active view's filterModel, 3) Old format filters
            let effectiveFilterModel: FilterModel?
            if let filterModel = filterModel {
                // Use explicitly passed filterModel (e.g., from updateFilterModel)
                effectiveFilterModel = filterModel
            } else if let activeView = activeView, activeView.entityType == entityType {
                // Use active view's filterModel to ensure view-specific filtering
                let viewFilterModel = activeView.advancedFilterModel
                effectiveFilterModel = viewFilterModel.isEmpty ? nil : viewFilterModel
            } else {
                effectiveFilterModel = nil
            }
            
            // Use new FilterModel if available
            if let filterModel = effectiveFilterModel {
                switch entityType {
                case .contacts:
                    let contacts = try await gridService.fetchContacts(offset: offset, limit: limit, sorts: effectiveSorts, filterModel: filterModel)
                    var rows: [[String: Any]] = []
                    var recordIds: [String] = []
                    for contact in contacts {
                        var row = contact.toGridDictionary()
                        row[GridViewService.ContactColumns.groups] = try await gridService.groupsWithColors(for: contact)
                        row[GridViewService.ContactColumns.tags] = gridService.tagNames(for: contact)
                        row[GridViewService.ContactColumns.relationships] = gridService.relationshipNames(for: contact)
                        rows.append(row)
                        recordIds.append(contact.phone)
                    }
                    if !activeCustomColumns.isEmpty {
                        let columnUUIDs = activeCustomColumns.map { $0.id }
                        let valuesMap = try await gridService.fetchCustomCellValues(columnUUIDs: columnUUIDs, recordIds: recordIds)
                        for (index, recordId) in recordIds.enumerated() {
                            let recordValues = valuesMap[recordId] ?? [:]
                            for column in activeCustomColumns {
                                if let value = recordValues[column.id] ?? nil {
                                    rows[index][column.id.uuidString] = value
                                } else {
                                    rows[index][column.id.uuidString] = NSNull()
                                }
                            }
                        }
                    }
                    let total = try await gridService.countContacts(filterModel: filterModel)
                    currentGridData = rows
                    currentPageOffset = offset
                    currentPageLimit = limit
                    
                    coordinator?.send(event: "pageData", payload: [
                        "entityType": entityType.rawValue,
                        "offset": offset,
                        "rows": rows,
                        "total": total
                    ])
                case .groups:
                    let groups = try await gridService.fetchGroups(offset: offset, limit: limit, sorts: effectiveSorts, filterModel: filterModel)
                    var rows: [[String: Any]] = []
                    var recordIds: [String] = []
                    for group in groups {
                        var row = group.toGridDictionary()
                        row[GridViewService.GroupColumns.tags] = gridService.tagNames(for: group)
                        row[GridViewService.GroupColumns.children] = try await gridService.childGroupNames(for: group)
                        row[GridViewService.GroupColumns.parents] = try await gridService.parentGroupNames(for: group)
                        rows.append(row)
                        recordIds.append(group.id.uuidString)
                    }
                    if !activeCustomColumns.isEmpty {
                        let columnUUIDs = activeCustomColumns.map { $0.id }
                        let valuesMap = try await gridService.fetchCustomCellValues(columnUUIDs: columnUUIDs, recordIds: recordIds)
                        for (index, recordId) in recordIds.enumerated() {
                            let recordValues = valuesMap[recordId] ?? [:]
                            for column in activeCustomColumns {
                                if let value = recordValues[column.id] ?? nil {
                                    rows[index][column.id.uuidString] = value
                                } else {
                                    rows[index][column.id.uuidString] = NSNull()
                                }
                            }
                        }
                    }
                    let total = try await gridService.countGroups(filterModel: filterModel)
                    currentGridData = rows
                    currentPageOffset = offset
                    currentPageLimit = limit
                    
                    coordinator?.send(event: "pageData", payload: [
                        "entityType": entityType.rawValue,
                        "offset": offset,
                        "rows": rows,
                        "total": total
                    ])
                }
                return
            }
            
            // Fall back to old filter format only if no FilterModel is available
            // This ensures we always prefer FilterModel when available
            let effectiveFilters = filters ?? activeView?.filterModel ?? [:]
            switch entityType {
            case .contacts:
                let contacts = try await gridService.fetchContacts(offset: offset, limit: limit, sorts: effectiveSorts, filters: effectiveFilters)
                print("📊 GridViewViewModel: Fetched \(contacts.count) contacts for offset \(offset)")
                var rows: [[String: Any]] = []
                var recordIds: [String] = []
                for contact in contacts {
                    var row = contact.toGridDictionary()
                    row[GridViewService.ContactColumns.groups] = try await gridService.groupsWithColors(for: contact)
                    row[GridViewService.ContactColumns.tags] = gridService.tagNames(for: contact)
                    row[GridViewService.ContactColumns.relationships] = gridService.relationshipNames(for: contact)
                    // Debug: Log first contact's data structure
                    if rows.isEmpty {
                        print("📊 GridViewViewModel: Sample row keys: \(row.keys.sorted())")
                        print("📊 GridViewViewModel: Sample row name value: \(row[GridViewService.ContactColumns.name] ?? "nil")")
                    }
                    rows.append(row)
                    recordIds.append(contact.phone)
                }
                if !activeCustomColumns.isEmpty {
                    let columnUUIDs = activeCustomColumns.map { $0.id }
                    let valuesMap = try await gridService.fetchCustomCellValues(columnUUIDs: columnUUIDs, recordIds: recordIds)
                    for (index, recordId) in recordIds.enumerated() {
                        let recordValues = valuesMap[recordId] ?? [:]
                        for column in activeCustomColumns {
                            if let value = recordValues[column.id] ?? nil {
                                rows[index][column.id.uuidString] = value
                            } else {
                                rows[index][column.id.uuidString] = NSNull()
                            }
                        }
                    }
                }
                let total = try await gridService.countContacts(filters: effectiveFilters)
                print("📊 GridViewViewModel: Sending pageData with \(rows.count) rows, total: \(total)")
                if rows.count > 0 {
                    let firstRow = rows[0]
                    print("📊 GridViewViewModel: First row has \(firstRow.keys.count) keys")
                    print("📊 GridViewViewModel: First row keys: \(firstRow.keys.sorted().prefix(10))")
                    if let nameValue = firstRow["contact.name"] {
                        print("📊 GridViewViewModel: First row 'contact.name' = '\(nameValue)'")
                    } else {
                        print("⚠️ GridViewViewModel: First row missing 'contact.name' key")
                    }
                    if let recordId = firstRow["recordId"] {
                        print("📊 GridViewViewModel: First row 'recordId' = '\(recordId)'")
                    }
                }
                // Store current grid data for search
                currentGridData = rows
                currentPageOffset = offset
                currentPageLimit = limit
                
                coordinator?.send(event: "pageData", payload: [
                    "entityType": entityType.rawValue,
                    "offset": offset,
                    "rows": rows,
                    "total": total
                ])
            case .groups:
                let groups = try await gridService.fetchGroups(offset: offset, limit: limit, sorts: effectiveSorts, filters: effectiveFilters)
                var rows: [[String: Any]] = []
                var recordIds: [String] = []
                for group in groups {
                    var row = group.toGridDictionary()
                    row[GridViewService.GroupColumns.tags] = gridService.tagNames(for: group)
                    row[GridViewService.GroupColumns.children] = try await gridService.childGroupNames(for: group)
                    row[GridViewService.GroupColumns.parents] = try await gridService.parentGroupNames(for: group)
                    // Get participant names instead of phone numbers
                    row[GridViewService.GroupColumns.participants] = try await gridService.participantNames(for: group)
                    rows.append(row)
                    recordIds.append(group.id.uuidString)
                }
                if !activeCustomColumns.isEmpty {
                    let columnUUIDs = activeCustomColumns.map { $0.id }
                    let valuesMap = try await gridService.fetchCustomCellValues(columnUUIDs: columnUUIDs, recordIds: recordIds)
                    for (index, recordId) in recordIds.enumerated() {
                        let recordValues = valuesMap[recordId] ?? [:]
                        for column in activeCustomColumns {
                            if let value = recordValues[column.id] ?? nil {
                                rows[index][column.id.uuidString] = value
                            } else {
                                rows[index][column.id.uuidString] = NSNull()
                            }
                        }
                    }
                }
                let total = try await gridService.countGroups(filters: effectiveFilters)
                
                // Store current grid data for search
                currentGridData = rows
                currentPageOffset = offset
                currentPageLimit = limit
                
                coordinator?.send(event: "pageData", payload: [
                    "entityType": entityType.rawValue,
                    "offset": offset,
                    "rows": rows,
                    "total": total
                ])
            }
        } catch {
            await report(error: error)
        }
    }
    
    // MARK: - Search Functionality
    
    func performSearch(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            currentSearchIndex = -1
            coordinator?.send(event: "searchResults", payload: [
                "query": "",
                "results": [],
                "currentIndex": -1
            ])
            return
        }
        
        let searchQuery = query.lowercased()
        var results: [GridSearchResult] = []
        
        for (rowIndex, row) in currentGridData.enumerated() {
            for (columnId, value) in row {
                // Skip recordId and other metadata columns
                if columnId == "recordId" { continue }
                
                // Convert value to string for searching
                let stringValue: String
                if let str = value as? String {
                    stringValue = str
                } else if let num = value as? NSNumber {
                    stringValue = num.stringValue
                } else if let arr = value as? [String] {
                    stringValue = arr.joined(separator: " ")
                } else if value is NSNull {
                    continue
                } else {
                    stringValue = String(describing: value)
                }
                
                // Check if the search query matches
                if stringValue.lowercased().contains(searchQuery) {
                    let recordId = row["recordId"] as? String ?? ""
                    results.append(GridSearchResult(
                        recordId: recordId,
                        columnId: columnId,
                        rowIndex: rowIndex,
                        matchText: stringValue
                    ))
                }
            }
        }
        
        searchResults = results
        currentSearchIndex = results.isEmpty ? -1 : 0
        
        // Send search results to web view
        coordinator?.send(event: "searchResults", payload: [
            "query": query,
            "results": results.map { $0.toDictionary() },
            "currentIndex": currentSearchIndex,
            "total": results.count
        ])
        
        // Navigate to first result if available
        if let firstResult = results.first {
            navigateToSearchResult(firstResult)
        }
    }
    
    func navigateToNextResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchResults.count
        navigateToCurrentResult()
    }
    
    func navigateToPreviousResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = currentSearchIndex <= 0 ? searchResults.count - 1 : currentSearchIndex - 1
        navigateToCurrentResult()
    }
    
    private func navigateToCurrentResult() {
        guard currentSearchIndex >= 0 && currentSearchIndex < searchResults.count else { return }
        let result = searchResults[currentSearchIndex]
        navigateToSearchResult(result)
        
        coordinator?.send(event: "searchNavigate", payload: [
            "currentIndex": currentSearchIndex,
            "total": searchResults.count,
            "result": result.toDictionary()
        ])
    }
    
    private func navigateToSearchResult(_ result: GridSearchResult) {
        // Calculate the absolute row index (accounting for pagination)
        let absoluteRowIndex = currentPageOffset + result.rowIndex
        
        // Send scroll and highlight event to web view with all necessary information
        // Mark as search active so the web view doesn't steal focus from search field
        coordinator?.send(event: "searchScrollToCell", payload: [
            "recordId": result.recordId,
            "columnId": result.columnId,
            "rowIndex": result.rowIndex,
            "absoluteRowIndex": absoluteRowIndex,
            "pageOffset": currentPageOffset,
            "scrollIntoView": true,
            "highlight": true,
            "matchText": result.matchText,
            "isSearchActive": true  // Prevent cell focus during search
        ])
    }
    
    func clearSearch() {
        searchText = ""
        searchResults = []
        currentSearchIndex = -1
        isSearchActive = false
        coordinator?.send(event: "searchClear", payload: [:])
    }
    
    private func processEdit(_ edit: GridEditPayload) async {
        print("📝 GridViewViewModel: Processing edit - recordId: \(edit.recordId), columnId: \(edit.columnId)")
        do {
            switch edit.entityType {
            case .contacts:
                let payload = edit.value.asGridCellValuePayload()
                let contact = try await gridService.editContact(sessionId: sessionId, phone: edit.recordId, columnId: edit.columnId, newValue: payload)
                print("✅ GridViewViewModel: Edit saved successfully for contact \(contact.phone)")
                var row = contact.toGridDictionary()
                row[GridViewService.ContactColumns.groups] = try await gridService.groupsWithColors(for: contact)
                row[GridViewService.ContactColumns.tags] = gridService.tagNames(for: contact)
                row[GridViewService.ContactColumns.relationships] = gridService.relationshipNames(for: contact)
                print("📝 GridViewViewModel: Sending editApplied for row with recordId: \(row["recordId"] ?? "missing")")
                coordinator?.send(event: "editApplied", payload: [
                    "entityType": edit.entityType.rawValue,
                    "row": row
                ])
            case .groups:
                let payload = edit.value.asGridCellValuePayload()
                // Handle both UUID format and integer IDs (legacy format)
                let groupId: UUID
                if let uuid = UUID(uuidString: edit.recordId) {
                    groupId = uuid
                } else if let integerId = Int(edit.recordId) {
                    // Convert integer ID to UUID format: 00000000-0000-0000-0000-%012d
                    let uuidString = String(format: "00000000-0000-0000-0000-%012d", integerId)
                    guard let convertedUUID = UUID(uuidString: uuidString) else {
                        throw GridViewService.GridViewServiceError.invalidValue("Failed to convert integer ID to UUID: \(edit.recordId)")
                    }
                    groupId = convertedUUID
                } else {
                    throw GridViewService.GridViewServiceError.invalidValue("Invalid group identifier format: \(edit.recordId)")
                }
                let group = try await gridService.editGroup(sessionId: sessionId, groupID: groupId, columnId: edit.columnId, newValue: payload)
                var row = group.toGridDictionary()
                row[GridViewService.GroupColumns.tags] = gridService.tagNames(for: group)
                row[GridViewService.GroupColumns.children] = try await gridService.childGroupNames(for: group)
                row[GridViewService.GroupColumns.parents] = try await gridService.parentGroupNames(for: group)
                coordinator?.send(event: "editApplied", payload: [
                    "entityType": edit.entityType.rawValue,
                    "row": row
                ])
            }
        } catch let serviceError as GridViewService.GridViewServiceError {
            coordinator?.send(event: "editError", payload: [
                "entityType": edit.entityType.rawValue,
                "recordId": edit.recordId,
                "columnId": edit.columnId
            ])
            enqueueEditError(serviceError, edit: edit)
        } catch {
            await report(error: error)
        }
    }
    
    private func processCreateCustomColumn(request: CreateCustomColumnRequest) async {
        do {
            let column = GridCustomColumn(
                viewId: request.viewUUID,
                entityType: request.entityType,
                userId: request.userId,
                name: request.name,
                dataType: request.dataType
            )
            try await persistCustomColumn(column)
        } catch {
            await report(error: error)
        }
    }

    private func persistCustomColumn(_ column: GridCustomColumn) async throws {
        try await gridService.save(customColumn: column)
        let updatedColumns = try await gridService.fetchCustomColumns(for: column.entityType, userId: column.userId, viewUUID: column.viewId)
        coordinator?.send(event: "customColumnsUpdated", payload: [
            "entityType": column.entityType.rawValue,
            "columns": updatedColumns.map { $0.toDictionary() }
        ])
        if let activeView, column.entityType == activeView.entityType {
            await reloadCustomColumns(for: activeView)
        }
    }
    
    private func enqueueEditError(_ error: GridViewService.GridViewServiceError, edit: GridEditPayload) {
        pendingEditErrors.append(PendingEditError(error: error, edit: edit))
        errorAggregationTask?.cancel()
        errorAggregationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            await self?.flushPendingEditErrors()
        }
    }
    
    @MainActor
    private func flushPendingEditErrors() {
        guard !pendingEditErrors.isEmpty else {
            errorAggregationTask = nil
            return
        }
        let captured = pendingEditErrors
        pendingEditErrors.removeAll()
        errorAggregationTask = nil
        
        let message = gridService.batchNotificationMessage(for: captured.map { $0.error }) ?? "Unable to save pasted data"
        presentErrorIfNeeded(message)
    }
    
    @MainActor
    private func report(error: Error) async {
        presentErrorIfNeeded(error.localizedDescription)
    }
    
    @MainActor
    private func presentErrorIfNeeded(_ message: String) {
        let now = Date()
        if lastPresentedErrorMessage == message,
           let lastDate = lastPresentedErrorDate,
           now.timeIntervalSince(lastDate) < 2 {
            return
        }
        lastPresentedErrorMessage = message
        lastPresentedErrorDate = now
        lastError = message
        SystemNotificationDispatcher.shared.post(title: "Grid View", body: message)
        coordinator?.send(event: "error", payload: ["message": message])
    }
}

// MARK: - Message Payloads

struct GridEditPayload: Decodable {
    let entityType: GridEntityType
    let recordId: String
    let columnId: String
    let value: GridEditValue
}

struct GridEditValue: Decodable {
    let rawValue: AnyCodable?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            rawValue = nil
        } else if let boolValue = try? container.decode(Bool.self) {
            rawValue = AnyCodable(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            rawValue = AnyCodable(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            rawValue = AnyCodable(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            rawValue = AnyCodable(stringValue)
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            rawValue = AnyCodable(arrayValue.map { $0.value })
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            rawValue = AnyCodable(dictValue.mapValues { $0.value })
        } else {
            rawValue = nil
        }
    }
    
    func asGridCellValuePayload() -> GridViewService.GridCellValuePayload {
        guard let rawValue else { return .empty }
        switch rawValue.value {
        case let string as String:
            return .string(string)
        case let number as Double:
            return .number(number)
        case let number as Int:
            return .number(Double(number))
        case let array as [Any]:
            let stringValues = array.compactMap { $0 as? String }
            return .chips(stringValues)
        default:
            return .empty
        }
    }
}

struct CreateCustomColumnRequest: Decodable {
    let entityType: GridEntityType
    let viewUUID: UUID?
    let userId: String
    let name: String
    let dataType: GridColumnDataType
}

// MARK: - Search Result

struct GridSearchResult {
    let recordId: String
    let columnId: String
    let rowIndex: Int
    let matchText: String
    
    func toDictionary() -> [String: Any] {
        return [
            "recordId": recordId,
            "columnId": columnId,
            "rowIndex": rowIndex,
            "matchText": matchText
        ]
    }
}

// MARK: - Row Serialization Helpers

private extension Contact {
    func toGridDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "recordId": phone,
            GridViewService.ContactColumns.name: name,
            GridViewService.ContactColumns.phone: phone,
            GridViewService.ContactColumns.totalMessages: totalMessages,
            GridViewService.ContactColumns.messagesSent: messagesSentCount,
            GridViewService.ContactColumns.messagesReceived: messagesReceivedCount,
            GridViewService.ContactColumns.groups: [],
            GridViewService.ContactColumns.tags: [],
            GridViewService.ContactColumns.relationships: []
        ]
        
        // Handle optional values - use empty strings for text fields, null for dates
        dict[GridViewService.ContactColumns.firstName] = firstName ?? ""
        dict[GridViewService.ContactColumns.lastName] = lastName ?? ""
        dict[GridViewService.ContactColumns.nickname] = nickname ?? ""
        dict[GridViewService.ContactColumns.email] = email ?? ""
        dict[GridViewService.ContactColumns.address] = address ?? ""
        dict[GridViewService.ContactColumns.notes] = notes ?? ""
        
        // Dates: use ISO string if available, otherwise null
        if let creationDate = creationDate {
            dict[GridViewService.ContactColumns.creationDate] = ISO8601DateFormatter().string(from: creationDate)
        } else {
            dict[GridViewService.ContactColumns.creationDate] = NSNull()
        }
        
        if let birthday = birthday {
            dict[GridViewService.ContactColumns.birthday] = ISO8601DateFormatter().string(from: birthday)
        } else {
            dict[GridViewService.ContactColumns.birthday] = NSNull()
        }
        
        // Last message dates: use ISO string if available, otherwise empty string (not null)
        if let lastMessageReceived = lastMessageReceivedDate ?? lastMessageDate {
            dict[GridViewService.ContactColumns.lastMessageReceived] = ISO8601DateFormatter().string(from: lastMessageReceived)
        } else {
            dict[GridViewService.ContactColumns.lastMessageReceived] = ""
        }
        
        if let lastMessageSent = lastMessageSentDate ?? lastMessageDate {
            dict[GridViewService.ContactColumns.lastMessageSent] = ISO8601DateFormatter().string(from: lastMessageSent)
        } else {
            dict[GridViewService.ContactColumns.lastMessageSent] = ""
        }
        
        // Profile photo: convert to base64 data URL if available
        if let photoData = profilePhotoData, !photoData.isEmpty {
            let base64 = photoData.base64EncodedString()
            dict[GridViewService.ContactColumns.profilePhoto] = "data:image/png;base64,\(base64)"
        } else {
            dict[GridViewService.ContactColumns.profilePhoto] = ""
        }
        
        return dict
    }
}

private extension ContactGroup {
    func toGridDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "recordId": id.uuidString,
            GridViewService.GroupColumns.name: name,
            GridViewService.GroupColumns.createdAt: ISO8601DateFormatter().string(from: createdAt),
            GridViewService.GroupColumns.participants: Array(memberPhones),
            GridViewService.GroupColumns.size: memberCount,
            GridViewService.GroupColumns.tags: [],
            GridViewService.GroupColumns.children: [],
            GridViewService.GroupColumns.parents: []
        ]
        
        // Handle optional color - use empty string if missing
        dict[GridViewService.GroupColumns.color] = colorHexString ?? ""
        
        return dict
    }
}

private extension GridViewConfig {
    func toDictionary() -> [String: Any] {
        return [
            "uuid": id.uuidString,
            "name": name,
            "entityType": entityType.rawValue,
            "userId": userId,
            "visibleColumns": visibleColumns,
            "frozenColumns": frozenColumns,
            "columnOrder": columnOrder,
            "sortModel": sortModel.map { ["columnId": $0.columnId, "direction": $0.direction.rawValue] },
            "filterModel": filterModel.mapValues { $0.value },
            "createdAt": ISO8601DateFormatter().string(from: createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt)
        ]
    }
}

private extension GridCustomColumn {
    func toDictionary() -> [String: Any] {
        return [
            "uuid": id.uuidString,
            "viewUUID": viewId?.uuidString as Any,
            "entityType": entityType.rawValue,
            "userId": userId,
            "name": name,
            "dataType": dataType.rawValue,
            "isVisible": isVisible,
            "orderIndex": orderIndex as Any,
            "createdAt": ISO8601DateFormatter().string(from: createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt)
        ]
    }
}

private func sanitizeColumnList(_ columns: [String], allowed: Set<String>? = nil) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for column in columns where !column.isEmpty {
        if let allowed, !allowed.contains(column) { continue }
        if seen.insert(column).inserted {
            result.append(column)
        }
    }
    return result
}

private extension GridViewViewModel {
    func reloadCustomColumns(for view: GridViewConfig?) async {
        guard let view else {
            activeCustomColumns = []
            return
        }
        do {
            activeCustomColumns = try await gridService.fetchCustomColumns(for: view.entityType, userId: view.userId, viewUUID: view.id)
        } catch {
            await report(error: error)
        }
    }

    func allowedColumnIds(for entity: GridEntityType) -> Set<String> {
        switch entity {
        case .contacts:
            let baseColumns = [
                GridViewService.ContactColumns.name,
                GridViewService.ContactColumns.firstName,
                GridViewService.ContactColumns.lastName,
                GridViewService.ContactColumns.nickname,
                GridViewService.ContactColumns.phone,
                GridViewService.ContactColumns.email,
                GridViewService.ContactColumns.address,
                GridViewService.ContactColumns.notes,
                GridViewService.ContactColumns.creationDate,
                GridViewService.ContactColumns.birthday,
                GridViewService.ContactColumns.groups,
                GridViewService.ContactColumns.tags,
                GridViewService.ContactColumns.relationships,
                GridViewService.ContactColumns.totalMessages,
                GridViewService.ContactColumns.messagesSent,
                GridViewService.ContactColumns.messagesReceived,
                GridViewService.ContactColumns.lastMessageReceived,
                GridViewService.ContactColumns.lastMessageSent,
                GridViewService.ContactColumns.profilePhoto
            ]
            return Set(baseColumns + activeCustomColumns.map { $0.id.uuidString })
        case .groups:
            let baseColumns = [
                GridViewService.GroupColumns.name,
                GridViewService.GroupColumns.participants,
                GridViewService.GroupColumns.color,
                GridViewService.GroupColumns.createdAt,
                GridViewService.GroupColumns.size,
                GridViewService.GroupColumns.tags,
                GridViewService.GroupColumns.children,
                GridViewService.GroupColumns.parents
            ]
            return Set(baseColumns + activeCustomColumns.map { $0.id.uuidString })
        }
    }
    
    func defaultViewConfiguration(for entity: GridEntityType) -> GridViewConfig {
        let columns = defaultColumnOrder(for: entity)
        return GridViewConfig(
            name: defaultViewBaseName(for: entity),
            entityType: entity,
            visibleColumns: columns,
            frozenColumns: defaultFrozenColumns(for: entity),
            columnOrder: columns,
            sortModel: [defaultSortDescriptor(for: entity)],
            filterModel: [:]
        )
    }
    
    func defaultColumnOrder(for entity: GridEntityType) -> [String] {
        switch entity {
        case .contacts:
            return [
                GridViewService.ContactColumns.name,
                GridViewService.ContactColumns.firstName,
                GridViewService.ContactColumns.lastName,
                GridViewService.ContactColumns.nickname,
                GridViewService.ContactColumns.phone,
                GridViewService.ContactColumns.email,
                GridViewService.ContactColumns.address,
                GridViewService.ContactColumns.notes,
                GridViewService.ContactColumns.creationDate,
                GridViewService.ContactColumns.birthday,
                GridViewService.ContactColumns.groups,
                GridViewService.ContactColumns.tags,
                GridViewService.ContactColumns.relationships,
                GridViewService.ContactColumns.totalMessages,
                GridViewService.ContactColumns.messagesSent,
                GridViewService.ContactColumns.messagesReceived,
                GridViewService.ContactColumns.lastMessageReceived,
                GridViewService.ContactColumns.lastMessageSent,
                GridViewService.ContactColumns.profilePhoto
            ]
        case .groups:
            return [
                GridViewService.GroupColumns.name,
                GridViewService.GroupColumns.participants,
                GridViewService.GroupColumns.color,
                GridViewService.GroupColumns.createdAt,
                GridViewService.GroupColumns.size,
                GridViewService.GroupColumns.tags,
                GridViewService.GroupColumns.children,
                GridViewService.GroupColumns.parents
            ]
        }
    }
    
    func defaultFrozenColumns(for entity: GridEntityType) -> [String] {
        switch entity {
        case .contacts:
            return [GridViewService.ContactColumns.name]
        case .groups:
            return [GridViewService.GroupColumns.name]
        }
    }
    
    func defaultSortDescriptor(for entity: GridEntityType) -> GridSortDescriptor {
        switch entity {
        case .contacts:
            // Default sort: A-Z by name, with null/empty at the end
            return GridSortDescriptor(columnId: GridViewService.ContactColumns.name, direction: .ascending)
        case .groups:
            return GridSortDescriptor(columnId: GridViewService.GroupColumns.name, direction: .ascending)
        }
    }
    
    func defaultViewBaseName(for entity: GridEntityType) -> String {
        switch entity {
        case .contacts:
            return "Contacts View"
        case .groups:
            return "Groups View"
        }
    }
    
    func uniqueViewName(basedOn baseName: String) -> String {
        let existingNames = Set(availableViews.map { $0.name })
        if !existingNames.contains(baseName) {
            return baseName
        }
        var index = 2
        while existingNames.contains("\(baseName) \(index)") {
            index += 1
        }
        return "\(baseName) \(index)"
    }
}

