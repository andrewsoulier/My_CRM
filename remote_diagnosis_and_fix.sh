#!/bin/bash

# Remote Diagnosis and Fix Script
# Connects to andreassoul-fuji.nord via SMB/SSH and fixes database issues

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "================================================================"
echo "MY CRM - Remote Diagnosis and Fix Tool"
echo "================================================================"
echo ""

# Remote connection details
REMOTE_HOST="andreassoul-fuji.nord"
REMOTE_USER="andrewsoulier"
REMOTE_PASS="28VP04!!"
SSH_KEY_PATH="$HOME/.ssh/id_ed25519"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIAGNOSTIC_SCRIPT="$SCRIPT_DIR/diagnose_remote_live.sh"

# Check if diagnostic script exists
if [ ! -f "$DIAGNOSTIC_SCRIPT" ]; then
    echo -e "${RED}❌ Error: diagnose_remote_live.sh not found${NC}"
    echo "Expected location: $DIAGNOSTIC_SCRIPT"
    exit 1
fi

echo -e "${BLUE}📡 Connecting to remote device: $REMOTE_HOST${NC}"
echo ""

# Function to execute remote commands
execute_remote() {
    local commands="$1"
    local description="$2"
    
    echo -e "${BLUE}→ $description${NC}"
    
    # Try SSH key first
    if [ -f "$SSH_KEY_PATH" ]; then
        ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" "$commands" 2>/dev/null && return 0
    fi
    
    # Try sshpass with password
    if command -v sshpass &> /dev/null; then
        sshpass -p "$REMOTE_PASS" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "$commands" 2>/dev/null && return 0
    fi
    
    echo -e "${RED}❌ Could not connect to remote device${NC}"
    echo "Please ensure:"
    echo "  1. Remote device is online"
    echo "  2. Remote login is enabled in System Settings > General > Sharing"
    echo "  3. You can access the device via Screen Sharing"
    return 1
}

# Function to copy file to remote
copy_to_remote() {
    local local_file="$1"
    local remote_path="$2"
    local description="$3"
    
    echo -e "${BLUE}→ $description${NC}"
    
    # Try SCP with SSH key
    if [ -f "$SSH_KEY_PATH" ]; then
        scp -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$local_file" "$REMOTE_USER@$REMOTE_HOST:$remote_path" 2>/dev/null && return 0
    fi
    
    # Try SCP with sshpass
    if command -v sshpass &> /dev/null; then
        sshpass -p "$REMOTE_PASS" scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$local_file" "$REMOTE_USER@$REMOTE_HOST:$remote_path" 2>/dev/null && return 0
    fi
    
    return 1
}

run_remote_capture() {
    local command="$1"
    if [ -f "$SSH_KEY_PATH" ]; then
        ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "$command"
        return $?
    elif command -v sshpass &> /dev/null; then
        sshpass -p "$REMOTE_PASS" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "$command"
        return $?
    else
        return 1
    fi
}

echo "================================================================"
echo "STEP 1: FORCE-QUIT ANY STUCK PROCESSES"
echo "================================================================"

KILL_COMMANDS=$(cat <<'EOS'
echo "Killing My CRM processes..."
pkill -9 -f -i "my.?crm" 2>/dev/null || true
pkill -9 -f -i "my_crm" 2>/dev/null || true
pkill -9 -f -i "mycrm" 2>/dev/null || true
pkill -9 -f "com.mycrm.app" 2>/dev/null || true
pkill -9 -f "com.andrewsoulier.mycrm" 2>/dev/null || true
pkill -9 -f "/Applications/My CRM.app" 2>/dev/null || true
pkill -9 -f "My CRM.app" 2>/dev/null || true
sleep 2
echo "Done killing processes"
EOS
)

if execute_remote "$KILL_COMMANDS" "Force-quitting all My CRM instances"; then
    echo -e "${GREEN}✅ Processes terminated${NC}"
else
    echo -e "${YELLOW}⚠️  Could not connect via SSH. Please manually quit the app via Screen Sharing.${NC}"
    echo ""
    read -p "Press Enter after you have quit the app manually..."
fi
echo ""

echo "================================================================"
echo "STEP 2: CHECK AND CLEAR DATABASE LOCKS"
echo "================================================================"

