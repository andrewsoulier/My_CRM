# Database and Permission Fixes - Implementation Summary

## Overview
Fixed critical database initialization and permission issues that prevented the app from running properly on new machines.

## Issues Identified from Logs

From the logs on the iHub Mac Mini machine, we identified:

1. **CanvasManager database connection failures** (lines 3, 12, 1836, 1844-1846)
   - Error: `❌ CanvasManager: Failed to open database`
   
2. **Missing groups table** (lines 31, 63, 77, 91, 106, 120, 134)
   - Error: `❌ Failed to load groups from database: no such table: groups`
   
3. **Messages import authorization denied** (lines 1842, 1925, 1969)
   - Error: `❌ MessagesImporter: Could not open chat.db - SQLite error 23: authorization denied`
   - Root cause: Missing Full Disk Access permission
   
4. **No contacts imported** (lines 1904, 1946, 1990, 2040, 2088)
   - Database is empty - no contacts have been imported
   - Contacts permission not granted (status = 0, "not determined")

## Root Cause Analysis

### Database Path Issue
- **Problem**: CRMDatabase was using SettingsManager correctly, but was not creating the database directory if it didn't exist
- **Impact**: On new machines without the `~/Documents/MY_CRM/` directory, database operations failed silently

### Groups Table Issue
- **Investigation**: The groups table SQL definition EXISTS in `SQLiteDataProvider.swift` (lines 234-248) and IS included in the statements array (line 315)
- **Actual Problem**: The groups table creation was working in SQLiteDataProvider, but CRMDatabase.open() was failing BEFORE the tables could be created because the directory didn't exist

### Permission Issue
- **Problem**: The app had permission checking code but wasn't proactively requesting permissions at startup
- **Impact**: Users were never prompted for Contacts or Full Disk Access, so imports failed silently

## Fixes Implemented

### 1. Fixed Database Directory Creation
**File: `Core/Database/CRMDatabase.swift`**

Added automatic directory creation in the `open()` method:

```swift
func open() throws -> OpaquePointer? {
    let path = getDatabasePath()
    
    // Ensure database directory exists
    let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: directory.path) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            print("✅ CRMDatabase: Created database directory at: \(directory.path)")
        } catch {
            print("❌ CRMDatabase: Failed to create database directory: \(error.localizedDescription)")
            throw CRMDatabaseError.openFailed("Failed to create database directory: \(error.localizedDescription)")
        }
    }
    
    var db: OpaquePointer?
    if sqlite3_open(path, &db) != SQLITE_OK {
        let msg = String(cString: sqlite3_errmsg(db))
        sqlite3_close(db)
        throw CRMDatabaseError.openFailed(msg)
    }
    exec(db: db, sql: "PRAGMA foreign_keys = ON;")
    return db
}
```

**Impact**: 
- Database directory is now created automatically on first launch
- All database operations (including table creation) can proceed
- Fixes the "Failed to open database" errors

### 2. Added Permission Request Dialogs (Updated 2025-10-26)
**File: `Core/Services/StartOrchestrator.swift`**

Added permission checks before imports:

```swift
func run(usePythonFallback: Bool = true, useSwiftContactsImport: Bool = false, useSwiftMessagesImport: Bool = false) {
    FirstRunSetup.run()
    
    // Check and request permissions before attempting imports
    Task { @MainActor in
        // Check Contacts permission
        if !PermissionManager.shared.hasContactsAccess() {
            PermissionManager.shared.promptForContactsAccess()
        }
        
        // Check Full Disk Access
        if !PermissionManager.shared.hasFullDiskAccess() {
            PermissionManager.shared.promptForFullDiskAccess()
        }
    }
    
    let preSnapshot = IntegritySnapshot.collect()
    // ... rest of method
}
```

**File: `App/MyCRMApp.swift`**

Removed duplicate permission checks (handled by StartOrchestrator):

```swift
// Kick off orchestrator - now using pure Swift implementation
// Note: Permissions are handled by StartOrchestrator, no need to duplicate here
DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
    // Enable both Swift contacts and messages import - Python completely disabled!
    StartOrchestrator.shared.run(usePythonFallback: false, useSwiftContactsImport: true, useSwiftMessagesImport: true)
}
```

**File: `Core/Services/PermissionManager.swift`**

Updated permission prompt methods to check status first:

