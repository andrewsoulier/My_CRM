# Settings System Documentation

## Overview

The My CRM application uses a unified settings system that automatically saves user preferences to a JSON file in the Application Support directory. This system provides real-time auto-save functionality, validation and repair of corrupt settings, and automatic migration from legacy settings files. The settings are used by both Swift application code and Python backend scripts.

## Architecture

### SettingsManager
- **Location**: `Core/Models/UserSettings.swift`
- **Type**: Singleton class (`SettingsManager.shared`)
- **Responsibility**: Manages all application settings with automatic persistence
- **Synchronization**: Connected to AppState for real-time canvas debug points updates

### Settings File Location
- **Path**: `~/Library/Application Support/My_CRM/User_Settings.json`
- **Format**: JSON with structured sections
- **Auto-creation**: File is created automatically if it doesn't exist

## Settings Structure

### Database Settings
```json
{
  "database": {
    "path": "/Users/username/Documents/MY_CRM/my_crm.db",
    "name": "my_crm.db"
  }
}
```

**Database Path Management**:
- The database path is read from `User_Settings.json` at `~/Library/Application Support/My_CRM/User_Settings.json`
- Default path: `~/Documents/MY_CRM/my_crm.db`
- The directory is automatically created if it doesn't exist when the database is first opened
- Users can change the database path through the Settings UI
- All components (Swift and Python) read the path from the settings file - no hardcoded paths

**Automatic Database Creation**: If the database file or directory does not exist, the system automatically:
1. Creates the parent directory with `withIntermediateDirectories: true`
2. Opens/creates the database file at the specified path
3. Creates all required tables (contacts, groups, messages, invites, canvases, batch_messages)
4. Sets up proper indexes and foreign key constraints

This ensures the app always has a valid database location without manual configuration.

### User Information
```json
{
  "user": {
    "name": "User Name",
    "phone": "+1 234-567-8900",
    "email": "user@example.com"
  }
}
```

### Application Preferences
```json
{
  "preferences": {
    "theme": "light",
    "notifications": true,
    "autoSync": true,
    "logLevel": "info",
    "runAtLogin": true,
    "uiDensity": "Normal"
  }
}
```

### Developer Settings
```json
{
  "developer": {
    "developerMode": false,
    "debugPoints": false,
    "showElementCoordinates": true,
    "showCanvasElementPoints": false
  }
}
```

**Developer Mode**
- Default: `false` for fresh installs to keep unfinished features hidden
- When enabled, unfinished navigation pages (marked as placeholders) become visible in the sidebar
- Toggling this setting immediately synchronizes with `AppState.isDeveloperModeEnabled`

### AI Integration Settings
```json
{
  "ai": {
    "selectedProvider": "openai",
    "enabledProviders": ["openai", "gemini", "claude"],
    "preferredModel": {
      "openai": "gpt-4o",
      "gemini": "gemini-pro",
      "claude": "claude-3-5-sonnet-20241022"
    }
  }
}
```

**Important Security Note**: API keys for AI providers are stored securely in macOS Keychain, NOT in the JSON settings file. The settings file only contains provider selection preferences.

**Supported AI Providers**:
- **OpenAI (ChatGPT)**: GPT-4 and GPT-3.5 models
- **Google Gemini**: Gemini Pro and Flash models
- **Anthropic Claude**: Claude 3 Sonnet, Opus, and Haiku models

**Keychain Storage**: API keys are stored using `KeychainManager.shared` with the service identifier `com.mycrm.apikeys`.

## Features

### Auto-Save Functionality
- **Trigger**: Any change to a setting automatically saves to file
- **Implementation**: Uses `onChange` modifiers in SwiftUI views
- **Performance**: Minimal overhead with efficient JSON serialization
- **Pretty Printing**: Settings file is formatted with pretty printing and sorted keys for readability

### Validation and Repair
- **Automatic Validation**: Settings are validated on load
- **Missing Key Detection**: Detects and repairs missing required settings
- **Corrupt File Handling**: Gracefully handles corrupt JSON by using defaults
- **Auto-Repair**: Missing values are automatically filled with defaults and saved
- **First-Run Safety**: Ensures valid settings even on first launch

### Settings Access
- **UI Integration**: All settings are bound directly to SwiftUI views
- **Real-time Updates**: Changes are immediately reflected in the UI
- **Persistence**: Settings survive app restarts and updates
- **Cross-Platform**: Used by both Swift application code and Python backend scripts

