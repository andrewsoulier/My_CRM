#!/bin/bash
set -euo pipefail

# Cron job script to update My CRM database every 90 seconds
# This script should be called by a cron job or launchd service

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_SUPPORT_DIR="$HOME/Library/Application Support/My_CRM"

# Ensure directories exist
mkdir -p "$APP_SUPPORT_DIR"
mkdir -p "$APP_SUPPORT_DIR/Logs"

# Logging
CRON_LOG="$APP_SUPPORT_DIR/Logs/cron_update.log"
log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$CRON_LOG"
}

# Limit log file size
if [ -f "$CRON_LOG" ] && [ $(stat -f%z "$CRON_LOG" 2>/dev/null || echo 0) -gt 1048576 ]; then
    mv "$CRON_LOG" "$CRON_LOG.old"
fi

log "=== Cron update started ==="

# Check if the bootstrap script exists
PY_BOOTSTRAP="$APP_BUNDLE_DIR/Resources/start.py"
if [ ! -f "$PY_BOOTSTRAP" ] && [ -f "$APP_BUNDLE_DIR/Resources/Start.py" ]; then
    PY_BOOTSTRAP="$APP_BUNDLE_DIR/Resources/Start.py"
fi

if [ ! -f "$PY_BOOTSTRAP" ]; then
    log "❌ Could not find bootstrap script at $PY_BOOTSTRAP"
    exit 1
fi

# Run the start.py script to update the database
log "Running database update..."
CRON_JOB=true /usr/bin/python3 "$PY_BOOTSTRAP" \
    --app-support "$APP_SUPPORT_DIR" \
    --logs "$APP_SUPPORT_DIR/Logs" >>"$CRON_LOG" 2>&1

PYTHON_EXIT_CODE=$?
log "Database update completed with exit code $PYTHON_EXIT_CODE"

exit $PYTHON_EXIT_CODE
