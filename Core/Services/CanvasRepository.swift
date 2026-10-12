import Foundation
import SwiftUI

// MARK: - Database Logging Utility

class DatabaseLogger {
    static let shared = DatabaseLogger()
    private let logFile: URL
    
    private init() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Could not access Documents directory")
        }
        self.logFile = documentsPath.appendingPathComponent("database_changes.log")
    }
    
    func logDatabaseOperation(operation: String, details: String, success: Bool, callStack: [String] = []) {
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        let callStackString = callStack.isEmpty ? "No call stack" : callStack.joined(separator: " → ")
        
        let logEntry = """
        [\(timestamp)] \(operation) - \(success ? "SUCCESS" : "FAILED")
        Details: \(details)
        Call Stack: \(callStackString)
        ----------------------------------------
        
        """
        
        // Write to file
        if let data = logEntry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
        
        // Also print to console for immediate feedback
        print("🔍 DB LOG: \(operation) - \(success ? "SUCCESS" : "FAILED")")
        print("🔍 Details: \(details)")
        print("🔍 Call Stack: \(callStackString)")
    }
    
    func getCallStack() -> [String] {
        return Thread.callStackSymbols.prefix(10).map { symbol in
            // Extract function name from stack symbol
            let components = symbol.components(separatedBy: " ")
            if components.count > 3 {
                return components[3]
            }
            return symbol
        }
    }
}

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Repository Protocol

protocol CanvasRepository {
    func load() -> (nodes: [ContactNode], groups: [GroupCircle], state: CanvasState)
    func save(nodes: [ContactNode], groups: [GroupCircle], state: CanvasState)
}

// MARK: - Database Canvas Repository

class DatabaseCanvasRepository: CanvasRepository {
    private let canvasManager = CanvasManager()
    
    init() {
        // No initialization needed - using Swift CanvasManager
    }
    
    func load() -> (nodes: [ContactNode], groups: [GroupCircle], state: CanvasState) {
        // For now, return empty state - this will be implemented when we have active canvas loading
        return (nodes: [], groups: [], state: CanvasState())
    }
    
    func save(nodes: [ContactNode], groups: [GroupCircle], state: CanvasState) {
        // Convert nodes and groups to canvas elements
        let elements = nodes.map { $0.toCanvasElement() } + groups.compactMap { $0.toCanvasElement() }
        
        // Create a temporary canvas for saving
        let canvas = Canvas(
            id: UUID().uuidString,
            name: "Auto-saved Canvas",
            elements: elements,
            canvasType: .groupMap,
            canvasState: state
        )
        
        // Save to database
        _ = createCanvas(canvas)
    }
    
    // MARK: - Canvas Management Methods
    
    func createCanvas(_ canvas: Canvas) -> Bool {
        let callStack = DatabaseLogger.shared.getCallStack()
        let details = "Creating canvas: \(canvas.name) (ID: \(canvas.id)) with \(canvas.elements.count) elements"
        
        // Update the canvas with current timestamp for lastSaved
        var updatedCanvas = canvas
        updatedCanvas.lastSaved = Date()
        updatedCanvas.dateUpdated = Date()
        
        let success = canvasManager.createCanvas(updatedCanvas)
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "CREATE_CANVAS",
            details: details,
            success: success,
            callStack: callStack
        )
        