### Debug Features
- **Settings File Access**: Button in debug section opens settings file in default text editor
- **File Path Display**: Shows exact location of settings file
- **Text Selection**: File path can be copied for manual access

### Canvas Debug Points Synchronization
- **Real-time Updates**: Changes to debug settings in Settings UI immediately affect canvas debug points
- **Bidirectional Sync**: SettingsManager and AppState.debugSettings stay synchronized
- **Automatic Connection**: AppState automatically connects to SettingsManager on initialization
- **Consistent Defaults**: Both systems use the same default values for debug settings

## Implementation Details

### SettingsManager Methods

#### Core Operations
```swift
func loadSettings()          // Load settings from file
func saveSettings()          // Save current settings to file
```

#### Convenience Methods
```swift
func updateDatabasePath(_ path: String)
func updateUIDensity(_ density: String)
func updateDeveloperMode(_ enabled: Bool)
func updateDebugPoints(_ enabled: Bool)
func updateCanvasElementPoints(_ enabled: Bool)
func updateVCFPath(_ path: String)
```

### KeychainManager Methods

#### API Key Management
```swift
func saveAPIKey(_ key: String, for provider: String) -> Bool
func retrieveAPIKey(for provider: String) -> String?
func deleteAPIKey(for provider: String) -> Bool
func hasAPIKey(for provider: String) -> Bool
func listProvidersWithKeys() -> [String]
```

### AIServiceManager Methods

#### Provider Management
```swift
func getProvider(_ type: AIProviderType) -> AIProvider?
func getActiveProvider() -> AIProvider?
func selectProvider(_ type: AIProviderType)
func saveAPIKey(_ key: String, for providerType: AIProviderType) -> Bool
func removeAPIKey(for providerType: AIProviderType) -> Bool
func hasAPIKey(for providerType: AIProviderType) -> Bool
```

#### Connection Testing
```swift
func testConnection(for providerType: AIProviderType) async
```

#### AI Queries
```swift
func sendChatCompletion(messages: [ChatMessage], temperature: Double, maxTokens: Int?) async -> Result<String, AIProviderError>
func sendQuery(_ text: String, systemPrompt: String?) async -> Result<String, AIProviderError>
```

### SQLiteDataProvider Database Path Methods

#### Database Path Resolution
```swift
func getUserDatabasePath() -> String           // Gets path from settings (new or legacy)
func ensureValidDatabasePath(_ proposedPath: String) -> String  // Validates and creates default if needed
```

The `ensureValidDatabasePath` method:
- Checks if the proposed database path's directory exists
- If not, creates a default location at `~/Documents/MY_CRM/`
- Updates the settings file with the new path
- Returns the validated (or newly created) path
- Called automatically during database connection

#### Settings Synchronization
```swift
func setAppState(_ appState: AppState)  // Connect to AppState for sync
private func synchronizeToAppState()    // Sync settings to AppState
```

#### File Access
```swift
func getSettingsFilePath() -> String
func openSettingsFileInEditor()
```

### SwiftUI Integration

#### Binding Settings
```swift
@StateObject private var settingsManager = SettingsManager.shared

// In view body
TextField("Database Path", text: $settingsManager.settings.database.path)
    .onChange(of: settingsManager.settings.database.path) { newValue in
        settingsManager.updateDatabasePath(newValue)
    }
```

#### Auto-Save Pattern
Every setting change follows this pattern:
1. User modifies setting in UI
2. `onChange` modifier triggers
3. Convenience method updates the setting
4. `saveSettings()` is called automatically
5. JSON file is updated immediately

## Usage Examples

### Accessing Settings in Code
```swift
// Get current database path
let dbPath = SettingsManager.shared.settings.database.path

// Check if debug points are enabled
let debugEnabled = SettingsManager.shared.settings.developer.debugPoints

// Update a setting programmatically
SettingsManager.shared.updateUIDensity("Compact")
```

### Adding New Settings
1. Add property to appropriate settings struct in `UserSettings.swift`
2. Add convenience method in `SettingsManager`
3. Bind to UI element with `onChange` modifier
4. Update this documentation

### Debugging Settings
1. Open Settings view in the app
2. Navigate to Debug section
3. Click "Open Settings File in Text Editor"
4. Modify JSON directly if needed
5. Restart app to load changes

## File Management

### Automatic Directory Creation
The settings system automatically creates the Application Support directory structure:
```
~/Library/Application Support/My_CRM/
└── User_Settings.json
```

