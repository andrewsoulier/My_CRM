#!/bin/bash

echo "=== Remote Database Diagnostics ==="
echo ""

DB_PATH="/Users/andrewsoulier/Documents/MY_CRM/my_crm.db"
DB_DIR="/Users/andrewsoulier/Documents/MY_CRM"

echo "1. Disk Space:"
df -h "$HOME/Documents"
echo ""

echo "2. Database Directory Permissions:"
ls -la "$DB_DIR" 2>/dev/null || echo "Directory does not exist"
echo ""

echo "3. Database File Permissions:"
ls -la "$DB_PATH" 2>/dev/null || echo "File does not exist"
echo ""

echo "4. Check if Documents is synced to cloud:"
if [ -f "$HOME/Documents/.DS_Store" ]; then
    xattr -l "$HOME/Documents" | grep "com.apple.metadata" && echo "📦 Documents folder may be synced to iCloud"
fi
echo ""

echo "5. Test write permissions:"
TEST_FILE="$DB_DIR/write_test_$(date +%s).txt"
if mkdir -p "$DB_DIR" 2>/dev/null && echo "test" > "$TEST_FILE" 2>/dev/null; then
    echo "✅ Can write to database directory"
    rm -f "$TEST_FILE"
else
    echo "❌ CANNOT write to database directory!"
    echo "   Error: $(echo "test" > "$TEST_FILE" 2>&1)"
fi
echo ""

echo "6. Check for file locks:"
lsof "$DB_PATH" 2>/dev/null || echo "No processes have database file open"
echo ""

echo "7. SQLite integrity check (if database exists):"
if [ -f "$DB_PATH" ]; then
    sqlite3 "$DB_PATH" "PRAGMA integrity_check;" 2>&1
else
    echo "Database file does not exist yet"
fi
echo ""

echo "8. Check Application Support path (alternative location):"
APP_SUPPORT="$HOME/Library/Application Support/My_CRM"
ls -la "$APP_SUPPORT" 2>/dev/null || echo "Application Support directory does not exist"
echo ""

echo "=== Recommendations ==="
echo "If Documents folder is synced to cloud, consider moving database to:"
echo "  ~/Library/Application Support/My_CRM/my_crm.db"
echo "or:"
echo "  ~/CRM/my_crm.db"