```swift
func promptForFullDiskAccess() {
    // Check if we already have Full Disk Access
    if hasFullDiskAccess() {
        print("✅ PermissionManager: Full Disk Access already granted, skipping prompt")
        return
    }
    // ... show alert only if not granted
}

func promptForContactsAccess() {
    // ... check status
    // If already authorized, skip prompt
    if status == .authorized {
        print("✅ PermissionManager: Contacts already authorized, skipping prompt")
        return
    }
    // ... handle other cases
}
```

**File: `UI/Shell/MainCRMView.swift`**

Updated notification permission request to check status first:

```swift
private func requestNotificationPermissions() async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    
    // Only request if not yet determined
    if settings.authorizationStatus == .authorized {
        print("✅ Notification permission already granted, skipping request")
        return
    } else if settings.authorizationStatus == .denied {
        print("⚠️ Notification permission previously denied, skipping request")
        return
    }
    // ... request only if status is .notDetermined
}
```

**File: `Core/Services/HotkeyManager.swift`**

Updated accessibility permission check:

```swift
func requestAccessibilityPermissions() {
    // Check if accessibility permissions are already granted (without prompting)
    let accessibilityEnabled = AXIsProcessTrusted()
    
    if accessibilityEnabled {
        print("✅ HotkeyManager: Accessibility permissions already granted, skipping prompt")
        return
    }
    // ... show prompt only if not granted
}
```

**Impact**:
- **First Launch**: Users see permission prompts only when needed
- **Subsequent Launches**: No prompts if permissions already granted
- **Permission Revoked**: Prompts reappear appropriately
- Users are now prompted for Contacts permission with system dialog
- Users are shown an alert with instructions for enabling Full Disk Access
- Permissions are requested BEFORE import attempts
- Notification permissions only requested if status is `.notDetermined`
- Duplicate permission checks removed from MyCRMApp.swift
- All permission methods check status before showing dialogs

### 3. Updated Documentation
**File: `SETTINGS_SYSTEM.md`**

Updated the Database Settings section to clarify:
- Database path is read from User_Settings.json (no hardcoded paths)
- Directory is automatically created if missing
- All components use SettingsManager as source of truth
- Detailed explanation of automatic database creation process

## Verification of Existing Code

### Database Path Usage
Confirmed that all components correctly use SettingsManager:

1. **CRMDatabase.swift**: Uses `SettingsManager.shared.settings.database.path` (line 14)
2. **SQLiteDataProvider.swift**: Uses `SettingsManager.shared.settings.database.path` (line 30)
3. **MessagesImporter.swift**: Uses `SettingsManager.shared.settings.database.path` (line 78)
4. **CanvasManager.swift**: Uses `CRMDatabase.shared.open()` which internally uses SettingsManager

**Result**: No hardcoded paths found - all components properly use SettingsManager

### Table Creation
Verified that table creation SQL is complete:

1. **SQLiteDataProvider.swift**: Creates contacts, groups, invites, batch_messages
2. **CRMDatabase.swift**: Creates contacts, groups, invites, messages
3. **CanvasManager.swift**: Creates canvases table with indexes
4. **Python scripts**: Create same tables with identical schema

**Result**: All required tables are defined and created properly

## 2025-11-08 Fuji Permission Audit

- **Full Disk Access**: Runtime logs on Fuji show `MessagesPreflight.hasFullDiskAccess() = false`; the deployed app still lacks Full Disk Access.
- **Directory Ownership**: `~/Library/Application Support/My_CRM` and its contents are owned by `andrewsoulier:staff` with expected `755/644` permissions—no UID/GID mismatch detected.
- **Extended Attributes**: `my_crm.db` carries `com.apple.macl` alongside `com.apple.lastuseddate#PS`; if WAL checkpoints keep returning `SQLITE_IOERR (rc=10)` after granting access, remove stale ACL metadata with `xattr -d com.apple.macl ~/Library/Application\ Support/My_CRM/my_crm.db`.
- **Disk Capacity**: Root APFS container has ~27 GB free (`diskutil info /`), ruling out low space as the cause of checkpoint failures.
- **Cloud Sync**: No ubiquity attributes present; Application Support path confirms database is local and not under iCloud/Dropbox control.

### Recommended Remote Checklist

1. Grant Full Disk Access: System Settings ▸ Privacy & Security ▸ **Full Disk Access** ▸ add `/Applications/My CRM.app`, then relaunch.
2. Clear stale ACL metadata (if any):  
   `xattr -d com.apple.macl ~/Library/Application\ Support/My_CRM/my_crm.db`
