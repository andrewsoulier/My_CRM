# Database I/O Error Fixes - Implementation Summary

## Date: October 26, 2025

## Problem Statement

The remote machine (iHub Mac Mini) experienced persistent "disk I/O error" and "authorization denied" errors when attempting to write to the database, preventing:
- Group creation
- Contact list display in Quick Send
- Proper database operations

The local machine did not experience these issues, indicating environmental/configuration differences rather than code bugs.

## Root Causes Identified

1. **Basic SQLite Connection** - Using `sqlite3_open()` without explicit flags
2. **No WAL Mode** - Default rollback journal is less resilient to crashes and concurrent access
3. **No Permission Detection** - App couldn't detect when macOS blocked writes
4. **Cloud Sync Conflicts** - Database in Documents folder (often synced to cloud services)
5. **Multiple Instances** - Old and new builds running simultaneously causing file locks
6. **Limited Error Context** - Generic I/O errors without actionable diagnostics

## Solutions Implemented

### 1. Upgraded SQLite Connection (SQLiteDataProvider.swift)

**Changed:** Lines 105-111, 208-213

**What:** Replaced `sqlite3_open()` with `sqlite3_open_v2()` using explicit flags:
```swift
let result = sqlite3_open_v2(
    path,
    &database,
    SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
    nil
)
```

**Why:** 
- `SQLITE_OPEN_READWRITE` - Explicitly request read-write access
- `SQLITE_OPEN_CREATE` - Create database if it doesn't exist
- `SQLITE_OPEN_FULLMUTEX` - Thread-safe for concurrent access
- Better error reporting when permissions are denied

### 2. Enabled WAL Mode (SQLiteDataProvider.swift)

**Changed:** Lines 131-143

**What:** Added PRAGMA settings after successful connection:
```swift
sqlite3_exec(database, "PRAGMA journal_mode=WAL;", nil, nil, &walError)
sqlite3_exec(database, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
```

**Why:**
- **Write-Ahead Logging (WAL)** allows concurrent reads during writes
- More resilient to crashes - doesn't corrupt on power loss
- Better performance for write-heavy operations
- Industry standard for production SQLite databases
- Reduces likelihood of SQLITE_BUSY errors

### 3. Created Permission Detection Service

**New File:** `Core/Services/DatabasePermissionChecker.swift`

**Features:**
- `checkDatabaseWritePermission()` - Tests actual write access by creating temp file
- `isPathCloudSynced()` - Detects if database is in cloud-synced folder
- `showPermissionAlert()` - Shows user-friendly alert with instructions
- `getDiagnosticInfo()` - Comprehensive diagnostics for I/O errors
- `showCloudSyncWarning()` - Logs warning about cloud-synced locations

**Cloud Sync Detection:**
- Google Drive paths
- Dropbox paths
- OneDrive paths
- iCloud Drive paths
- Documents folder (often synced)
- Desktop folder (often synced)

### 4. Created Multiple Instance Manager

**New File:** `Core/Services/AppInstanceManager.swift`

**Features:**
- `checkForOtherInstances()` - Finds other My CRM processes using NSRunningApplication
- `showMultiInstanceAlert()` - Alerts user with option to quit other instances
- `quitOtherInstances()` - Gracefully terminates other instances
- `checkAndHandleMultipleInstances()` - Complete check-and-handle workflow

**Benefits:**
- Prevents file lock conflicts
- Avoids database corruption from concurrent writes
- User can choose to quit old instances automatically

### 5. Integrated Checks into Connection Flow (SQLiteDataProvider.swift)

**Changed:** Lines 91-96, 148-160

**Instance Check (lines 91-96):**
```swift
// Check for multiple app instances before connecting
let canProceed = await AppInstanceManager.shared.checkAndHandleMultipleInstances()
if !canProceed {
    logger.error("❌ User cancelled connection due to multiple instances")
    throw DataProviderError.databaseConnectionFailed
}
```

