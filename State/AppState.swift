import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    // MARK: - Navigation State
    @Published var selectedPage: Page = .peopleMaps
    @Published var isPageNavBarVisible = true
    @Published var isContactsBarVisible = true
    @Published var isGroupsBarVisible = true
    @Published var isGridToolbarVisible = true
    @Published var isDeveloperModeEnabled = false
    
    // MARK: - UI State
    @Published var searchTerm = ""
    @Published var sortOption: ContactFilter.ContactSortOption = .name
    @Published var selectedContacts: Set<String> = []
    @Published var selectedGroup: UUID?
    @Published var selectedDeck: UUID?
    
    // MARK: - Canvas State
    @Published var canvasZoom: Double = 1.0
    @Published var canvasOffset: CGPoint = .zero
    @Published var isGridSnappingEnabled = false
    
    // MARK: - Debug Settings
    @Published var debugSettings = DebugSettings()
    
    // MARK: - Navigation Tree State
    @Published var expandedFolders: Set<String> = []
    
    // MARK: - Modal State
    @Published var showingSettings = false
    @Published var showingGroupEditor = false
    @Published var showingDeckEditor = false
    
    // MARK: - Error State
    @Published var lastError: String?
    @Published var showingError = false
    @Published var messageType: MessageType = .error
    
    // MARK: - Persistence
    private let userDefaults = UserDefaults.standard
    
    init() {
        print("🚨 AppState.init() called")
        print("🚨 AppState.init() - setting up initial state")
        print("🚨 AppState.init() - selectedPage: \(selectedPage)")
        print("🚨 AppState.init() - isPageNavBarVisible: \(isPageNavBarVisible)")
        print("🚨 AppState.init() - isContactsBarVisible: \(isContactsBarVisible)")
        print("🚨 AppState.init() - searchTerm: '\(searchTerm)'")
        print("🚨 AppState.init() - calling loadPersistedState()")
        loadPersistedState()
        
        // Connect to SettingsManager for synchronization
        connectToSettingsManager()
        
        print("🚨 AppState.init() completed")
    }
    
    // MARK: - Settings Synchronization
    
    private func connectToSettingsManager() {
        // Connect this AppState instance to SettingsManager
        SettingsManager.shared.setAppState(self)
        print("🔧 AppState: Connected to SettingsManager")
    }
    
    // MARK: - Navigation Methods
    func selectPage(_ page: Page) {
        let targetPage = (!isDeveloperModeEnabled && page.isPlaceholder) ? .peopleMaps : page
        selectedPage = targetPage
        savePersistedState()
    }
    
    func toggleGridToolbar() {
        isGridToolbarVisible.toggle()
        savePersistedState()
    }
    
    func togglePageNavBar() {
        isPageNavBarVisible.toggle()
        savePersistedState()
    }
    
    func toggleContactsBar() {
        isContactsBarVisible.toggle()
        savePersistedState()
    }
    
    func toggleGroupsBar() {
        isGroupsBarVisible.toggle()
        savePersistedState()
    }
    
    func collapseAllSiblings() {
        // Implementation for collapsing all sibling folders
        // This would be implemented when the navigation tree is built
    }
    
    func expandAllSiblings() {
        // Implementation for expanding all sibling folders
        // This would be implemented when the navigation tree is built
    }
    
    // MARK: - Selection Methods
    func selectContact(_ phone: String) {
        selectedContacts.insert(phone)
    }
    
    func deselectContact(_ phone: String) {
        selectedContacts.remove(phone)
    }
    
    func selectContacts(_ phones: [String]) {
        selectedContacts.formUnion(phones)
    }
    
    func clearSelection() {
        selectedContacts.removeAll()
    }
    
    func toggleContactSelection(_ phone: String) {
        if selectedContacts.contains(phone) {
            selectedContacts.remove(phone)
        } else {
            selectedContacts.insert(phone)
        }
    }
    
    // MARK: - Canvas Methods
    func setZoom(_ zoom: Double) {
        canvasZoom = max(0.1, min(5.0, zoom)) // Allow zoom from 10% to 500%
    }
    
    func resetZoom() {
        canvasZoom = 1.0
        canvasOffset = .zero
    }
    
    func toggleGridSnapping() {
        isGridSnappingEnabled.toggle()
    }
    
    // MARK: - Error Handling
    func showError(_ message: String) {
        lastError = message
        messageType = .error
        showingError = true
    }
    
    func showMessage(_ message: String) {
        lastError = message
        messageType = .message
        showingError = true
    }
    
    func clearError() {
        lastError = nil
        showingError = false
        messageType = .error
    }
    
    // MARK: - Persistence
    private func savePersistedState() {
        userDefaults.set(isPageNavBarVisible, forKey: "isPageNavBarVisible")
        userDefaults.set(isContactsBarVisible, forKey: "isContactsBarVisible")
        userDefaults.set(isGroupsBarVisible, forKey: "isGroupsBarVisible")
        userDefaults.set(isGridToolbarVisible, forKey: "isGridToolbarVisible")
        userDefaults.set(selectedPage.rawValue, forKey: "selectedPage")
        userDefaults.set(searchTerm, forKey: "searchTerm")
        userDefaults.set(sortOption.rawValue, forKey: "sortOption")
        userDefaults.set(isGridSnappingEnabled, forKey: "isGridSnappingEnabled")
    }
    
    private func loadPersistedState() {
        print("🚨 PERSISTENCE: loadPersistedState() called")
        print("🚨 PERSISTENCE: Loading isPageNavBarVisible")
        isPageNavBarVisible = userDefaults.object(forKey: "isPageNavBarVisible") as? Bool ?? true
        print("🚨 PERSISTENCE: Loading isContactsBarVisible")
        isContactsBarVisible = userDefaults.object(forKey: "isContactsBarVisible") as? Bool ?? true
        print("🚨 PERSISTENCE: Loading isGroupsBarVisible")
        isGroupsBarVisible = userDefaults.object(forKey: "isGroupsBarVisible") as? Bool ?? true
        print("🚨 PERSISTENCE: Loading isGridToolbarVisible")
        isGridToolbarVisible = userDefaults.object(forKey: "isGridToolbarVisible") as? Bool ?? true
        print("🚨 PERSISTENCE: Loading selectedPage")
        if let pageRawValue = userDefaults.string(forKey: "selectedPage"),
           let page = Page(rawValue: pageRawValue) {
            selectedPage = page
        }
        print("🚨 PERSISTENCE: Loading searchTerm")
        searchTerm = userDefaults.string(forKey: "searchTerm") ?? ""
        print("🚨 PERSISTENCE: Loading sortOption")
        if let sortRawValue = userDefaults.string(forKey: "sortOption"),
           let sort = ContactFilter.ContactSortOption(rawValue: sortRawValue) {
            sortOption = sort
        }
        isGridSnappingEnabled = userDefaults.object(forKey: "isGridSnappingEnabled") as? Bool ?? false
    }
}

