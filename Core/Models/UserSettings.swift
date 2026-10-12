import Foundation
#if os(macOS)
import AppKit
#endif

// MARK: - User Settings Model
struct UserSettings: Codable {
    var database: DatabaseSettings
    var user: UserInfo
    var preferences: AppPreferences
    var developer: DeveloperSettings
    var ai: AISettings
    
    init() {
        self.database = DatabaseSettings()
        self.user = UserInfo()
        self.preferences = AppPreferences()
        self.developer = DeveloperSettings()
        self.ai = AISettings()
    }
}

// MARK: - Database Settings
struct DatabaseSettings: Codable {
    var path: String
    var name: String
    
    init() {
        // Default to Application Support/My_CRM/my_crm.db to avoid cloud-synced folders
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let databaseDirectory = appSupport.appendingPathComponent("My_CRM")
        self.path = databaseDirectory.appendingPathComponent("my_crm.db").path
        self.name = "my_crm.db"
    }
}

// MARK: - User Info
struct UserInfo: Codable {
    var name: String
    var phone: String
    var email: String
    
    init() {
        self.name = ""
        self.phone = ""
        self.email = ""
    }
}

// MARK: - App Preferences
struct AppPreferences: Codable {
    var theme: String
    var notifications: Bool
    var autoSync: Bool
    var logLevel: String
    var runAtLogin: Bool
    var uiDensity: String
    
    init() {
        self.theme = "light"
        self.notifications = true
        self.autoSync = true
        self.logLevel = "info"
        self.runAtLogin = true
        self.uiDensity = "Normal"
    }
}

// MARK: - Developer Settings
struct DeveloperSettings: Codable {
    var developerMode: Bool
    var debugPoints: Bool
    var showElementCoordinates: Bool
    var showCanvasElementPoints: Bool
    
    init() {
        self.developerMode = false
        self.debugPoints = false
        self.showElementCoordinates = true
        self.showCanvasElementPoints = false
    }
    
    private enum CodingKeys: String, CodingKey {
        case developerMode
        case debugPoints
        case showElementCoordinates
        case showCanvasElementPoints
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.developerMode = try container.decodeIfPresent(Bool.self, forKey: .developerMode) ?? false
        self.debugPoints = try container.decodeIfPresent(Bool.self, forKey: .debugPoints) ?? false
        self.showElementCoordinates = try container.decodeIfPresent(Bool.self, forKey: .showElementCoordinates) ?? true
        self.showCanvasElementPoints = try container.decodeIfPresent(Bool.self, forKey: .showCanvasElementPoints) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(developerMode, forKey: .developerMode)
        try container.encode(debugPoints, forKey: .debugPoints)
        try container.encode(showElementCoordinates, forKey: .showElementCoordinates)
        try container.encode(showCanvasElementPoints, forKey: .showCanvasElementPoints)
    }
}

// MARK: - AI Settings
struct AISettings: Codable {
    var selectedProvider: String
    var enabledProviders: [String]
    var preferredModel: [String: String] // Provider -> Model mapping
    
    init() {
        self.selectedProvider = ""
        self.enabledProviders = []
        self.preferredModel = [:]
    }
}

// MARK: - AI Provider Types
enum AIProviderType: String, CaseIterable, Codable {
    case openai = "openai"
    case gemini = "gemini"
    case claude = "claude"
    
    var displayName: String {
        switch self {
        case .openai: return "OpenAI (ChatGPT)"
        case .gemini: return "Google Gemini"
        case .claude: return "Anthropic Claude"
        }
    }
    
    var description: String {
        switch self {
        case .openai: return "GPT-4 and GPT-3.5 models for advanced language understanding"
        case .gemini: return "Google's multimodal AI for text and reasoning tasks"
        case .claude: return "Anthropic's AI assistant focused on safety and accuracy"
        }
    }
    
    var apiKeyURL: String {
        switch self {
        case .openai: return "https://platform.openai.com/api-keys"
        case .gemini: return "https://aistudio.google.com/app/apikey"
        case .claude: return "https://console.anthropic.com/settings/keys"
        }
    }
}