        return success
    }
    
    func getCanvas(id: String) -> Canvas? {
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "GET_CANVAS_BY_ID",
            details: "Fetching canvas from database with ID: \(id)",
            success: true
        )
        
        if let canvas = canvasManager.getCanvas(id: id) {
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "GET_CANVAS_BY_ID_SUCCESS",
                details: "Successfully fetched canvas: \(canvas.name) (ID: \(canvas.id)) with \(canvas.elements.count) elements",
                success: true
            )
            return canvas
        } else {
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "GET_CANVAS_BY_ID_FAILED",
                details: "Failed to fetch canvas from database for ID: \(id)",
                success: false
            )
            return nil
        }
    }
    
    func getAllCanvases(type: CanvasType? = nil) -> [Canvas] {
        let callStack = DatabaseLogger.shared.getCallStack()
        let typeString = type?.rawValue ?? "all types"
        let details = "Fetching all canvases of type: \(typeString)"
        
        let canvases = canvasManager.getAllCanvases(type: type)
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "GET_ALL_CANVASES",
            details: details + " - Found \(canvases.count) canvases",
            success: true,
            callStack: callStack
        )
        
        return canvases
    }
    
    func getGroupMapCanvasesOrdered() -> [Canvas] {
        let canvases = getAllCanvases(type: .groupMap)
        
        // Sort by favorites first, then by date created (newest first)
        let sortedCanvases = canvases.sorted { canvas1, canvas2 in
            let isFavorite1 = canvas1.metadata["favorite"] == "true"
            let isFavorite2 = canvas2.metadata["favorite"] == "true"
            
            if isFavorite1 != isFavorite2 {
                return isFavorite1 // Favorites come first
            }
            
            // Within each group (favorites/non-favorites), sort by date created (newest first)
            return canvas1.dateCreated > canvas2.dateCreated
        }
        
        // Limit to the most recent 20 canvases to prevent UI hanging
        return Array(sortedCanvases.prefix(20))
    }
    
    func getLastEditedCanvas(type: CanvasType = .groupMap) -> Canvas? {
        let canvases = getAllCanvases(type: type)
        
        // Return the canvas with the most recent dateUpdated
        return canvases.max { canvas1, canvas2 in
            canvas1.dateUpdated < canvas2.dateUpdated
        }
    }
    
    func toggleCanvasFavorite(canvasId: String) -> Bool {
        guard let canvas = getCanvas(id: canvasId) else { return false }
        
        var updatedCanvas = canvas
        let currentFavorite = updatedCanvas.metadata["favorite"] == "true"
        updatedCanvas.metadata["favorite"] = currentFavorite ? "false" : "true"
        
        return updateCanvas(updatedCanvas)
    }
    
    func updateCanvas(_ canvas: Canvas) -> Bool {
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "UPDATE_CANVAS",
            details: "Updating canvas: \(canvas.name) (ID: \(canvas.id)) with \(canvas.elements.count) elements",
            success: true
        )
        
        // Update the canvas with current timestamp for lastSaved
        var updatedCanvas = canvas
        updatedCanvas.lastSaved = Date()
        updatedCanvas.dateUpdated = Date()
        
        let canvasData = updatedCanvas.toDatabaseFormat()
        
        let updates: [String: Any] = [
            "canvas_name": updatedCanvas.name,
            "canvas_elements": canvasData["canvas_elements"] ?? [],
            "canvas_state": canvasData["canvas_state"] ?? [:],
            "canvas_type": updatedCanvas.canvasType.rawValue,
            "metadata": updatedCanvas.metadata
        ]
        
        let success = canvasManager.updateCanvas(id: updatedCanvas.id, updates: updates)
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "UPDATE_CANVAS_RESULT",
            details: "Canvas update result: \(success ? "SUCCESS" : "FAILED")",
            success: success
        )
        
        return success
    }
    
    func deleteCanvas(id: String) -> Bool {
        let callStack = DatabaseLogger.shared.getCallStack()
        let details = "Deleting canvas with ID: \(id)"
        
        let success = canvasManager.deleteCanvas(id: id)
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "DELETE_CANVAS",
            details: details,
            success: success,
            callStack: callStack
        )
        
        return success
    }
    
    func addElement(to canvasId: String, element: CanvasElement) -> Bool {
        let callStack = DatabaseLogger.shared.getCallStack()
        let details = "Adding element \(element.id) of type \(element.elementType) to canvas \(canvasId)"
        
        let success = canvasManager.addElement(canvasId: canvasId, element: element)
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "ADD_ELEMENT",
            details: details,
            success: success,
            callStack: callStack
        )
        
        return success
    }
    
    func updateElement(in canvasId: String, element: CanvasElement) -> Bool {
        let callStack = DatabaseLogger.shared.getCallStack()
        let details = "Updating element \(element.id) of type \(element.elementType) in canvas \(canvasId)"
        
        let success = canvasManager.updateElement(canvasId: canvasId, elementId: element.id, element: element)
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "UPDATE_ELEMENT",
            details: details,
            success: success,
            callStack: callStack
        )
        
        return success
    }
    
    func removeElement(from canvasId: String, elementId: String) -> Bool {
        let callStack = DatabaseLogger.shared.getCallStack()
        let details = "Removing element \(elementId) from canvas \(canvasId)"
        
        let success = canvasManager.removeElement(canvasId: canvasId, elementId: elementId)
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "REMOVE_ELEMENT",
            details: details,
            success: success,
            callStack: callStack
        )
        
        return success
    }
    
    func searchCanvases(query: String, type: CanvasType? = nil) -> [Canvas] {
        return canvasManager.searchCanvases(query: query, type: type)
    }
    
    // MARK: - Private Helper Methods
    // Note: executeCanvasScript and jsonString methods removed - now using Swift CanvasManager
}