CHECK_LOCKS_COMMANDS=$(cat <<'EOS'
SETTINGS_FILE="$HOME/Library/Application Support/My_CRM/User_Settings.json"
DB_PATH="$HOME/Desktop/my_crm.db"

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
        DB_PATH="$HOME/Desktop/my_crm.db"
    fi
fi

DB_PATH="${DB_PATH/#\~/$HOME}"
echo "Using database path: $DB_PATH"

echo "Checking for database locks..."
LOCKS=$(lsof "$DB_PATH" 2>/dev/null || echo "")
if [ -n "$LOCKS" ]; then
    echo "WARNING: Database still locked by:"
    echo "$LOCKS"
    lsof "$DB_PATH" 2>/dev/null | awk 'NR>1 {print $2}' | xargs -r kill -9 2>/dev/null || true
    sleep 1
    echo "Killed locking processes"
else
    echo "No locks detected"
fi

# Check WAL files
if [ -f "$DB_PATH-wal" ]; then
    WAL_SIZE=$(stat -f %z "$DB_PATH-wal" 2>/dev/null || echo "0")
    if [[ "$WAL_SIZE" =~ ^[0-9]+$ ]] && [ "$WAL_SIZE" -gt 0 ]; then
        echo "WAL file exists: $WAL_SIZE bytes"
        echo "Attempting to checkpoint WAL..."
        sqlite3 "$DB_PATH" "PRAGMA wal_checkpoint(TRUNCATE);" 2>&1 || echo "Could not checkpoint WAL"
    elif [[ "$WAL_SIZE" =~ ^[0-9]+$ ]]; then
        echo "WAL file exists but is empty ($WAL_SIZE bytes)"
    else
        echo "WAL file detected but size unknown ($WAL_SIZE)"
    fi
fi

echo "Database lock check complete"
EOS
)

if execute_remote "$CHECK_LOCKS_COMMANDS" "Checking and clearing database locks"; then
    echo -e "${GREEN}✅ Database locks cleared${NC}"
else
    echo -e "${YELLOW}⚠️  Could not connect via SSH${NC}"
fi
echo ""

REMOTE_DB_PATH=$(run_remote_capture "python3 -c \"import json, os, pathlib, sys; p = pathlib.Path(os.path.expanduser('~')) / 'Library/Application Support/My_CRM/User_Settings.json'; data = json.loads(p.read_text()) if p.exists() else {}; path = data.get('database', {}).get('path'); sys.stdout.write(path or '')\"" 2>/dev/null || true)
REMOTE_DB_PATH=$(printf "%s" "$REMOTE_DB_PATH" | tr -d '\r')
if [ -z "$REMOTE_DB_PATH" ]; then
    REMOTE_DB_PATH="$HOME/Desktop/my_crm.db"
fi
if [[ "$REMOTE_DB_PATH" == "$HOME"* ]]; then
    REMOTE_DB_PATH_DISPLAY="~${REMOTE_DB_PATH#$HOME}"
else
    REMOTE_DB_PATH_DISPLAY="$REMOTE_DB_PATH"
fi
echo "Remote database path (from settings): $REMOTE_DB_PATH_DISPLAY"
echo ""

echo "================================================================"
echo "STEP 3: COPY AND RUN DIAGNOSTIC SCRIPT"
echo "================================================================"

# Copy diagnostic script to remote
REMOTE_DIAG_PATH="~/Desktop/diagnose_remote_live.sh"

if copy_to_remote "$DIAGNOSTIC_SCRIPT" "$REMOTE_DIAG_PATH" "Copying diagnostic script to remote device"; then
    echo -e "${GREEN}✅ Diagnostic script copied${NC}"
    
    # Make executable and run
    RUN_DIAGNOSTIC='
    cd ~/Desktop
    chmod +x diagnose_remote_live.sh
    ./diagnose_remote_live.sh
    '
    
    echo ""
    echo -e "${BLUE}Running diagnostics on remote device...${NC}"
    echo "================================================================"
    
    if [ -f "$SSH_KEY_PATH" ]; then
        ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "$RUN_DIAGNOSTIC" 2>/dev/null || echo "Diagnostic completed"
    elif command -v sshpass &> /dev/null; then
        sshpass -p "$REMOTE_PASS" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "$RUN_DIAGNOSTIC" 2>/dev/null || echo "Diagnostic completed"
    fi
    
    echo "================================================================"
    echo ""
else
    echo -e "${YELLOW}⚠️  Could not copy via SCP${NC}"
    echo ""
    echo "Manual steps:"
    echo "  1. Open Screen Sharing to andreassoul-fuji.nord"
    echo "  2. Copy diagnose_remote_live.sh to Desktop"
    echo "  3. Open Terminal and run:"
    echo "     cd ~/Desktop && chmod +x diagnose_remote_live.sh && ./diagnose_remote_live.sh"
fi

echo "================================================================"
echo "STEP 4: CHECK FOR LATEST DMG"
echo "================================================================"

