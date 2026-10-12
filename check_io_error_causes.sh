#!/bin/bash

echo "=== SQLite Disk I/O Error Diagnosis ==="
echo ""
echo "Checking on: $(hostname)"
echo "Date: $(date)"
echo ""

DB_PATH="/Users/andrewsoulier/Documents/MY_CRM/my_crm.db"
DB_DIR="/Users/andrewsoulier/Documents/MY_CRM"

# 1. Cloud Sync Detection
echo "1. ☁️  CLOUD SYNC CHECK:"
if ls -la@ "$HOME/Documents" 2>/dev/null | grep -q "com.apple.metadata"; then
    echo "   ⚠️  FOUND: Documents folder has iCloud metadata"
    echo "   💡 This is likely causing I/O errors due to sync conflicts!"
fi
if [ -d "$HOME/Library/Mobile Documents" ]; then
    echo "   ℹ️  iCloud Drive is active on this machine"
fi
if [ -d "$HOME/Library/CloudStorage/GoogleDrive"* ]; then
    echo "   ℹ️  Google Drive is active on this machine"
    echo "   ⚠️  If Documents is synced, this causes SQLite write conflicts"
fi
echo ""

# 2. Permissions
echo "2. 🔒 PERMISSIONS CHECK:"
if [ -d "$DB_DIR" ]; then
    ls -la "$DB_DIR"
    echo ""
    echo "   Directory owner: $(stat -f '%Su' "$DB_DIR")"
    echo "   Directory permissions: $(stat -f '%Sp' "$DB_DIR")"
    if [ -f "$DB_PATH" ]; then
        echo "   Database file permissions: $(stat -f '%Sp' "$DB_PATH")"
        echo "   Database file owner: $(stat -f '%Su' "$DB_PATH")"
    fi
else
    echo "   ℹ️  Directory doesn't exist yet: $DB_DIR"
fi
echo ""

# 3. Disk Space
echo "3. 💾 DISK SPACE CHECK:"
df -h "$HOME/Documents" | tail -1
AVAILABLE=$(df "$HOME/Documents" | tail -1 | awk '{print $4}')
if [ "$AVAILABLE" -lt 1000000 ]; then
    echo "   ⚠️  LOW DISK SPACE! Less than 1GB available"
fi
echo ""

# 4. Temp Directory
echo "4. 🗂️  TEMP DIRECTORY CHECK:"
TMPDIR="${TMPDIR:-/tmp}"
echo "   TMPDIR: $TMPDIR"
if [ -w "$TMPDIR" ]; then
    echo "   ✅ Temp directory is writable"
else
    echo "   ❌ Temp directory NOT writable (SQLite needs this for journal files)"
fi
echo ""

# 5. File Locks
echo "5. 🔐 FILE LOCK CHECK:"
if [ -f "$DB_PATH" ]; then
    LOCKS=$(lsof "$DB_PATH" 2>/dev/null)
    if [ -n "$LOCKS" ]; then
        echo "   ⚠️  Database file is LOCKED by:"
        echo "$LOCKS"
    else
        echo "   ✅ No file locks detected"
    fi
    
    # Check for journal/wal files
    if [ -f "${DB_PATH}-journal" ]; then
        echo "   ⚠️  Found rollback journal: ${DB_PATH}-journal"
        echo "   💡 Previous crash may have left incomplete transaction"
    fi
    if [ -f "${DB_PATH}-wal" ]; then
        echo "   ℹ️  Found WAL file: ${DB_PATH}-wal"
    fi
else
    echo "   ℹ️  Database file doesn't exist yet"
fi
echo ""

# 6. Write Test
echo "6. ✍️  WRITE PERMISSION TEST:"
TEST_FILE="$DB_DIR/.write_test_$(date +%s)"
if mkdir -p "$DB_DIR" 2>/dev/null; then
    if echo "test" > "$TEST_FILE" 2>/dev/null; then
        echo "   ✅ Can write to database directory"
        rm -f "$TEST_FILE"
    else
        echo "   ❌ CANNOT write to database directory!"
        echo "   Error: $(echo "test" > "$TEST_FILE" 2>&1)"
    fi
else
    echo "   ❌ CANNOT create database directory!"
fi
echo ""

# 7. macOS TCC (Privacy) Check
echo "7. 🔐 macOS PRIVACY/TCC CHECK:"
BUNDLE_ID="com.ihub.my-crm"
echo "   App Bundle ID: $BUNDLE_ID"
echo "   Full Disk Access status:"
if [ -f "$HOME/Library/Messages/chat.db" ]; then
    if sqlite3 "$HOME/Library/Messages/chat.db" "SELECT 1 LIMIT 1" 2>/dev/null >/dev/null; then
        echo "   ✅ Has Full Disk Access (can read Messages)"
    else
        echo "   ⚠️  No Full Disk Access or Messages permission denied"
    fi
fi
echo ""

# 8. Filesystem Type
echo "8. 💿 FILESYSTEM TYPE:"
df -T "$HOME/Documents" 2>/dev/null || diskutil info "$(df "$HOME/Documents" | tail -1 | awk '{print $1}')" | grep "File System"
echo ""

# 9. SQLite Version
echo "9. 📚 SQLITE VERSION:"
sqlite3 -version
echo ""

# 10. Open Files Limit
echo "10. 📊 OPEN FILES LIMIT:"
ulimit -n
MAX_FILES=$(ulimit -n)
CURRENT_OPEN=$(lsof -p $$ 2>/dev/null | wc -l)
echo "   Current process has $CURRENT_OPEN files open (limit: $MAX_FILES)"
echo ""

echo "=== RECOMMENDATIONS ==="
echo ""
echo "Common SQLite I/O Error Causes:"
echo "  1. ☁️  Cloud sync (iCloud, Google Drive, Dropbox) - MOVE database OUT of synced folders"
echo "  2. 🔒 File permissions - Ensure app has write access"
echo "  3. 💾 Low disk space - Free up space on device"
echo "  4. 🔐 macOS TCC restrictions - Grant Full Disk Access in System Settings"
echo "  5. 📁 Readonly filesystem - Check mount options"
echo ""
echo "Best Practice Database Locations:"
echo "  ✅ ~/Library/Application Support/My_CRM/my_crm.db (recommended)"
echo "  ✅ ~/CRM/my_crm.db (simple, not synced)"
echo "  ❌ ~/Documents/* (often cloud-synced, causes conflicts)"
echo "  ❌ ~/Desktop/* (same as Documents)"
echo ""