### Error Handling
- **File Read Errors**: Falls back to default settings
- **File Write Errors**: Logs error but continues operation
- **JSON Parse Errors**: Uses default settings and logs error
- **Directory Creation**: Handles permission issues gracefully

### Backup and Recovery
- **Manual Backup**: Copy the JSON file to backup location
- **Recovery**: Replace corrupted file with backup
- **Reset**: Delete file to restore default settings

## Development Guidelines

### Adding New Settings
1. **Define Structure**: Add to appropriate section in `UserSettings` struct
2. **Add Convenience Method**: Create update method in `SettingsManager`
3. **UI Integration**: Bind to SwiftUI view with auto-save
4. **Documentation**: Update this file with new setting details

### Best Practices
- **Default Values**: Always provide sensible defaults
- **Validation**: Validate setting values before saving
- **Error Handling**: Handle file I/O errors gracefully
- **Performance**: Use efficient JSON serialization
- **Threading**: Settings operations are main-thread safe

### Testing
- **File Operations**: Test with missing/corrupted settings file
- **Permission Issues**: Test with read-only Application Support
- **JSON Validation**: Test with malformed JSON
- **Auto-Save**: Verify immediate persistence of changes

## Python Integration

### Unified Settings Format
All Python scripts in the iMessage Server Scraper feature group now read from `User_Settings.json` instead of the legacy `User_Preferences` file. This ensures consistency between Swift and Python components.

### Python Script Compatibility
The following Python scripts have been updated to use `User_Settings.json`:
- `database_utils.py` - Database connection manager
- `start.py` - Main orchestrator script
- `import_contacts.py` - Contact import script
- `import_imessages.py` - iMessage import script
- `connectToChatGPT.py` - ChatGPT integration
- `process_new_contacts.py` - Contact processing
- `evaluate_date_of_first_contact.py` - Contact date evaluation
- `update_chatGPT.py` - ChatGPT update script
- `test_contacts.py` - Contact testing
- `vcf_check.py` - VCF validation

All scripts follow the same fallback pattern:
1. Check `~/Library/Application Support/My_CRM/User_Settings.json`
2. Fall back to script directory `User_Settings.json`
3. Use default path if neither exists

## Migration from Previous System

### Legacy Settings Migration
The system includes automatic migration from the old `User_Preferences` file to the new `User_Settings.json` format.

**Migration Process:**
1. **Automatic Detection**: On first run, `SettingsMigration` checks for old `User_Preferences` file
2. **Data Transfer**: Settings are decoded from old format and saved to new format
3. **Backup**: Old file is backed up as `User_Preferences.migrated` or `User_Preferences.backup`
4. **Seamless**: Migration happens transparently during app initialization

**Legacy Files:**
The following files have been deprecated and marked with `-- Old --` prefix:
- `App/Feature Groups/iMessage Server Scraper/Resources/-- Old -- User_Preferences`
- `App/Feature Groups/iMessage Server Scraper/Resources/-- Old -- User_Preferences_Template`
- `App/-- Old -- PreferencesView.swift` (replaced by `UI/Modals/SettingsView.swift`)

### Migration Components
- **SettingsMigration.swift**: Handles one-time migration from old to new format
- **FirstRunSetup.swift**: Calls migration during app initialization
- **SettingsManager.validateAndRepairSettings()**: Repairs corrupt or incomplete settings

## Troubleshooting

### Common Issues

#### Settings Not Saving
- Check Application Support directory permissions
- Verify JSON serialization is working
- Check console for error messages

#### Settings Not Loading
- Verify settings file exists and is readable
- Check JSON format is valid
- Look for parse errors in console

#### File Access Issues
- Ensure app has Application Support access
- Check macOS security settings
- Verify file permissions

### Debug Commands
```bash
# Check if settings file exists
ls -la "~/Library/Application Support/My_CRM/User_Settings.json"

# View settings file content
cat "~/Library/Application Support/My_CRM/User_Settings.json"

# Check file permissions
ls -la "~/Library/Application Support/My_CRM/"
```

## Future Enhancements

### Planned Features
- **Settings Import/Export**: Backup and restore settings
- **Settings Validation**: Schema validation for settings file
- **Settings Sync**: Cloud sync for settings across devices
- **Settings UI**: Dedicated settings management interface

### Performance Improvements
- **Lazy Loading**: Load settings only when needed
- **Batch Updates**: Group multiple changes for efficiency
- **Compression**: Compress settings file for large configurations

---

**Note**: This documentation should be updated whenever the settings system is modified to ensure developers understand the current implementation and usage patterns.