**Permission Check (lines 148-154):**
```swift
// Check write permissions
let permissionStatus = DatabasePermissionChecker.shared.checkDatabaseWritePermission(path: path)
if permissionStatus == .denied {
    logger.error("❌ Database write permission denied")
    await DatabasePermissionChecker.shared.showPermissionAlert(status: .denied)
    throw DataProviderError.databaseConnectionFailed
}
```

**Cloud Sync Warning (lines 156-160):**
```swift
// Check for cloud sync (warn but continue per user preference)
let (isSynced, service) = DatabasePermissionChecker.shared.isPathCloudSynced(path)
if isSynced {
    DatabasePermissionChecker.shared.showCloudSyncWarning(service: service ?? "unknown", path: path)
}
```

### 6. Enhanced I/O Error Diagnostics (SQLiteDataProvider.swift)

**Changed:** Lines 1668-1700

**What:** When group creation fails, now provides:
- Specific SQLite error code
- Detailed diagnostics for I/O errors
- Permission status
- Cloud sync detection
- Disk space check
- Temp directory writability
- File lock detection
- Actionable recommendations

**Example Output:**
```
❌ Failed to insert group: disk I/O error (Error code: 10)
💡 Database path: /Users/.../Documents/MY_CRM/my_crm.db
❌ Disk I/O Error Detected - Running diagnostics...
📊 Diagnostic Results:
   ✅ Write permission OK
   ⚠️ Database in cloud-synced location (Google Drive)
   ✅ Disk space OK: 45.23 GB free
   ✅ Temp directory writable
💡 Common causes of I/O errors:
   1. Database in cloud-synced folder (iCloud, Google Drive, Dropbox)
   2. Missing Full Disk Access permission
   3. Disk full or filesystem read-only
   4. Another app instance has database locked
   5. Antivirus/backup software interfering with database
💡 Recommended: Move database to ~/Library/Application Support/My_CRM/
```

## Additional Diagnostics (Nov 8, 2025)

- **Checkpoint Logging Upgrade** (`SQLiteDataProvider.checkpointWAL()`):
  - Now logs SQLite return code (`rc`) and error message when a WAL checkpoint fails.
  - Frees any error pointers and falls back to `sqlite3_errmsg` if the callback returns `nil`.
  - Example: `⚠️ WAL checkpoint warning (rc=10): disk I/O error`.
- **Planned Enhancements**:
  1. Capture `sqlite3_extended_errcode(db)` to differentiate `SQLITE_IOERR_*` subcodes (e.g., `BLOCKED`, `CHECKPOINT`, `READ`).
  2. Record `errno` using `perror` or `String(cString: strerror(errno))` immediately after failure for OS-level diagnostics.
  3. Attach checkpoint context (database path, WAL size, consumer module) via `logger.withMetadata`.
  4. Implement exponential backoff + retry (e.g., 3 attempts over 5 seconds) before escalating to warning.
  5. When retries fail, run `DatabasePermissionChecker.shared.getDiagnosticInfo()` and include results in the warning payload.
  6. Surface a UI alert banner if `rc=10` persists for >5 minutes to prompt the user to check Full Disk Access / cloud sync.

## Verification Plan (After Fix Deployment)

1. **Environment Prep**
   - Confirm `/Applications/My CRM.app` has Full Disk Access on the target Mac.
   - remove legacy attributes if needed: `xattr -d com.apple.macl ~/Library/Application\ Support/My_CRM/my_crm.db`.

2. **Manual Checkpoints**
   - Run `sqlite3 "~/Library/Application Support/My_CRM/my_crm.db" "PRAGMA wal_checkpoint(PASSIVE);"` and ensure result is `0|pages|checkpointed`.
   - Verify `my_crm.db-wal` shrinks to 0 bytes and stays unlocked.

3. **App Launch Monitoring**
   - Launch My CRM and tail `crm_debug.log` for 10 minutes.
   - Expect no `checkpointWAL(): rc=10` warnings; the periodic job should log success or remain silent.

4. **Functional Regression**
   - Create/edit/delete a group via UI (exercises `GroupManager`).
   - Create/update a canvas (exercises `CanvasManager`).
   - Trigger Contacts import and Quick Send preview—confirm no retry errors.