# Check if Google Drive is mounted
GOOGLE_DRIVE_PATH="/Volumes/andrewsoulier/Google Drive/Shared Apps/My CRM"
if [ -d "$GOOGLE_DRIVE_PATH" ]; then
    LATEST_DMG=$(find "$GOOGLE_DRIVE_PATH" -name "My CRM Installer*.dmg" -type f 2>/dev/null | sort -r | head -1)
    
    if [ -n "$LATEST_DMG" ]; then
        LATEST_DMG_DATE=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$LATEST_DMG" 2>/dev/null)
        echo -e "${GREEN}✅ Latest DMG found: $(basename "$LATEST_DMG")${NC}"
        echo "   Created: $LATEST_DMG_DATE"
        echo ""
        
        if [ -t 0 ]; then
            read -p "Copy latest DMG to remote device? (y/n): " -n 1 -r || true
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                REMOTE_DMG_PATH="~/Desktop/$(basename "$LATEST_DMG")"
                if copy_to_remote "$LATEST_DMG" "$REMOTE_DMG_PATH" "Copying DMG to remote Desktop"; then
                    echo -e "${GREEN}✅ DMG copied to remote Desktop${NC}"
                    echo ""
                    echo -e "${YELLOW}Next steps:${NC}"
                    echo "  1. Open the DMG on the remote device"
                    echo "  2. Drag My CRM.app to Applications (replace existing)"
                    echo "  3. Launch the app from Applications"
                else
                    echo -e "${YELLOW}⚠️  Could not copy DMG via SCP${NC}"
                    echo "You can manually copy via Finder (SMB) or use Screen Sharing"
                fi
            fi
        else
            echo "(Skipping DMG copy prompt - non-interactive session)"
        fi
    else
        echo -e "${YELLOW}⚠️  No DMG found in Google Drive${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Google Drive not mounted${NC}"
    echo "Mount Google Drive first to access latest installers"
fi
echo ""

echo "================================================================"
echo "STEP 5: RECOMMENDATIONS"
echo "================================================================"
echo ""
echo "Based on the diagnostics above, check for:"
echo ""
echo "1. ${RED}VERSION MISMATCH${NC}"
echo "   → If running outdated version, install latest DMG"
echo ""
echo "2. ${RED}DATABASE LOCKED${NC}"
echo "   → Should be cleared now. If not, manually restart the Mac"
echo ""
echo "3. ${RED}MISSING DATA${NC}"
echo "   → Check Section 7 of diagnostics for table row counts"
echo "   → If tables are empty, database may need restoration from backup"
echo ""
echo "4. ${RED}MULTIPLE INSTANCES${NC}"
echo "   → Should be killed now. Check Spotlight to ensure only one launches"
echo ""
echo "================================================================"
echo "NEXT ACTIONS"
echo "================================================================"
echo ""
echo "Via Screen Sharing on andreassoul-fuji.nord:"
echo ""
echo "1. ${GREEN}Verify processes are stopped:${NC}"
echo "   Activity Monitor → Search 'CRM' → Should be empty"
echo ""
echo "2. ${GREEN}Try opening database in DB Browser:${NC}"
echo "   Open DB Browser → Open Database → $REMOTE_DB_PATH_DISPLAY"
echo "   If it opens, lock is cleared ✅"
echo ""
echo "3. ${GREEN}Launch app from /Applications:${NC}"
echo "   Cmd+Space → Type 'My CRM' → Press Enter"
echo "   (NOT from Desktop, build folder, or any other location)"
echo ""
echo "4. ${GREEN}Check app logs immediately after launch:${NC}"
echo "   ~/Library/Application Support/My_CRM/Logs/*.log"
echo "   Look for errors in the first 30 lines"
echo ""
echo "5. ${GREEN}If still no data loads:${NC}"
echo "   Share the diagnostic output and latest app logs"
echo ""
echo "================================================================"

# Offer to save diagnostic output
if [ -t 0 ]; then
    read -p "Save diagnostic output to file? (y/n): " -n 1 -r || true
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        OUTPUT_FILE="$HOME/Desktop/remote_diagnostic_$(date +%Y%m%d_%H%M%S).txt"
        
        SAVE_DIAGNOSTIC='
        cd ~/Desktop
        if [ -f diagnose_remote_live.sh ]; then
            ./diagnose_remote_live.sh > diagnostic_report.txt 2>&1
            echo "Saved to ~/Desktop/diagnostic_report.txt"
        fi
        '
        
        if execute_remote "$SAVE_DIAGNOSTIC" "Saving diagnostic report"; then
            echo -e "${GREEN}✅ Diagnostic report saved on remote device${NC}"
            echo "   Location: ~/Desktop/diagnostic_report.txt"
        fi
    fi
else
    echo "(Skipping diagnostic save prompt - non-interactive session)"
fi

echo ""
echo "================================================================"
echo "Script Complete!"
echo "================================================================"
echo ""