// MARK: - Page Enum
enum Page: String, CaseIterable {
    case peopleMaps = "Relationship Maps"
    case gridView = "Grid View"
    case deckBuilder = "Group Details"
    case canvasManagement = "Canvas Management"
    case smartLists = "Smart Lists"
    case timeline = "Timeline View"
    case flashcardTrainer = "Flashcard Trainer"
    case quickSend = "Quick Send"
    case engagementDashboard = "Engagement Dashboard"
    case automationsManager = "Automations Manager"
    case tagManager = "Tag Manager"
    case groupsAndCircles = "Groups & Circles"
    case importSync = "Import/Sync"
    case settings = "Settings"
    
    var icon: String {
        switch self {
        case .peopleMaps: return "person.3.fill"
        case .gridView: return "square.grid.3x3.fill"
        case .deckBuilder: return "rectangle.stack"
        case .canvasManagement: return "rectangle.on.rectangle"
        case .smartLists: return "list.bullet"
        case .timeline: return "clock.fill"
        case .flashcardTrainer: return "brain.head.profile"
        case .quickSend: return "paperplane.fill"
        case .engagementDashboard: return "chart.bar.fill"
        case .automationsManager: return "gearshape.fill"
        case .tagManager: return "tag.fill"
        case .groupsAndCircles: return "person.2.fill"
        case .importSync: return "arrow.triangle.2.circlepath"
        case .settings: return "gear"
        }
    }
    
    var isPlaceholder: Bool {
        switch self {
        case .peopleMaps, .gridView, .deckBuilder, .canvasManagement, .quickSend, .settings:
            return false
        default:
            return true
        }
    }
}

// MARK: - Debug Settings
struct DebugSettings: Codable {
    var showDebugPoints: Bool = false  // Match SettingsManager default
    var showElementCoordinates: Bool = true
    var showCanvasElementPoints: Bool = false
    
    init() {
        // Load from UserDefaults first
        if let data = UserDefaults.standard.data(forKey: "debugSettings"),
           let settings = try? JSONDecoder().decode(DebugSettings.self, from: data) {
            self.showDebugPoints = settings.showDebugPoints
            self.showElementCoordinates = settings.showElementCoordinates
            self.showCanvasElementPoints = settings.showCanvasElementPoints
        }
        
        // Then override with User_Settings.json file if it exists
        loadFromUserPreferences()
    }
    
    private mutating func loadFromUserPreferences() {
        // Try to load from Application Support first
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let myCRMAppSupport = appSupport.appendingPathComponent("My_CRM")
            let preferencesPath = myCRMAppSupport.appendingPathComponent("User_Settings.json").path
            
            if FileManager.default.fileExists(atPath: preferencesPath) {
                loadFromPath(preferencesPath)
                return
            }
        }
        
        // If not found in Application Support, try to load from app bundle
        if let bundlePath = Bundle.main.resourcePath {
            let bundlePrefsPath = "\(bundlePath)/Feature Groups/iMessage Server Scraper/Resources/User_Settings.json"
            if FileManager.default.fileExists(atPath: bundlePrefsPath) {
                loadFromPath(bundlePrefsPath)
            }
        }
    }
    
    private mutating func loadFromPath(_ path: String) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let preferences = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let developer = preferences?["developer"] as? [String: Any] {
                if let debugPoints = (developer["debugPoints"] as? Bool) ?? (developer["debug_points"] as? Bool) {
                    self.showDebugPoints = debugPoints
                    self.showElementCoordinates = debugPoints
                }
                if let canvasElementPoints = (developer["showCanvasElementPoints"] as? Bool) ?? (developer["canvas_element_points"] as? Bool) {
                    self.showCanvasElementPoints = canvasElementPoints
                }
            }
        } catch {
            print("Failed to load debug settings from \(path): \(error)")
        }
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "debugSettings")
        }
    }
}

// MARK: - Message Type
enum MessageType {
    case error
    case message
    
    var title: String {
        switch self {
        case .error:
            return "Error"
        case .message:
            return "Message"
        }
    }
}