// MARK: - Settings Manager
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var settings: UserSettings
    private let settingsURL: URL
    
    // Reference to AppState for synchronization
    weak var appState: AppState?
    
    private init() {
        // Set up the settings file path in App Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let myCRMAppSupport = appSupport.appendingPathComponent("My_CRM")
        self.settingsURL = myCRMAppSupport.appendingPathComponent("User_Settings.json")
        
        // Initialize with default settings
        self.settings = UserSettings()
        
        // Load settings from file
        loadSettings()
    }
    
    // MARK: - AppState Connection
    
    func setAppState(_ appState: AppState) {
        self.appState = appState
        print("🔧 SettingsManager: Connected to AppState")
        
        // Synchronize current settings to AppState on main thread
        Task { @MainActor in
            synchronizeToAppState()
        }
    }
    
    // MARK: - File Operations
    
    func loadSettings() {
        do {
            // Ensure the directory exists
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), 
                                                  withIntermediateDirectories: true, 
                                                  attributes: nil)
            
            // Try to load from file
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                let data = try Data(contentsOf: settingsURL)
                
                // Try to decode the settings
                do {
                    let loadedSettings = try JSONDecoder().decode(UserSettings.self, from: data)
                    self.settings = loadedSettings
                    print("📁 SettingsManager: Loaded settings from \(settingsURL.path)")
                    
                    // Validate and repair any missing or invalid values
                    validateAndRepairSettings()
                } catch {
                    // JSON is corrupt or invalid, use defaults and save
                    print("⚠️ SettingsManager: Settings file is corrupt (\(error)), using defaults")
                    self.settings = UserSettings()
                    saveSettings()
                    print("📁 SettingsManager: Created new settings file with defaults")
                }
            } else {
                // File doesn't exist, save default settings
                saveSettings()
                print("📁 SettingsManager: Created new settings file at \(settingsURL.path)")
            }
        } catch {
            print("❌ SettingsManager: Failed to load settings: \(error)")
            // Keep default settings if loading fails
            self.settings = UserSettings()
            saveSettings()
        }
    }
    
    func saveSettings() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: settingsURL)
            print("💾 SettingsManager: Saved settings to \(settingsURL.path)")
        } catch {
            print("❌ SettingsManager: Failed to save settings: \(error)")
        }
    }
    
    // MARK: - Validation & Repair
    
    private func validateAndRepairSettings() {
        var needsRepair = false
        let defaults = UserSettings()
        
        // Validate database settings
        if settings.database.path.isEmpty {
            print("⚠️ SettingsManager: Database path is empty, using default")
            settings.database.path = defaults.database.path
            needsRepair = true
        }
        if settings.database.name.isEmpty {
            print("⚠️ SettingsManager: Database name is empty, using default")
            settings.database.name = defaults.database.name
            needsRepair = true
        }
        
        // Validate preferences
        if settings.preferences.theme.isEmpty {
            print("⚠️ SettingsManager: Theme is empty, using default")
            settings.preferences.theme = defaults.preferences.theme
            needsRepair = true
        }
        if settings.preferences.logLevel.isEmpty {
            print("⚠️ SettingsManager: Log level is empty, using default")
            settings.preferences.logLevel = defaults.preferences.logLevel
            needsRepair = true
        }
        if settings.preferences.uiDensity.isEmpty {
            print("⚠️ SettingsManager: UI density is empty, using default")
            settings.preferences.uiDensity = defaults.preferences.uiDensity
            needsRepair = true
        }
        
        // Save if any repairs were made
        if needsRepair {
            print("🔧 SettingsManager: Repaired settings, saving...")
            saveSettings()
        }
    }
    
    // MARK: - Convenience Methods
    
    func updateDatabasePath(_ path: String) {
        settings.database.path = path
        saveSettings()
    }
    
    func updateUIDensity(_ density: String) {
        settings.preferences.uiDensity = density
        saveSettings()
    }
    
    func updateDebugPoints(_ enabled: Bool) {
        settings.developer.debugPoints = enabled
        saveSettings()
        
        // Synchronize to AppState on main thread
        Task { @MainActor in
            synchronizeToAppState()
        }
    }
    
    func updateDeveloperMode(_ enabled: Bool) {
        settings.developer.developerMode = enabled
        saveSettings()
        
        Task { @MainActor in
            synchronizeToAppState()
        }
    }
    
    func updateCanvasElementPoints(_ enabled: Bool) {
        settings.developer.showCanvasElementPoints = enabled
        saveSettings()
        
        // Synchronize to AppState on main thread
        Task { @MainActor in
            synchronizeToAppState()
        }
    }
    
    // MARK: - Synchronization
    
    @MainActor
    private func synchronizeToAppState() {
        guard let appState = appState else {
            print("🔧 SettingsManager: No AppState reference available for synchronization")
            return
        }
        
        let developerModeEnabled = settings.developer.developerMode
        appState.isDeveloperModeEnabled = developerModeEnabled
        
        if !developerModeEnabled && appState.selectedPage.isPlaceholder {
            appState.selectPage(.peopleMaps)
        }
        
        // Update AppState debug settings to match SettingsManager
        appState.debugSettings.showDebugPoints = settings.developer.debugPoints
        appState.debugSettings.showElementCoordinates = settings.developer.showElementCoordinates
        appState.debugSettings.showCanvasElementPoints = settings.developer.showCanvasElementPoints
        
        print("🔧 SettingsManager: Synchronized debug settings to AppState")
        print("  - showDebugPoints: \(settings.developer.debugPoints)")
        print("  - showElementCoordinates: \(settings.developer.showElementCoordinates)")
        print("  - showCanvasElementPoints: \(settings.developer.showCanvasElementPoints)")
    }
    
    func updateVCFPath(_ path: String) {
        // Store VCF path in user info for now
        settings.user.phone = path // Reusing phone field temporarily
        saveSettings()
    }
    
    // MARK: - File Access
    
    func getSettingsFilePath() -> String {
        return settingsURL.path
    }
    
    func openSettingsFileInEditor() {
        #if os(macOS)
        NSWorkspace.shared.open(settingsURL)
        #endif
    }
}
