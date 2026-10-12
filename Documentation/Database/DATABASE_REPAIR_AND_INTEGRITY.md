# Database Repair and Integrity System

## Overview

This document describes the database repair and integrity checking system implemented to fix critical issues discovered on remote deployments where databases were missing tables or experiencing corruption.

## Issues Fixed

### 1. Missing Groups Table
**Problem**: Remote machines had databases missing the `groups` table, causing:
- Error: "no such table: groups"
- Group creation failures with "disk I/O error"
- Data loss (contacts dropping from 3870 to 0)

**Root Cause**: Migration code assumed groups table existed and only tried to ALTER it, never CREATE it.

**Fix**: Modified `runGroupsParticipantsMigration()` in `SQLiteDataProvider.swift` to:
1. First execute `CREATE TABLE IF NOT EXISTS groups` before checking columns
2. Then check for missing columns and add them if needed
3. Comprehensive error logging with recovery hints

### 2. Database Corruption from Failed Operations
**Problem**: Failed INSERT operations corrupted the database and wiped all data.

**Fix**: Added transaction wrapping in `saveGroupToDatabaseAndGetId()`:
- `BEGIN TRANSACTION` before INSERT
- `COMMIT` on success
- `ROLLBACK` on error (prevents corruption)
- Enhanced error logging with database path

### 3. Duplicate Contact Nodes on Canvas
**Problem**: Same contact appearing twice with different UUIDs when drag-dropped.

**Fix**: Added duplicate detection in `addContactFromDrop()`:
- Check if contact with same phone number already exists
- If exists, move existing contact instead of creating duplicate
- Use phone number as deduplication key (database-level ID)

### 4. Quick Send Empty Contact List
**Problem**: Contact list dropdown empty after database corruption.

**Fix**: Prevented by fixing issues #1 and #2 above - contacts no longer lost.

## New Components

### DatabaseRepairService
**File**: `Core/Services/DatabaseRepairService.swift`

A utility service for detecting and repairing database issues:

```swift
// Check if repair needed
let repairService = DatabaseRepairService()
if repairService.needsRepair(database: db) {
    await repairService.repairDatabase(database: db, databasePath: path)
}
```

**Features**:
- Detects missing tables
- Creates automatic backups before repair
- Recreates tables with correct schema
- Validates integrity with PRAGMA integrity_check

### Integrity Checking Methods
**File**: `Core/Services/SQLiteDataProvider.swift`

Two new methods added:

1. **`checkDatabaseIntegrity()`**
   - Runs `PRAGMA integrity_check`
   - Returns true if database is healthy
   - Logs detailed errors if corrupted

2. **`checkRequiredTablesExist()`**
   - Validates all required tables exist
   - Returns array of missing table names
   - Required tables: contacts, groups, canvases, batch_messages, messages

### Startup Health Check
**File**: `Core/Services/SQLiteDataProvider.swift` - `connect()` method

On every database connection:
1. Connect to database
2. Run integrity check
3. Check for missing tables
4. Log warnings if issues found
5. Run migrations (which now create missing tables)
6. Load data

## Database Paths

### Local Machine (Works)
- Path: `/Users/andrewsoulier/My_CRM Project/my_crm_2.db`
- Groups table: EXISTS
- Contacts: Persist correctly

### Remote Machine (Fixed)
- Path: `/Users/andrewsoulier/Documents/MY_CRM/my_crm.db`
- Groups table: NOW CREATED by migration
- Contacts: Protected by transactions
- Duplicates: Prevented by deduplication

## Migration Flow

### Before Fix
1. Connect to database
2. Run migrations
3. Migration 1: Try to ALTER groups table
4. **FAIL** - Table doesn't exist
5. Continue loading (with broken state)
6. Group creation fails with "disk I/O error"

### After Fix
1. Connect to database
2. Check integrity (new)
3. Check required tables (new)
4. Run migrations
5. Migration 1: CREATE TABLE IF NOT EXISTS groups (new)
6. Migration 1: Check for missing columns
7. Migration 1: ALTER TABLE to add missing columns
8. Load data successfully

## Transaction Safety

All group save operations now wrapped in transactions:

```swift
BEGIN TRANSACTION
    INSERT INTO groups (...)
    [if success]
        COMMIT
    [if error]
        ROLLBACK  // Prevents corruption
```

Benefits:
- Atomic operations
- No partial writes
- Database remains consistent on errors
- Contact data preserved even if group save fails

## Testing

### To Simulate Remote State Locally
1. Delete groups table: `sqlite3 my_crm_2.db "DROP TABLE IF EXISTS groups;"`
2. Launch app
3. Check logs: Should see "Migration 1: Groups table ensured"
4. Create group - should work without errors
5. Contacts should remain loaded

### To Verify Duplicate Prevention
1. Drag contact to canvas
2. Drag same contact again
3. Check logs: Should see "Contact already exists on canvas"
4. Verify only one node displayed
5. Second drop should move existing node

## Error Recovery

### If Database Corrupted
1. App detects corruption on startup
2. Logs: "Database integrity check failed"
3. Creates backup with timestamp
4. Migrations recreate missing tables
5. Data preserved where possible

### If Disk I/O Error
1. Transaction begins
2. INSERT fails
3. Error logged with full details
4. Transaction ROLLED BACK
5. Database remains in consistent state
6. User can retry operation

## Monitoring

Check these logs on remote machines:
- `✅ Migration 1: Groups table ensured` - Table creation successful
- `✅ Transaction committed successfully` - Group saved correctly
- `⚠️ Contact already exists on canvas` - Duplicate prevented
- `✅ Database integrity check passed` - No corruption

## Related Files

- `Core/Services/SQLiteDataProvider.swift` - Main database provider
- `Core/Services/DatabaseRepairService.swift` - Repair utility
- `UI/Pages/PeopleMaps/GroupsMapViewModel.swift` - Canvas operations
- `database_requirements.json` - Schema specifications
- `DATABASE_FIRST_IMPLEMENTATION_GUIDE.md` - Database architecture

## Future Improvements

1. Automatic repair on detected corruption
2. Periodic integrity checks
3. Database vacuum on startup
4. Transaction support for all write operations
5. Better error messages to users