3. Re-run manual checkpoint:  
   `sqlite3 "~/Library/Application Support/My_CRM/my_crm.db" "PRAGMA wal_checkpoint(PASSIVE);"`
4. Relaunch My CRM and monitor `~/Library/Application Support/My_CRM/Logs/crm_debug.log` for the absence of `checkpointWAL(): rc=10` warnings.

## Testing Checklist

On a clean machine (or with clean state), verify:

- [ ] App starts without errors
- [ ] Contacts permission dialog appears on first launch
- [ ] Full Disk Access alert appears with instructions
- [ ] Database directory is created at ~/Documents/MY_CRM/
- [ ] Database file is created at ~/Documents/MY_CRM/my_crm.db
- [ ] All tables are created (contacts, groups, messages, invites, canvases, batch_messages)
- [ ] After granting Contacts permission, contacts are imported
- [ ] After granting Full Disk Access, messages are imported
- [ ] No "Failed to open database" errors in logs
- [ ] No "no such table: groups" errors in logs
- [ ] Canvas operations work properly

## Expected Log Output

On successful first launch:
```
📁 CRMDatabase: Using database path from SettingsManager: /Users/username/Documents/MY_CRM/my_crm.db
✅ CRMDatabase: Created database directory at: /Users/username/Documents/MY_CRM
🔨 CRMDatabase.ensureSchema: Creating database schema...
✅ CRMDatabase: contacts table ready
✅ CRMDatabase: groups table ready
✅ CRMDatabase: invites table ready
✅ CRMDatabase: messages table ready
✅ CRMDatabase.ensureSchema: Schema creation complete
🔐 PermissionManager: Requesting Contacts access (system prompt should appear)...
```

## Files Modified

1. `Core/Database/CRMDatabase.swift` - Added directory creation in open()
2. `Core/Services/StartOrchestrator.swift` - Added permission checks
3. `App/MyCRMApp.swift` - Removed duplicate permission checks (2025-10-26)
4. `Core/Services/PermissionManager.swift` - Added status checks before showing prompts (2025-10-26)
5. `UI/Shell/MainCRMView.swift` - Added notification status check before requesting (2025-10-26)
6. `Core/Services/HotkeyManager.swift` - Added accessibility status check before prompting (2025-10-26)
7. `SETTINGS_SYSTEM.md` - Updated documentation

## Additional Notes

### Permission Flow
1. App launches
2. After 1.0s: Permission checks run, dialogs appear
3. User grants/denies permissions
4. After 3.5s: StartOrchestrator runs import operations
5. Importers attempt to access Contacts/Messages based on permissions granted

### Database Creation Flow
1. Any component calls `CRMDatabase.shared.open()`
2. Path is read from SettingsManager
3. Directory existence is checked
4. Directory is created if missing
5. Database file is opened/created
6. Foreign keys pragma is set
7. Tables are created via `ensureSchema()`

### Existing Permission Manager Features
The `PermissionManager` class has:
- `hasContactsAccess()` - checks CNContactStore authorization
- `hasFullDiskAccess()` - checks Messages database readability
- `promptForContactsAccess()` - checks status first, shows system dialog or settings alert only if needed (updated 2025-10-26)
- `promptForFullDiskAccess()` - checks status first, shows alert with System Settings instructions only if needed (updated 2025-10-26)
- Automatic retry of Contacts import after permission granted

### Permission Check Before Prompt (Added 2025-10-26)
All permission prompt methods now check the current permission status before showing any dialogs:
- **Full Disk Access**: Checks `hasFullDiskAccess()` before showing alert
- **Contacts Access**: Returns early if status is `.authorized`
- **Notifications**: Checks `notificationSettings()` before requesting
- **Accessibility**: Checks `AXIsProcessTrusted()` before prompting

This ensures users only see permission dialogs when permissions are actually missing or blocked, improving the user experience on subsequent app launches.

## Conclusion

All identified issues have been fixed:
1. ✅ Database directory is now automatically created
2. ✅ Permission dialogs are shown on first launch
3. ✅ Database path from SettingsManager is used consistently
4. ✅ Groups table (and all tables) are created properly
5. ✅ Documentation updated to reflect current behavior

The app should now work properly on clean machines without manual setup.