// MARK: - Canvas Update Service

class CanvasUpdateService: ObservableObject {
    private let repository: DatabaseCanvasRepository
    private var currentCanvasId: String?
    private var updateTimer: Timer?
    private let updateDebounceInterval: TimeInterval = 0.5
    
    @Published var isUpdating = false
    @Published var lastUpdateError: String?
    
    init(repository: DatabaseCanvasRepository = DatabaseCanvasRepository()) {
        self.repository = repository
    }
    
    // MARK: - Canvas Lifecycle
    
    func loadCanvas(id: String) -> Canvas? {
        currentCanvasId = id
        return repository.getCanvas(id: id)
    }
    
    func createCanvas(name: String, type: CanvasType = .groupMap) -> Canvas? {
        var canvas = Canvas(name: name, canvasType: type)
        canvas.lastSaved = Date() // Set lastSaved timestamp for new canvas
        if repository.createCanvas(canvas) {
            currentCanvasId = canvas.id
            return canvas
        }
        return nil
    }
    
    func saveCanvas(_ canvas: Canvas) {
        currentCanvasId = canvas.id
        debouncedUpdate { [weak self] in
            self?.performCanvasUpdate(canvas)
        }
    }
    
    func updateCanvas(_ canvas: Canvas) -> Bool {
        currentCanvasId = canvas.id
        return repository.updateCanvas(canvas)
    }
    
    func deleteCanvas(id: String) -> Bool {
        let success = repository.deleteCanvas(id: id)
        if success && currentCanvasId == id {
            currentCanvasId = nil
        }
        return success
    }
    
    // MARK: - Element Operations
    
    func addElement(_ element: CanvasElement, to canvasId: String) {
        debouncedUpdate { [weak self] in
            _ = self?.repository.addElement(to: canvasId, element: element)
        }
    }
    
    func updateElement(_ element: CanvasElement, in canvasId: String) {
        debouncedUpdate { [weak self] in
            _ = self?.repository.updateElement(in: canvasId, element: element)
        }
    }
    
    func removeElement(elementId: String, from canvasId: String) {
        debouncedUpdate { [weak self] in
            _ = self?.repository.removeElement(from: canvasId, elementId: elementId)
        }
    }
    
    // MARK: - Batch Operations
    
    func updateElementPositions(_ elements: [CanvasElement], in canvasId: String) {
        debouncedUpdate { [weak self] in
            for element in elements {
                _ = self?.repository.updateElement(in: canvasId, element: element)
            }
        }
    }
    
    func updateCanvasState(_ state: CanvasState, for canvasId: String) {
        debouncedUpdate { [weak self] in
            guard let canvas = self?.repository.getCanvas(id: canvasId) else { return }
            var updatedCanvas = canvas
            updatedCanvas.canvasState = state
            _ = self?.repository.updateCanvas(updatedCanvas)
        }
    }
    
    // MARK: - Search and Discovery
    
    func searchCanvases(query: String, type: CanvasType? = nil) -> [Canvas] {
        return repository.searchCanvases(query: query, type: type)
    }
    
    func getAllCanvases(type: CanvasType? = nil) -> [Canvas] {
        return repository.getAllCanvases(type: type)
    }
    
    // MARK: - Private Methods
    
    private func debouncedUpdate(_ update: @escaping () -> Void) {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateDebounceInterval, repeats: false) { _ in
            update()
        }
    }
    
    private func performCanvasUpdate(_ canvas: Canvas) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            DispatchQueue.main.async {
                self?.isUpdating = true
                self?.lastUpdateError = nil
            }
            
            let success = self?.repository.updateCanvas(canvas) ?? false
            
            DispatchQueue.main.async {
                self?.isUpdating = false
                if !success {
                    self?.lastUpdateError = "Failed to update canvas"
                }
            }
        }
    }
}

