# My CRM Cleanup Guide

This guide explains how My CRM manages background processes and provides instructions for proper cleanup when closing or uninstalling the app.

## Overview

My CRM uses several system-level components that can persist after the app window closes:

1. **LaunchAgents** - Scheduled message delivery and background tasks
2. **File System Monitors** - Watch for trigger files to process scheduled messages
3. **Database Connections** - SQLite connections with Write-Ahead Logging (WAL)
4. **Background Processes** - Shell scripts and Python processes (if enabled)

## Automatic Cleanup

Starting with this version, My CRM includes **automatic cleanup** that runs when you quit the app:

### What Gets Cleaned Up Automatically

When you quit My CRM (⌘Q or "Quit" from menu), the app will:

1. ✅ Stop all running timers
2. ✅ Unload all LaunchAgents created by the app
3. ✅ Close file system monitors
4. ✅ Terminate background processes
5. ✅ Checkpoint and close database connections

### How It Works

The cleanup is handled by `AppCleanupService` which is triggered by the app's termination handler. The process:

- Detects when the app is quitting
- Runs cleanup synchronously (waits up to 10 seconds)
- Logs all cleanup actions to the console and log files
- Ensures all resources are released before app terminates

## Background Components Explained

### LaunchAgents

LaunchAgents are macOS system services that run independently of the main app. My CRM creates them for:

**Scheduled Messages** (`com.mycrm.quicksend.*`)
- Created when you schedule a message for future delivery
- One LaunchAgent per scheduled message
- Automatically removed when message is sent or cancelled

**Cron Update Service** (`com.mycrm.cronupdate`)
- Runs periodic background tasks (every 90 seconds)
- Located in: `~/Library/LaunchAgents/com.mycrm.cronupdate.plist`

**Launch Service** (`com.andrewsoulier.crmlaunch`)
- Auto-starts backend components (if configured)
- Located in: `~/Library/LaunchAgents/com.andrewsoulier.crmlaunch.plist`

### File System Monitors

My CRM monitors these directories:

- **Trigger Directory**: `~/Library/Application Support/My_CRM/Triggers/`
  - Used for scheduled message triggers
  - Cleaned up automatically on app quit

### Database Files

The app maintains an SQLite database with WAL (Write-Ahead Logging):

- **Main Database**: `~/Documents/MY_CRM/my_crm.db` (or custom location)
- **WAL File**: `my_crm.db-wal` (transaction log)
- **SHM File**: `my_crm.db-shm` (shared memory)

On quit, the app runs `PRAGMA wal_checkpoint(TRUNCATE)` to ensure all data is written to the main database file.

## Manual Cleanup

If automatic cleanup fails or you need to manually clean up:

### Using the Cleanup Script

Run the included cleanup script before deleting the app:

```bash
cd "/Users/andrewsoulier/My_CRM Project/MY CRM"
./cleanup_mycrm.sh
```

**Optional**: Provide the app bundle path to check for open files:

```bash
./cleanup_mycrm.sh "/Applications/My CRM.app"
```

### Manual Cleanup Steps

If you prefer to clean up manually:

#### 1. Unload LaunchAgents

```bash
# List all My CRM LaunchAgents
launchctl list | grep mycrm

# Unload each one (example)
launchctl unload -w ~/Library/LaunchAgents/com.mycrm.cronupdate.plist
launchctl unload -w ~/Library/LaunchAgents/com.andrewsoulier.crmlaunch.plist

# Find and remove all scheduled message LaunchAgents
cd ~/Library/LaunchAgents
for plist in com.mycrm.quicksend.*.plist; do
    [ -f "$plist" ] && launchctl unload -w "$plist" && rm "$plist"
done
```

#### 2. Remove LaunchAgent Plist Files

```bash
rm ~/Library/LaunchAgents/com.mycrm.*.plist
rm ~/Library/LaunchAgents/com.andrewsoulier.crmlaunch.plist
```

#### 3. Kill Running Processes

```bash
# Find My CRM processes
ps aux | grep -i "my crm"

# Kill processes (replace PID with actual process ID)
kill -15 <PID>

# Force kill if needed
kill -9 <PID>
```

#### 4. Clean Temporary Files

