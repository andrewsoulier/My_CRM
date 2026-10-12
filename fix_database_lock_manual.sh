#!/bin/bash

# Manual Database Lock Fix
# Run this script DIRECTLY on andreassoul-fuji.nord via Terminal

echo "================================================================"
echo "MY CRM - Manual Database Lock Fix"
echo "================================================================"
echo ""

sanitize_int() {
    local value="$1"
    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        echo "$value"
    else
        echo "0"
    fi
}

SETTINGS_FILE="$HOME/Library/Application Support/My_CRM/User_Settings.json"
DEFAULT_DB_PATH="$HOME/Desktop/my_crm.db"

if [ -f "$SETTINGS_FILE" ]; then
    DB_PATH=$(python3 - <<'PY'
import json, os
from pathlib import Path

settings_path = Path(os.path.expanduser("~")) / "Library" / "Application Support" / "My_CRM" / "User_Settings.json"
try:
    with open(settings_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    path = data.get("database", {}).get("path")
    if path:
        print(path)
except Exception:
    pass
PY
)
    if [ -z "$DB_PATH" ]; then
        DB_PATH="$DEFAULT_DB_PATH"
    fi
else
    DB_PATH="$DEFAULT_DB_PATH"
fi

DB_PATH="${DB_PATH/#\~/$HOME}"
echo "Using database path: $DB_PATH"

echo "Step 1: Killing all My CRM processes..."
pkill -9 -f -i "my.?crm" 2>/dev/null || true
pkill -9 -f -i "my_crm" 2>/dev/null || true
pkill -9 -f -i "mycrm" 2>/dev/null || true
pkill -9 -f "com.mycrm.app" 2>/dev/null || true
pkill -9 -f "com.andrewsoulier.mycrm" 2>/dev/null || true
pkill -9 -f "/Applications/My CRM.app" 2>/dev/null || true
pkill -9 -f "My CRM.app" 2>/dev/null || true
sleep 3
echo "✅ Processes killed"
echo ""

echo "Step 1b: Unloading Quick Send launch agents..."
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
FOUND_AGENTS=false
if compgen -G "$LAUNCH_AGENT_DIR/com.mycrm.quicksend.*.plist" > /dev/null; then
    for plist in "$LAUNCH_AGENT_DIR"/com.mycrm.quicksend.*.plist; do
        [ -f "$plist" ] || continue
        FOUND_AGENTS=true
        launchctl unload -w "$plist" 2>/dev/null || true
        rm -f "$plist" 2>/dev/null || true
        echo "  Removed $(basename "$plist")"
    done
fi
if [ "$FOUND_AGENTS" = false ]; then
    echo "  No Quick Send launch agents found"
fi
echo ""

echo "Step 1c: Killing helper scripts and automation runners..."
pkill -9 -f "quick_send_helper" 2>/dev/null || true
pkill -9 osascript 2>/dev/null || true
sleep 1
echo "✅ Helper processes terminated"
echo ""

echo "Step 2: Checking for processes holding database lock..."
LOCKS=$(lsof "$DB_PATH" 2>/dev/null || echo "")
if [ -n "$LOCKS" ]; then
    echo "⚠️  Database still locked by:"
    echo "$LOCKS"
    echo ""
    echo "Force-killing these processes..."
    lsof "$DB_PATH" 2>/dev/null | awk 'NR>1 {print $2}' | xargs kill -9 2>/dev/null || true
    sleep 2
    echo "✅ Lock cleared"
else
    echo "✅ No locks detected"
fi
echo ""

echo "Step 3: Checking WAL files..."
if [ -f "$DB_PATH-wal" ]; then
    WAL_SIZE=$(stat -f %z "$DB_PATH-wal" 2>/dev/null || echo "0")
    WAL_SIZE=$(sanitize_int "$WAL_SIZE")
    echo "WAL file exists: $WAL_SIZE bytes"
    
    if [ "$WAL_SIZE" -gt 0 ]; then
        echo "Attempting to checkpoint WAL..."
        sqlite3 "$DB_PATH" "PRAGMA wal_checkpoint(TRUNCATE);" 2>&1 && echo "✅ WAL checkpointed" || echo "⚠️  Could not checkpoint WAL"
    else
        echo "WAL file is empty (OK)"
    fi
else
    echo "No WAL file (OK)"
fi
echo ""

echo "Step 3b: Clearing leftover trigger files..."
TRIGGER_DIR="$HOME/Library/Application Support/My_CRM/Triggers"
if [ -d "$TRIGGER_DIR" ]; then
    find "$TRIGGER_DIR" -name "*.trigger" -type f -delete 2>/dev/null || true
    echo "🧹 Removed trigger files from $TRIGGER_DIR"
else
    echo "No trigger directory found (OK)"
fi
echo ""

echo "Step 4: Verify database is accessible..."
if [ -f "$DB_PATH" ]; then
    echo "Database file exists"
    
    # Quick integrity check
    INTEGRITY=$(sqlite3 "$DB_PATH" "PRAGMA integrity_check;" 2>&1)
    if [ "$INTEGRITY" = "ok" ]; then
        echo "✅ Database integrity: OK"
    else
        echo "❌ Database integrity check failed:"
        echo "$INTEGRITY"
    fi
    
    # Check tables
    echo ""
    echo "Checking tables..."
    sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table';" | while read table; do
        COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM $table;" 2>&1)
        if [[ "$COUNT" =~ ^[0-9]+$ ]]; then
            echo "  $table: $COUNT rows"
        else
            echo "  $table: ? rows (error: $COUNT)"
        fi
    done
else
    echo "❌ Database file not found!"
fi
echo ""

echo "================================================================"
echo "Database lock should now be cleared!"
echo "================================================================"
echo ""
echo "Next steps:"
echo "  1. Launch My CRM from /Applications (Cmd+Space → 'My CRM')"
echo "  2. Check if data loads"
echo "  3. If still no data, run: ~/Desktop/diagnose_remote_live.sh"
echo ""


