#!/bin/bash
set -euo pipefail

# Script to install the My CRM cron update service

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_FILE="$SCRIPT_DIR/com.mycrm.cronupdate.plist"
CRON_SCRIPT="$SCRIPT_DIR/cron_update.sh"

# Make the cron script executable
chmod +x "$CRON_SCRIPT"

# Copy the plist to LaunchAgents directory
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$LAUNCH_AGENTS_DIR"

# Create a user-specific version of the plist
USER_PLIST="$LAUNCH_AGENTS_DIR/com.mycrm.cronupdate.plist"

# Replace the hardcoded path with the actual script path
sed "s|/Users/andrewsoulier/My_CRM Project/My CRM/App/Feature Groups/iMessage Server Scraper/MacOS|$SCRIPT_DIR|g" "$PLIST_FILE" > "$USER_PLIST"

# Load the service
launchctl load "$USER_PLIST"

echo "✅ My CRM cron update service installed and started"
echo "   Service will run every 90 seconds"
echo "   Logs will be written to: $HOME/Library/Application Support/My_CRM/Logs/cron_update.log"
echo ""
echo "To uninstall, run: $SCRIPT_DIR/uninstall_cron.sh"