```bash
# Remove trigger files
rm -rf ~/Library/Application\ Support/My_CRM/Triggers/*.trigger

# Remove temp logs
rm /tmp/mycrm_quicksend_*.{out,err}
rm /tmp/crm_*.log
```

## Troubleshooting "In Use" Errors

If you get an error that the app is "in use" when trying to delete it:

### Check for Open Files

```bash
# Check what's holding the app open
lsof /Applications/My\ CRM.app
```

### Common Causes

1. **LaunchAgents Still Running**
   - Run: `launchctl list | grep mycrm`
   - Unload any found agents

2. **Python Processes**
   - Run: `ps aux | grep python.*crm`
   - Kill any found processes

3. **Open Database Connections**
   - Run: `lsof | grep my_crm.db`
   - Close any apps accessing the database

4. **Shell Scripts Still Running**
   - Run: `ps aux | grep Launch_Server`
   - Kill any found processes

### Force Cleanup Command

If all else fails, this one-liner will force clean everything:

```bash
launchctl list | grep mycrm | awk '{print $3}' | xargs -I {} launchctl unload -w ~/Library/LaunchAgents/{}.plist 2>/dev/null; \
pkill -f "my crm"; \
rm ~/Library/LaunchAgents/com.mycrm.*.plist 2>/dev/null; \
rm ~/Library/LaunchAgents/com.andrewsoulier.crmlaunch.plist 2>/dev/null; \
echo "Cleanup complete"
```

## Verification

After cleanup, verify nothing is left running:

```bash
# Check LaunchAgents
launchctl list | grep mycrm
# Should return nothing

# Check processes
ps aux | grep -i "my crm" | grep -v grep
# Should return nothing

# Check open files on app bundle
lsof /Applications/My\ CRM.app
# Should return nothing

echo "✅ Clean - app can be safely deleted"
```

## Safe Deletion Process

1. **Quit the app** normally (⌘Q or "Quit" from menu)
   - Wait 5 seconds for automatic cleanup

2. **Verify cleanup** (optional):
   ```bash
   launchctl list | grep mycrm
   ```

3. **Run cleanup script** (if needed):
   ```bash
   ./cleanup_mycrm.sh "/Applications/My CRM.app"
   ```

4. **Delete the app bundle**:
   ```bash
   rm -rf /Applications/My\ CRM.app
   ```

5. **Remove user data** (optional):
   ```bash
   rm -rf ~/Library/Application\ Support/My_CRM
   rm -rf ~/Documents/MY_CRM
   ```

## Logs

Cleanup actions are logged to:

- **Console Output**: Visible when running from terminal
- **App Logs**: `~/Library/Application Support/My_CRM/Logs/`
- **System Log**: Check with `log show --predicate 'process == "My CRM"' --last 5m`

## Support

If you encounter issues with cleanup:

1. Check the logs for error messages
2. Run the cleanup script with verbose output
3. Manually verify and remove components using the steps above
4. Use Activity Monitor to identify any remaining processes

## Technical Details

### AppCleanupService

The main cleanup coordinator that orchestrates all cleanup operations:

**Location**: `Core/Services/AppCleanupService.swift`

**Methods**:
- `performCompleteCleanup()` - Main cleanup entry point
- `unloadAllLaunchAgents()` - Removes all LaunchAgents
- `stopFileSystemMonitors()` - Closes file descriptors
- `closeDatabaseConnections()` - Checkpoints and closes SQLite

### SchedulingService Shutdown

Properly closes file system monitors:

**Location**: `Core/Services/SchedulingService.swift`

**Method**: `shutdown()` - Cancels dispatch sources and closes file descriptors

### Database Cleanup

Ensures all data is persisted before closing:

**Location**: `Core/Services/SQLiteDataProvider.swift`

**Method**: `closeDatabase()` - Checkpoints WAL and closes connection

### Application Delegate

Hooks into app termination:

**Location**: `App/MyCRMApp.swift`

**Method**: `applicationWillTerminate()` - Triggers cleanup service

## Summary

✅ **Automatic cleanup** runs when you quit the app normally

✅ **Manual cleanup script** available for troubleshooting: `cleanup_mycrm.sh`

✅ **All LaunchAgents** are unloaded and removed

✅ **All processes** are terminated

✅ **All database connections** are properly closed

✅ **All file descriptors** are released

The app can now be safely deleted after closing without "in use" errors! 🎉