5. **Resilience Tests**
   - Toggle network drives / cloud sync off/on to ensure the Permission Checker emits warnings instead of I/O errors.
   - Quit and relaunch the app twice in quick succession to confirm no lingering locks remain.

6. **Post-Test Snapshot**
   - Capture `sqlite3 "SELECT count(*) FROM groups;"` for sanity.
   - Archive the final `crm_debug.log` segment in `Logs/` for audit.

## User Experience Flow

### On First Launch:
1. **Multiple Instance Check** - If other instances detected, shows alert with option to quit them
2. **Database Connection** - Attempts to connect with improved flags
3. **WAL Mode Enabled** - Configures database for better concurrency
4. **Permission Verification** - Tests actual write access
5. **Cloud Sync Warning** - Logs warning if database in synced folder (doesn't block)

### On Permission Denied:
1. Shows alert: "Database Permission Required"
2. Explains the issue (Full Disk Access needed)
3. Offers button to open System Settings
4. Throws error to prevent data corruption

### On I/O Error During Operations:
1. Captures specific SQLite error code
2. Runs comprehensive diagnostics
3. Logs detailed analysis
4. Provides actionable recommendations
5. Rolls back transaction to prevent corruption

## Configuration Choices (Per User Preferences)

1. **Cloud Sync Detection** - Log warning but continue (option 1c)
2. **Permission Denied** - Show alert with System Settings link (option 2a)
3. **WAL Mode** - Enabled by default (option 3a)
4. **Multiple Instances** - Detect and offer to quit other instances (option 4a)

## Testing Checklist

- [ ] Test with database in Documents folder (cloud-synced)
- [ ] Test without Full Disk Access permission
- [ ] Launch two instances simultaneously
- [ ] Verify WAL mode creates .db-wal and .db-shm files
- [ ] Test group creation with all scenarios
- [ ] Deploy to remote machine (iHub Mac Mini)
- [ ] Verify no more I/O errors on remote
- [ ] Verify Quick Send shows contacts
- [ ] Verify groups can be created on remote

## Expected Outcomes

### Local Machine:
- No change in behavior (already working)
- WAL mode may improve performance slightly
- Multiple instance detection prevents accidental conflicts

### Remote Machine (iHub Mac Mini):
- **Group creation should work** - I/O errors diagnosed and prevented
- **Quick Send should show contacts** - Database operations stable
- **Cloud sync warning logged** - User informed if database in risky location
- **Better error messages** - If issues persist, clear diagnostics provided

## Recommended Database Location

For best reliability, move database to:
```
~/Library/Application Support/My_CRM/my_crm.db
```

This location:
- ✅ Not cloud-synced by default
- ✅ Standard macOS app data location
- ✅ Protected by user permissions
- ✅ Survives app updates
- ✅ Backed up by Time Machine

## Files Modified

1. **Core/Services/SQLiteDataProvider.swift** - Connection upgrades, WAL mode, checks integration, enhanced diagnostics
2. **Core/Services/DatabasePermissionChecker.swift** - NEW - Permission and cloud sync detection
3. **Core/Services/AppInstanceManager.swift** - NEW - Multiple instance management

## Technical Notes

- **WAL Mode Files**: Creates `.db-wal` and `.db-shm` files alongside main database
- **Thread Safety**: FULLMUTEX flag ensures safe concurrent access
- **Error Codes**: SQLITE_IOERR (10), SQLITE_CANTOPEN (14), SQLITE_READONLY (8)
- **Transaction Safety**: Existing rollback logic preserved with enhanced diagnostics

## Next Steps

1. Build and test locally
2. Deploy to remote machine
3. Monitor logs for I/O error diagnostics
4. If issues persist, use diagnostic output to identify specific cause
5. Consider offering in-app database relocation tool if cloud sync detected

## Success Metrics

- ✅ No "disk I/O error" in logs
- ✅ No "authorization denied" in logs
- ✅ Groups can be created successfully
- ✅ Quick Send displays contact list
- ✅ WAL mode enabled (check for .db-wal file)
- ✅ Diagnostic logs provide clear guidance if issues occur