// MARK: - Canvas Conversion Extensions

extension ContactNode {
    func toCanvasElement() -> CanvasElement {
        return CanvasElement(
            id: phone, // Use phone number as element ID for database lookup
            elementType: .contact,
            location: position,
            scale: 1.0,
            width: size.width,
            height: size.height,
            rotation: 0,
            color: "#007AFF",
            contactUUID: contactUUID?.uuidString // Store contact UUID in canvas element
        )
    }
    
    static func fromCanvasElement(_ element: CanvasElement, dataProvider: SQLiteDataProvider? = nil) -> ContactNode {
        // Create a basic ContactNode - the actual contact data will be loaded separately
        let contactUUID = element.contactUUID != nil ? UUID(uuidString: element.contactUUID!) : nil
        
        // Initialize with empty values - we MUST get data from database
        var contactName = ""
        var profilePhotoData: Data? = nil
        var contactPhone = element.id // Use element ID as phone for database lookup
        
        // CRITICAL: We must have a dataProvider to look up contact data
        guard let dataProvider = dataProvider else {
            print("❌ CRITICAL ERROR: No dataProvider available for contact lookup!")
            print("❌ Cannot populate contact data for element: \(element.id)")
            // Return a placeholder that will be updated later when dataProvider is available
            return ContactNode(
                id: UUID(),
                name: "Loading...", // Temporary placeholder
                phone: element.id,
                contactUUID: contactUUID,
                profilePhotoData: nil,
                position: element.location,
                size: CGSize(width: element.width, height: element.height),
                isSelected: false
            )
        }
        
        // CRITICAL: We must be connected to the database
        guard dataProvider.isConnectedToDatabase else {
            print("❌ CRITICAL ERROR: DataProvider not connected to database!")
            print("❌ Cannot populate contact data for element: \(element.id)")
            return ContactNode(
                id: UUID(),
                name: "Database Not Connected", // Temporary placeholder
                phone: element.id,
                contactUUID: contactUUID,
                profilePhotoData: nil,
                position: element.location,
                size: CGSize(width: element.width, height: element.height),
                isSelected: false
            )
        }
        
        // Look up contact in database using the phone number stored in element.id
        // The element.id contains the phone number when the contact was added to canvas
        if let contact = dataProvider.getContact(by: element.id) {
            contactName = contact.displayName
            contactPhone = contact.phone
            profilePhotoData = contact.profilePhotoData
            print("✅ Successfully found contact in database: \(contact.displayName) (\(contact.phone))")
        } else {
            print("❌ CRITICAL ERROR: Contact not found in database for phone: \(element.id)")
            print("📊 DataProvider has \(dataProvider.contacts.count) contacts loaded")
            print("📊 DataProvider connected: \(dataProvider.isConnectedToDatabase)")
            
            // List some contacts for debugging
            let sampleContacts = Array(dataProvider.contacts.prefix(5))
            print("📊 Sample contacts in dataProvider:")
            for contact in sampleContacts {
                print("  - \(contact.displayName) (\(contact.phone))")
            }
            
            // Return a placeholder indicating the contact was not found
            return ContactNode(
                id: UUID(),
                name: "Contact Not Found", // Clear indication of the problem
                phone: element.id,
                contactUUID: contactUUID,
                profilePhotoData: nil,
                position: element.location,
                size: CGSize(width: element.width, height: element.height),
                isSelected: false
            )
        }
        
        return ContactNode(
            id: UUID(), // Generate new UUID for UI purposes
            name: contactName,
            phone: contactPhone,
            contactUUID: contactUUID,
            profilePhotoData: profilePhotoData,
            position: element.location,
            size: CGSize(width: element.width, height: element.height),
            isSelected: false
        )
    }
}

extension GroupCircle {
    func toCanvasElement() -> CanvasElement? {
        // Only create canvas element if we have a database ID
        guard let dbId = databaseId else {
            // No database ID means the group was deleted or not properly saved
            return nil
        }
        
        let elementId = String(dbId) // Use just the database ID as element ID
        
        return CanvasElement(
            id: elementId,
            elementType: .group,
            location: center,
            scale: 1.0,
            width: width,  // Use actual width instead of radius * 2
            height: height,  // Use actual height instead of radius * 2
            rotation: rotation,
            color: color.toHexString(), // Store the actual group color
            groupUUID: id.uuidString // Store the group UUID separately
        )
    }
    
