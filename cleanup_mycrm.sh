#!/bin/bash

# My CRM Complete Cleanup Script
# This script removes all LaunchAgents, processes, and residual files
# Run this before deleting the app bundle to ensure clean removal

set -euo pipefail

echo "🧹 My CRM Complete Cleanup"
echo "=========================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track if any action was taken
ACTIONS_TAKEN=0

# Function to log success
log_success() {
    echo -e "${GREEN}✓${NC} $1"
    ACTIONS_TAKEN=$((ACTIONS_TAKEN + 1))
}

# Function to log info
log_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Function to log error
log_error() {
    echo -e "${RED}✗${NC} $1"
}

echo "Step 1: Unloading LaunchAgents..."
echo "-----------------------------------"

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

# Find all My CRM LaunchAgent plists
if [ -d "$LAUNCH_AGENTS_DIR" ]; then
    # Array of LaunchAgent patterns to clean up
    PATTERNS=("com.mycrm." "com.andrewsoulier.crm")
    
    shopt -s nullglob
    for pattern in "${PATTERNS[@]}"; do
        # Find matching plist files
        for plist in "$LAUNCH_AGENTS_DIR"/${pattern}*.plist; do
            if [ -f "$plist" ]; then
                LABEL=$(basename "$plist" .plist)
                
                # Check if it's loaded
                if launchctl list | grep -q "$LABEL"; then
                    log_info "Unloading LaunchAgent: $LABEL"
                    if launchctl unload -w "$plist" 2>/dev/null; then
                        log_success "Unloaded $LABEL"
                    else
                        log_error "Failed to unload $LABEL (may not be running)"
                    fi
                fi
                
                # Remove the plist file
                if rm "$plist" 2>/dev/null; then
                    log_success "Removed plist: $(basename "$plist")"
                fi
            fi
        done
    done
    shopt -u nullglob
else
    log_info "LaunchAgents directory not found"
fi

echo ""
echo "Step 2: Terminating running processes..."
echo "----------------------------------------"

# Kill any running My CRM processes
PROCESSES=$(ps aux | grep -i "my crm" | grep -v grep | grep -v "cleanup_mycrm.sh" | awk '{print $2}' || true)

if [ -n "$PROCESSES" ]; then
    for pid in $PROCESSES; do
        PROCESS_NAME=$(ps -p $pid -o comm= 2>/dev/null || echo "unknown")
        log_info "Terminating process: $PROCESS_NAME (PID: $pid)"
        if kill -15 $pid 2>/dev/null; then
            log_success "Terminated process $pid"
            sleep 1
            
            # Force kill if still running
            if ps -p $pid > /dev/null 2>&1; then
                log_info "Force killing process $pid"
                kill -9 $pid 2>/dev/null || true
            fi
        fi
    done
else
    log_info "No My CRM processes running"
fi

echo ""
echo "Step 3: Cleaning up helper scripts..."
echo "--------------------------------------"

# Clean up any running Python scripts related to My CRM
PYTHON_PROCESSES=$(ps aux | grep -i "python.*crm" | grep -v grep | awk '{print $2}' || true)

if [ -n "$PYTHON_PROCESSES" ]; then
    for pid in $PYTHON_PROCESSES; do
        log_info "Terminating Python process: $pid"
        kill -15 $pid 2>/dev/null || true
        log_success "Terminated Python process $pid"
    done
else
    log_info "No My CRM Python processes running"
fi

echo ""
echo "Step 4: Removing temporary files..."
echo "------------------------------------"

# Clean up trigger files
TRIGGER_DIR="$HOME/Library/Application Support/My_CRM/Triggers"
if [ -d "$TRIGGER_DIR" ]; then
    TRIGGER_COUNT=$(find "$TRIGGER_DIR" -name "*.trigger" 2>/dev/null | wc -l)
    if [ "$TRIGGER_COUNT" -gt 0 ]; then
        log_info "Removing $TRIGGER_COUNT trigger file(s)"
        rm -f "$TRIGGER_DIR"/*.trigger 2>/dev/null
        log_success "Removed trigger files"
    else
        log_info "No trigger files to clean"
    fi
fi

# Clean up temp log files
TEMP_LOGS=(/tmp/mycrm_quicksend_*.out /tmp/mycrm_quicksend_*.err /tmp/crm_*.log)
shopt -s nullglob
for file in "${TEMP_LOGS[@]}"; do
    if [ -f "$file" ]; then
        rm -f "$file" 2>/dev/null
        log_success "Removed temp file: $(basename "$file")"
    fi
done
shopt -u nullglob

echo ""
echo "Step 5: Checking for open file descriptors..."
echo "----------------------------------------------"

# Check for open files in the app bundle (if path is provided)
if [ $# -gt 0 ]; then
    APP_PATH="$1"
    if [ -d "$APP_PATH" ]; then
        log_info "Checking for open files in: $APP_PATH"
        OPEN_FILES=$(lsof "$APP_PATH" 2>/dev/null | wc -l)
        if [ "$OPEN_FILES" -gt 0 ]; then
            log_error "Warning: $OPEN_FILES file(s) still open in app bundle"
            lsof "$APP_PATH" 2>/dev/null | tail -n +2
        else
            log_success "No open files in app bundle"
        fi
    fi
fi

echo ""
echo "Summary"
echo "======="

if [ $ACTIONS_TAKEN -eq 0 ]; then
    echo -e "${GREEN}✓${NC} System is clean - no My CRM processes or LaunchAgents found"
else
    echo -e "${GREEN}✓${NC} Cleanup complete - $ACTIONS_TAKEN action(s) performed"
fi

echo ""
echo "You can now safely delete the My CRM app bundle."
echo ""

exit 0

