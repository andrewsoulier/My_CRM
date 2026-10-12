# Database Path Management

## Overview
All database path references in the app are **dynamically pulled from SettingsManager** to ensure consistency and flexibility.

## Architecture

### Source of Truth
The **single source of truth** for the database path is:
```swift
SettingsManager.shared.settings.database.path
```

This value is loaded from `~/Library/Application Support/My_CRM/User_Settings.json`

### Default Path
If no settings file exists, the default path is set to:
```swift
let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
"\(documentsPath)/MY_CRM/my_crm.db"
```

In a sandboxed app, this resolves to:
```
~/Library/Containers/com.andrewsoulier.mycrm/Data/Documents/MY_CRM/my_crm.db
```

## Components Using Dynamic Paths

### 1. CRMDatabase (Core/Database/CRMDatabase.swift)
**Purpose**: Central database access layer

**Method**: 
```swift
private func getDatabasePath() -> String {
    let path = SettingsManager.shared.settings.database.path
    print("📁 CRMDatabase: Using database path from SettingsManager: \(path)")
    return path
}
```

**Usage**: Called by `open()` method before opening any database connection

### 2. SQLiteDataProvider (Core/Services/SQLiteDataProvider.swift)
**Purpose**: Main data provider for the app

**Method**:
```swift
func getUserDatabasePath() -> String {
    let path = SettingsManager.shared.settings.database.path
    print("📁 Using database path from SettingsManager: \(path)")
    return path
}
```

**Usage**: Called by `MainCRMView` during app initialization:
```swift
private func connectToDatabase() async {
    let proposedPath = dataProvider.getUserDatabasePath()
    let databasePath = dataProvider.ensureValidDatabasePath(proposedPath)
    try await dataProvider.connectToDatabase(path: databasePath)
}
```

**Connection Sync**:
- `SQLiteDataProvider.connectToDatabase` now mirrors the resolved path into `GRDBDatabaseManager.shared` so GRDB-based services use the exact same file.
- When the provider closes or switches databases it also calls `GRDBDatabaseManager.shared.disconnect()`, emitting connection notifications.
- Observers (GridView, TagService, RelationshipService, etc.) listen for `.grdbDatabaseDidConnect` / `.grdbDatabaseDidDisconnect` to start or pause their streams automatically.

### 3. FirstRunSetup (Core/Services/FirstRunSetup.swift)
**Purpose**: Initialize database on first app launch

**Method**:
```swift
private static func ensureDatabase() {
    let settings = SettingsManager.shared.settings
    let dbPath = settings.database.path
    // ... create directory and file
    CRMDatabase.shared.ensureSchema()
}
```

**Usage**: Automatically called during app initialization in `StartOrchestrator`

### 4. ContactsDAO (Core/Database/ContactsDAO.swift)
**Purpose**: CRUD operations for contacts

**Database Access**: Uses `CRMDatabase.shared.open()` which automatically gets the path from SettingsManager

### 5. MessagesDAO (Core/Database/MessagesDAO.swift)
**Purpose**: CRUD operations for messages

**Database Access**: Uses `CRMDatabase.shared.open()` which automatically gets the path from SettingsManager

### 6. MessagesImporter (Core/Importers/MessagesImporter.swift)
**Purpose**: Import messages from chat.db

**Logging**: Logs the database path for debugging:
```swift
logger.info("💬 MessagesImporter.run(): starting (chatDB=\(path), crmDB=\(SettingsManager.shared.settings.database.path))")
```

**Database Access**: Uses `CRMDatabase.shared.open()` which automatically gets the path from SettingsManager

## Benefits of Dynamic Path Management

### 1. **Single Source of Truth**
- All components read from the same location (`SettingsManager`)
- No hardcoded paths or cached values
- Changes in settings immediately affect all components

### 2. **Testability**
- Easy to change database location for testing by modifying `User_Settings.json`
- No need to modify code for different database locations

### 3. **Sandboxing Compatible**
- Works correctly in both sandboxed and non-sandboxed environments
- Sandboxed apps automatically use container paths
- Non-sandboxed apps can use any accessible path

### 4. **User Control**
- Users can change database location in Settings UI
- Changes take effect on next app launch
- Path is preserved across app updates

## Path Resolution Flow

```
1. App Launch
   ↓
2. FirstRunSetup.run()
   ↓
3. ensureSettingsFile() → Creates User_Settings.json if missing
   ↓
4. ensureDatabase() → Reads path from SettingsManager
   ↓
5. CRMDatabase.shared.ensureSchema() → Uses getDatabasePath()
   ↓
6. MainCRMView.connectToDatabase()
   ↓
7. SQLiteDataProvider.getUserDatabasePath() → Returns SettingsManager path
   ↓
8. connectToDatabase(path:) → Opens SQLite database and mirrors the path into GRDBDatabaseManager
```

## Troubleshooting

### Issue: Database not found
**Solution**: Check `~/Library/Application Support/My_CRM/User_Settings.json` and verify the `database.path` value is correct

### Issue: Database in wrong location
**Solution**: 
1. Quit the app
2. Edit `User_Settings.json` and update `database.path`
3. Restart the app

### Issue: Grid View reports "database is not connected"
**Solution**:
1. Confirm the database file still exists at the path shown in the error message.
2. Re-open the database path via Settings → Database (choose the file again) or relaunch the app so `SQLiteDataProvider.connectToDatabase` can re-establish both SQLite and GRDB connections.
3. Once `.grdbDatabaseDidConnect` fires, the grid automatically reloads its data.

### Issue: Sandbox container vs actual path
**In sandboxed apps**, the database is always in:
```
~/Library/Containers/com.andrewsoulier.mycrm/Data/Documents/MY_CRM/my_crm.db
```

The `User_Settings.json` path is a relative path that gets resolved within the sandbox container.

## Best Practices

1. **Never hardcode database paths** - Always use `SettingsManager.shared.settings.database.path`
2. **Don't cache the path** - Always read fresh from SettingsManager to ensure it's current
3. **Use CRMDatabase.shared.open()** for all database access - It handles path resolution automatically
4. **Log the path** in debug builds for troubleshooting
5. **Create directory if missing** - Use `FileManager` to ensure parent directories exist

## Related Files

- `Core/Models/UserSettings.swift` - Settings model and SettingsManager
- `Core/Database/CRMDatabase.swift` - Central database access with dynamic path resolution
- `Core/Services/SQLiteDataProvider.swift` - Main data provider
- `Core/Services/FirstRunSetup.swift` - First-run initialization
- `~/Library/Application Support/My_CRM/User_Settings.json` - Runtime settings file