    func toCanvasElement(databaseId: String) -> CanvasElement {
        return CanvasElement(
            id: databaseId, // Use the database ID as the primary identifier
            elementType: .group,
            location: center,
            scale: 1.0,
            width: width,  // Use actual width instead of radius * 2
            height: height,  // Use actual height instead of radius * 2
            rotation: rotation,
            color: color.toHexString(), // Store the actual group color
            groupUUID: id.uuidString // Store the group UUID separately
        )
    }
    
    static func fromCanvasElement(_ element: CanvasElement, dataProvider: SQLiteDataProvider? = nil) -> GroupCircle? {
        // Get database integer ID from element
        guard let dbId = Int(element.id) else {
            print("⚠️ Invalid database ID in canvas element: \(element.id)")
            return nil
        }
        
        // Find ContactGroup by database integer ID (not UUID!)
        guard let dataProvider = dataProvider,
              let contactGroup = dataProvider.groups.first(where: { $0.databaseId == dbId }) else {
            print("⚠️ No group found for database ID: \(dbId)")
            return nil
        }
        
        print("✅ Found group '\(contactGroup.name)' for database ID: \(dbId)")
        
        // Create GroupCircle with real data from database
        var group = GroupCircle(
            id: UUID(),  // Generate new UUID (separate from database ID)
            name: contactGroup.name,
            center: element.location,
            radius: element.width / 2,
            color: contactGroup.color,
            rotation: element.rotation,
            databaseId: dbId
        )
        group.width = element.width
        group.height = element.height
        return group
    }
}

// MARK: - Color Extensions (removed duplicate - using CanvasModels.swift version)

// MARK: - In-Memory Implementation

class InMemoryCanvasRepository: CanvasRepository {
    private var nodes: [ContactNode] = []
    private var groups: [GroupCircle] = []
    private var state: CanvasState = CanvasState()
    
    func load() -> (nodes: [ContactNode], groups: [GroupCircle], state: CanvasState) {
        return (nodes: nodes, groups: groups, state: state)
    }
    
    func save(nodes: [ContactNode], groups: [GroupCircle], state: CanvasState) {
        self.nodes = nodes
        self.groups = groups
        self.state = state
    }
}

// MARK: - File-Based Implementation (for future use)

class FileCanvasRepository: CanvasRepository {
    private let fileManager = FileManager.default
    private let documentsPath: URL
    
    init() {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Could not access documents directory")
        }
        documentsPath = documentsURL
    }
    
    func load() -> (nodes: [ContactNode], groups: [GroupCircle], state: CanvasState) {
        let nodesURL = documentsPath.appendingPathComponent("canvas_nodes.json")
        let groupsURL = documentsPath.appendingPathComponent("canvas_groups.json")
        let stateURL = documentsPath.appendingPathComponent("canvas_state.json")
        
        var nodes: [ContactNode] = []
        var groups: [GroupCircle] = []
        var state = CanvasState()
        
        // Load nodes
        if let data = try? Data(contentsOf: nodesURL),
           let decodedNodes = try? JSONDecoder().decode([ContactNode].self, from: data) {
            nodes = decodedNodes
        }
        
        // Load groups
        if let data = try? Data(contentsOf: groupsURL),
           let decodedGroups = try? JSONDecoder().decode([GroupCircle].self, from: data) {
            groups = decodedGroups
        }
        
        // Load state
        if let data = try? Data(contentsOf: stateURL),
           let decodedState = try? JSONDecoder().decode(CanvasState.self, from: data) {
            state = decodedState
        }
        
        return (nodes: nodes, groups: groups, state: state)
    }
    
    func save(nodes: [ContactNode], groups: [GroupCircle], state: CanvasState) {
        let nodesURL = documentsPath.appendingPathComponent("canvas_nodes.json")
        let groupsURL = documentsPath.appendingPathComponent("canvas_groups.json")
        let stateURL = documentsPath.appendingPathComponent("canvas_state.json")
        
        // Save nodes
        if let data = try? JSONEncoder().encode(nodes) {
            try? data.write(to: nodesURL)
        }
        
        // Save groups
        if let data = try? JSONEncoder().encode(groups) {
            try? data.write(to: groupsURL)
        }
        
        // Save state
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL)
        }
    }
}
