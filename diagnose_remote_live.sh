#!/bin/bash

# Remote Database Diagnostics - Live Session
# Run this on andreassoul-fuji.nord to diagnose database connection issues

echo "================================================================"
echo "MY CRM - Remote Database Diagnostics"
echo "================================================================"
echo "Device: $(hostname)"
echo "User: $(whoami)"
echo "Date: $(date)"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

sanitize_int() {
    local value="$1"
    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
        echo "$value"
    else
        echo "0"
    fi
}

# Determine database path (default falls back to Desktop/my_crm.db)
SETTINGS_FILE="$HOME/Library/Application Support/My_CRM/User_Settings.json"
DEFAULT_DB_PATH="$HOME/Desktop/my_crm.db"

if [ -f "$SETTINGS_FILE" ]; then
    DB_PATH=$(python3 - <<'PY'
import json, os, sys
from pathlib import Path

settings_path = Path(os.path.expanduser("~")) / "Library" / "Application Support" / "My_CRM" / "User_Settings.json"
try:
    with open(settings_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    db_path = data.get("database", {}).get("path")
    if db_path:
        print(db_path)
except Exception as exc:
    print("", end="")
PY
)
    if [ -z "$DB_PATH" ]; then
        DB_PATH="$DEFAULT_DB_PATH"
    fi
else
    DB_PATH="$DEFAULT_DB_PATH"
fi

DB_PATH="${DB_PATH/#\~/$HOME}"
DB_DIR="$(dirname "$DB_PATH")"

echo "Detected database path: $DB_PATH"


echo "================================================================"
echo "1. APP VERSION CHECK"
echo "================================================================"

# Find the running app bundle path
RUNNING_APP_PATH=$(ps aux | grep -i "My CRM.app/Contents/MacOS" | grep -v grep | head -1 | sed 's/.*\(\/.*My CRM\.app\).*/\1/')

if [ -n "$RUNNING_APP_PATH" ]; then
    echo -e "${BLUE}📱 Running app found at: $RUNNING_APP_PATH${NC}"
    
    # Get version from running app
    RUNNING_VERSION=$(defaults read "$RUNNING_APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")
    RUNNING_BUILD=$(defaults read "$RUNNING_APP_PATH/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "unknown")
    RUNNING_BUNDLE_ID=$(defaults read "$RUNNING_APP_PATH/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "unknown")
    
    echo "  Version: $RUNNING_VERSION (Build $RUNNING_BUILD)"
    echo "  Bundle ID: $RUNNING_BUNDLE_ID"
    
    # Get modification date of running app
    RUNNING_APP_DATE=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$RUNNING_APP_PATH" 2>/dev/null || echo "unknown")
    echo "  App Bundle Modified: $RUNNING_APP_DATE"
    
    # Get executable modification date (more accurate for when it was built)
    RUNNING_EXEC_DATE=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$RUNNING_APP_PATH/Contents/MacOS/My CRM" 2>/dev/null || echo "unknown")
    echo "  Executable Built: $RUNNING_EXEC_DATE"
    echo ""
else
    echo -e "${YELLOW}⚠️  No running app instance found${NC}"
fi

# Check /Applications folder for installed version
INSTALLED_APP_PATH="/Applications/My CRM.app"
if [ -d "$INSTALLED_APP_PATH" ]; then
    echo -e "${BLUE}📦 Installed app found at: $INSTALLED_APP_PATH${NC}"
    
    INSTALLED_VERSION=$(defaults read "$INSTALLED_APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")
    INSTALLED_BUILD=$(defaults read "$INSTALLED_APP_PATH/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "unknown")
    
    echo "  Version: $INSTALLED_VERSION (Build $INSTALLED_BUILD)"
    
    INSTALLED_APP_DATE=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$INSTALLED_APP_PATH" 2>/dev/null || echo "unknown")
    INSTALLED_EXEC_DATE=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$INSTALLED_APP_PATH/Contents/MacOS/My CRM" 2>/dev/null || echo "unknown")
    
    echo "  App Bundle Modified: $INSTALLED_APP_DATE"
    echo "  Executable Built: $INSTALLED_EXEC_DATE"
    echo ""
    
    # Compare running vs installed
    if [ -n "$RUNNING_APP_PATH" ] && [ "$RUNNING_APP_PATH" != "$INSTALLED_APP_PATH" ]; then
        echo -e "${YELLOW}⚠️  WARNING: Running app is NOT from /Applications/${NC}"
        echo "   Running from: $RUNNING_APP_PATH"
        echo "   This may be an old or test build!"
        echo ""
    fi
    
    if [ "$RUNNING_EXEC_DATE" != "$INSTALLED_EXEC_DATE" ] && [ -n "$RUNNING_APP_PATH" ]; then
        echo -e "${YELLOW}⚠️  WARNING: Running app build date differs from installed app${NC}"
        echo "   Running app built: $RUNNING_EXEC_DATE"
        echo "   Installed app built: $INSTALLED_EXEC_DATE"
        
        # Determine which is newer
        RUNNING_TIMESTAMP=$(stat -f "%m" "$RUNNING_APP_PATH/Contents/MacOS/My CRM" 2>/dev/null || echo "0")
        INSTALLED_TIMESTAMP=$(stat -f "%m" "$INSTALLED_APP_PATH/Contents/MacOS/My CRM" 2>/dev/null || echo "0")
        RUNNING_TIMESTAMP=$(sanitize_int "$RUNNING_TIMESTAMP")
        INSTALLED_TIMESTAMP=$(sanitize_int "$INSTALLED_TIMESTAMP")
        
        if [ "$INSTALLED_TIMESTAMP" -gt "$RUNNING_TIMESTAMP" ]; then
            echo -e "${RED}   ❌ INSTALLED APP IS NEWER! You're running an outdated build.${NC}"
            echo "   ACTION: Restart the app from /Applications/My CRM.app"
        else
            echo -e "${BLUE}   ℹ️  Running app is newer (may be a test build)${NC}"
        fi
        echo ""
    elif [ -n "$RUNNING_APP_PATH" ]; then
        echo -e "${GREEN}✅ Running app matches installed version${NC}"
        echo ""
    fi
else
    echo -e "${YELLOW}⚠️  No app found in /Applications folder${NC}"
    echo "   Expected location: /Applications/My CRM.app"
    echo ""
fi

# Check for recent DMG installers (shows available updates)
echo "Checking for DMG installers..."
DMG_LOCATIONS=(
    "$HOME/Desktop"
    "$HOME/Downloads"
    "/Volumes/andrewsoulier/My_CRM Project/MY CRM"
)

FOUND_DMG=false
for location in "${DMG_LOCATIONS[@]}"; do
    if [ -d "$location" ]; then
        DMG_FILES=$(find "$location" -maxdepth 1 -name "My CRM Installer*.dmg" -type f 2>/dev/null)
        if [ -n "$DMG_FILES" ]; then
            FOUND_DMG=true
            echo -e "${BLUE}Found DMG installer(s) in $location:${NC}"
            echo "$DMG_FILES" | while read dmg; do
                DMG_DATE=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$dmg" 2>/dev/null || echo "unknown")
                DMG_SIZE=$(stat -f "%z" "$dmg" 2>/dev/null | awk '{print $1/1024/1024 " MB"}')
                echo "  📀 $(basename "$dmg")"
                echo "     Created: $DMG_DATE"
                echo "     Size: $DMG_SIZE"
                
                # Compare DMG date with installed app
                if [ -n "$INSTALLED_EXEC_DATE" ]; then
                    DMG_TIMESTAMP=$(stat -f "%m" "$dmg" 2>/dev/null || echo "0")
                    INSTALLED_TIMESTAMP=$(stat -f "%m" "$INSTALLED_APP_PATH/Contents/MacOS/My CRM" 2>/dev/null || echo "0")
                    DMG_TIMESTAMP=$(sanitize_int "$DMG_TIMESTAMP")
                    INSTALLED_TIMESTAMP=$(sanitize_int "$INSTALLED_TIMESTAMP")
                    
                    if [ "$DMG_TIMESTAMP" -gt "$INSTALLED_TIMESTAMP" ]; then
                        echo -e "${YELLOW}     ⚠️  This DMG is NEWER than the installed app!${NC}"
                        echo "     ACTION: Install this DMG to get the latest version"
                    fi
                fi
            done
            echo ""
        fi
    fi
done

if [ "$FOUND_DMG" = false ]; then
    echo "  No DMG installers found in common locations"
    echo ""
fi

# Check Google Drive for latest DMG (if mounted)
GOOGLE_DRIVE_PATH="/Volumes/andrewsoulier/Google Drive/Shared Apps/My CRM"
if [ -d "$GOOGLE_DRIVE_PATH" ]; then
    echo "Checking Google Drive for latest installer..."
    LATEST_DMG=$(find "$GOOGLE_DRIVE_PATH" -name "My CRM Installer*.dmg" -type f 2>/dev/null | sort -r | head -1)
    if [ -n "$LATEST_DMG" ]; then
        LATEST_DMG_DATE=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$LATEST_DMG" 2>/dev/null || echo "unknown")
        echo -e "${BLUE}📦 Latest DMG on Google Drive:${NC}"
        echo "  $(basename "$LATEST_DMG")"
        echo "  Created: $LATEST_DMG_DATE"
        
        if [ -n "$INSTALLED_EXEC_DATE" ]; then
            LATEST_DMG_TIMESTAMP=$(stat -f "%m" "$LATEST_DMG" 2>/dev/null || echo "0")
            INSTALLED_TIMESTAMP=$(stat -f "%m" "$INSTALLED_APP_PATH/Contents/MacOS/My CRM" 2>/dev/null || echo "0")
            LATEST_DMG_TIMESTAMP=$(sanitize_int "$LATEST_DMG_TIMESTAMP")
            INSTALLED_TIMESTAMP=$(sanitize_int "$INSTALLED_TIMESTAMP")
            
            if [ "$LATEST_DMG_TIMESTAMP" -gt "$INSTALLED_TIMESTAMP" ]; then
                echo -e "${RED}  ❌ YOUR APP IS OUTDATED!${NC}"
                echo "  Google Drive has a newer version from $LATEST_DMG_DATE"
                echo "  ACTION: Copy and install the latest DMG from Google Drive"
            else
                echo -e "${GREEN}  ✅ Your app is up to date with Google Drive${NC}"
            fi
        fi
        echo ""
    fi
fi

echo "================================================================"
echo "2. CHECKING FOR MULTIPLE APP INSTANCES"
echo "================================================================"
APP_INSTANCES=$(ps aux | grep -i "My CRM.app" | grep -v grep || true)
INSTANCE_COUNT=$(echo "$APP_INSTANCES" | grep -c "My CRM.app" 2>/dev/null || echo "0")
INSTANCE_COUNT=$(sanitize_int "$INSTANCE_COUNT")

if [ "$INSTANCE_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Found $INSTANCE_COUNT My CRM instance(s) running:${NC}"
    echo "$APP_INSTANCES"
    echo ""
    echo -e "${YELLOW}PIDs:${NC}"
    ps aux | grep -i "My CRM.app" | grep -v grep | awk '{print "  - PID: " $2 " (CPU: " $3 "%, MEM: " $4 "%)"}'
else
    echo -e "${GREEN}✅ No My CRM instances currently running${NC}"
fi
echo ""

echo "================================================================"
echo "3. DATABASE FILE STATUS"
echo "================================================================"
if [ -f "$DB_PATH" ]; then
    echo -e "${GREEN}✅ Database file exists${NC}"
    ls -lh "$DB_PATH"
    echo ""
    
    # Check permissions
    echo "Permissions:"
    stat -f "  Owner: %Su:%Sg" "$DB_PATH"
    stat -f "  Permissions: %Sp (%p)" "$DB_PATH"
    echo ""
    
    # Check file size
    FILE_SIZE=$(stat -f %z "$DB_PATH" 2>/dev/null || echo "0")
    FILE_SIZE=$(sanitize_int "$FILE_SIZE")
    if [ "$FILE_SIZE" -lt 1024 ]; then
        echo -e "${RED}❌ WARNING: Database file is very small ($FILE_SIZE bytes)${NC}"
        echo "   This may indicate corruption or incomplete initialization"
    else
        echo -e "${GREEN}✅ Database file size: $(stat -f %z "$DB_PATH" | awk '{print $1/1024/1024 " MB"}')${NC}"
    fi
else
    echo -e "${RED}❌ Database file NOT FOUND at: $DB_PATH${NC}"
fi
echo ""

echo "================================================================"
echo "4. DATABASE FILE LOCKS (CRITICAL)"
echo "================================================================"
echo "Checking processes with database file open..."
LOCKS=$(lsof "$DB_PATH" 2>/dev/null)
if [ -n "$LOCKS" ]; then
    echo -e "${YELLOW}⚠️  Database file is currently LOCKED by:${NC}"
    echo "$LOCKS"
    echo ""
    echo -e "${YELLOW}This explains why you cannot open it in DB Browser!${NC}"
else
    echo -e "${GREEN}✅ No file locks detected${NC}"
    echo "   (Database should be accessible in DB Browser)"
fi
echo ""

echo "================================================================"
echo "5. WAL MODE FILES"
echo "================================================================"
WAL_FILE="$DB_PATH-wal"
SHM_FILE="$DB_PATH-shm"

if [ -f "$WAL_FILE" ]; then
    echo -e "${BLUE}📄 WAL file exists:${NC}"
    ls -lh "$WAL_FILE"
    WAL_SIZE=$(stat -f %z "$WAL_FILE" 2>/dev/null || echo "0")
    WAL_SIZE=$(sanitize_int "$WAL_SIZE")
    if [ "$WAL_SIZE" -gt 0 ]; then
        echo -e "${YELLOW}   ⚠️  WAL file has uncommitted transactions (${WAL_SIZE} bytes)${NC}"
        echo "   This may indicate an incomplete write or crash"
    fi
else
    echo "   No WAL file found"
fi

if [ -f "$SHM_FILE" ]; then
    echo -e "${BLUE}📄 SHM file exists:${NC}"
    ls -lh "$SHM_FILE"
else
    echo "   No SHM file found"
fi

if [ -f "$WAL_FILE" ] && [ "$INSTANCE_COUNT" = "0" ]; then
    echo ""
    echo -e "${YELLOW}⚠️  WAL file exists but no app is running${NC}"
    echo "   This suggests the app crashed without checkpointing the WAL"
    WAL_SIZE=$(stat -f %z "$WAL_FILE" 2>/dev/null || echo "0")
    WAL_SIZE=$(sanitize_int "$WAL_SIZE")
    echo "   WAL file size: ${WAL_SIZE} bytes"
fi
echo ""

echo "================================================================"
echo "6. APPLICATION LOGS"
echo "================================================================"
LOG_ROOT="$HOME/Library/Application Support/My_CRM"
if [ -d "$LOG_ROOT" ]; then
    echo -e "${GREEN}✅ Log directory exists${NC}"
    echo "Contents:"
    ls -lht "$LOG_ROOT" | head -10
    echo ""
    
    LOG_SEARCH_PATHS=("$LOG_ROOT" "$LOG_ROOT/Logs" "$LOG_ROOT/Logs/Archive")
    LOG_FILES=()
    for path in "${LOG_SEARCH_PATHS[@]}"; do
        if [ -d "$path" ]; then
            while IFS= read -r log_file; do
                LOG_FILES+=("$log_file")
            done < <(find "$path" -maxdepth 1 -type f -name "*.log" 2>/dev/null)
        fi
    done

    if [ "${#LOG_FILES[@]}" -gt 0 ]; then
        IFS=$'\n' SORTED_LOGS=($(printf "%s\n" "${LOG_FILES[@]}" | sort -r))
        LATEST_LOG="${SORTED_LOGS[0]}"
        echo -e "${BLUE}📋 Most recent log: $(basename "$LATEST_LOG")${NC}"
        echo "Last 30 lines:"
        echo "----------------------------------------"
        tail -30 "$LATEST_LOG"
        echo "----------------------------------------"
        echo ""
        
        echo "Searching for critical errors in logs..."
        ERROR_PATTERNS=(
            "disk I/O error"
            "database is locked"
            "no such table"
            "Failed to open database"
            "authorization denied"
            "SQLITE_IOERR"
            "SQLITE_BUSY"
            "SQLITE_LOCKED"
            "Failed to load contacts"
            "Failed to load groups"
        )
        
        for pattern in "${ERROR_PATTERNS[@]}"; do
            COUNT=$(grep -c "$pattern" "$LATEST_LOG" 2>/dev/null || echo "0")
            COUNT=$(sanitize_int "$COUNT")
            if [ "$COUNT" -gt 0 ]; then
                echo -e "${RED}❌ Found '$pattern': $COUNT occurrences${NC}"
                echo "   Last occurrence:"
                grep "$pattern" "$LATEST_LOG" | tail -1 | sed 's/^/   /'
            fi
        done
        echo ""
    else
        echo -e "${YELLOW}⚠️  No log files found in $LOG_ROOT or subdirectories${NC}"
    fi
else
    echo -e "${RED}❌ Log directory NOT FOUND: $LOG_ROOT${NC}"
fi
echo ""

echo "================================================================"
echo "7. SQLITE INTEGRITY CHECK"
echo "================================================================"
if [ -f "$DB_PATH" ] && [ "$INSTANCE_COUNT" -eq 0 ]; then
    echo "Running PRAGMA integrity_check..."
    INTEGRITY=$(sqlite3 "$DB_PATH" "PRAGMA integrity_check;" 2>&1)
    if [ "$INTEGRITY" = "ok" ]; then
        echo -e "${GREEN}✅ Database integrity: OK${NC}"
    else
        echo -e "${RED}❌ Database integrity check FAILED:${NC}"
        echo "$INTEGRITY"
    fi
    echo ""
    
    echo "Checking journal mode..."
    JOURNAL_MODE=$(sqlite3 "$DB_PATH" "PRAGMA journal_mode;" 2>&1)
    echo "  Journal mode: $JOURNAL_MODE"
    if [ "$JOURNAL_MODE" = "wal" ]; then
        echo -e "${GREEN}  ✅ WAL mode is enabled${NC}"
    else
        echo -e "${YELLOW}  ⚠️  WAL mode is NOT enabled (should be 'wal', got '$JOURNAL_MODE')${NC}"
    fi
    echo ""
    
    echo "Checking tables..."
    TABLES=$(sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table';" 2>&1)
    if [ -n "$TABLES" ]; then
        echo -e "${GREEN}✅ Tables found:${NC}"
        echo "$TABLES" | sed 's/^/  - /'
        
        # Check for required tables
        REQUIRED_TABLES=("contacts" "groups" "canvases" "messages" "batch_messages")
        for table in "${REQUIRED_TABLES[@]}"; do
            if echo "$TABLES" | grep -q "^$table$"; then
                echo -e "${GREEN}  ✅ $table${NC}"
                
                # Count rows
                COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM $table;" 2>&1)
                if [[ "$COUNT" =~ ^[0-9]+$ ]]; then
                    echo "     Rows: $COUNT"
                else
                    echo -e "${YELLOW}     ⚠️  Unable to count rows (error: $COUNT)${NC}"
                fi
            else
                echo -e "${RED}  ❌ $table - MISSING${NC}"
            fi
        done
    else
        echo -e "${RED}❌ No tables found or error accessing database${NC}"
    fi
elif [ "$INSTANCE_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Skipping integrity check - app is currently running${NC}"
    echo "   Stop the app first to run integrity checks"
else
    echo -e "${RED}❌ Cannot check integrity - database file not found${NC}"
fi
echo ""

echo "================================================================"
echo "8. DISK SPACE"
echo "================================================================"
df -h "$HOME/Desktop" | tail -1 | awk '{print "Available space: " $4 " (Used: " $5 ")"}'
echo ""

echo "================================================================"
echo "9. SYSTEM INFORMATION"
echo "================================================================"
echo "macOS Version: $(sw_vers -productVersion)"
echo "Memory: $(sysctl hw.memsize | awk '{print $2/1024/1024/1024 " GB"}')"
echo "CPU: $(sysctl -n machdep.cpu.brand_string)"
echo ""

echo "================================================================"
echo "SUMMARY & RECOMMENDATIONS"
echo "================================================================"

# Analyze findings
ISSUES_FOUND=0

# Check version issues first (most likely cause)
if [ -n "$RUNNING_APP_PATH" ] && [ -d "$INSTALLED_APP_PATH" ]; then
    RUNNING_TIMESTAMP=$(stat -f "%m" "$RUNNING_APP_PATH/Contents/MacOS/My CRM" 2>/dev/null || echo "0")
    INSTALLED_TIMESTAMP=$(stat -f "%m" "$INSTALLED_APP_PATH/Contents/MacOS/My CRM" 2>/dev/null || echo "0")
    RUNNING_TIMESTAMP=$(sanitize_int "$RUNNING_TIMESTAMP")
    INSTALLED_TIMESTAMP=$(sanitize_int "$INSTALLED_TIMESTAMP")
    
    if [ "$RUNNING_TIMESTAMP" != "$INSTALLED_TIMESTAMP" ] && [ "$INSTALLED_TIMESTAMP" -gt "$RUNNING_TIMESTAMP" ]; then
        echo -e "${RED}❌ CRITICAL: Running OUTDATED app version${NC}"
        echo "   Your app was built: $(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$RUNNING_APP_PATH/Contents/MacOS/My CRM" 2>/dev/null)"
        echo "   Newer version available: $(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$INSTALLED_APP_PATH/Contents/MacOS/My CRM" 2>/dev/null)"
        echo "   ACTION: Quit the app and launch from /Applications/My CRM.app"
        echo "   THIS MAY BE WHY DATA IS NOT LOADING!"
        ISSUES_FOUND=$((ISSUES_FOUND+1))
        echo ""
    fi
    
    if [ "$RUNNING_APP_PATH" != "$INSTALLED_APP_PATH" ]; then
        echo -e "${YELLOW}⚠️  WARNING: Running app from non-standard location${NC}"
        echo "   Running from: $RUNNING_APP_PATH"
        echo "   Should be: $INSTALLED_APP_PATH"
        echo "   ACTION: Launch the app from /Applications instead"
        ISSUES_FOUND=$((ISSUES_FOUND+1))
        echo ""
    fi
fi

if [ "$INSTANCE_COUNT" -gt 1 ]; then
    echo -e "${RED}❌ ISSUE: Multiple app instances running${NC}"
    echo "   ACTION: Quit all instances and restart with only one"
    ISSUES_FOUND=$((ISSUES_FOUND+1))
    echo ""
fi

if [ -n "$LOCKS" ]; then
    echo -e "${RED}❌ ISSUE: Database is locked${NC}"
    echo "   ACTION: Quit the app to release the lock"
    ISSUES_FOUND=$((ISSUES_FOUND+1))
fi

if [ -f "$WAL_FILE" ] && [ "$INSTANCE_COUNT" -eq 0 ]; then
    WAL_SIZE=$(stat -f %z "$WAL_FILE")
    if [ "$WAL_SIZE" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  WARNING: Uncommitted WAL transactions${NC}"
        echo "   ACTION: Start the app to checkpoint the WAL"
        ISSUES_FOUND=$((ISSUES_FOUND+1))
    fi
fi

if [ ! -f "$DB_PATH" ]; then
    echo -e "${RED}❌ ISSUE: Database file missing${NC}"
    echo "   ACTION: Check if database was moved or deleted"
    ISSUES_FOUND=$((ISSUES_FOUND+1))
fi

if [ "$ISSUES_FOUND" -eq 0 ]; then
    echo -e "${GREEN}✅ No obvious issues detected${NC}"
    echo ""
    echo "Since the app loads but shows no data:"
    echo "  1. Check the application logs above for specific errors"
    echo "  2. Verify database has data (check row counts above)"
    echo "  3. Check if SettingsManager is pointing to wrong database path"
fi

echo ""
echo "================================================================"
echo "NEXT STEPS"
echo "================================================================"
echo "1. Review the errors found in application logs (Section 5)"
echo "2. If database is locked, quit the app to release it"
echo "3. If multiple instances running, keep only one"
echo "4. Share this diagnostic output for further analysis"
echo ""
echo "To save this report:"
echo "  ./diagnose_remote_live.sh > ~/Desktop/diagnostic_report.txt"
echo ""
echo "================================================================"

