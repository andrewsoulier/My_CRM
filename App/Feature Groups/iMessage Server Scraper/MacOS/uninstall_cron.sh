#!/bin/bash
set -euo pipefail

# Script to uninstall the My CRM cron update service

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
USER_PLIST="$LAUNCH_AGENTS_DIR/com.mycrm.cronupdate.plist"

# Unload the service if it's running
if launchctl list | grep -q "com.mycrm.cronupdate"; then
    launchctl unload "$USER_PLIST"
    echo "✅ My CRM cron update service stopped"
else
    echo "ℹ️  My CRM cron update service was not running"
fi

# Remove the plist file
if [ -f "$USER_PLIST" ]; then
    rm "$USER_PLIST"
    echo "✅ Removed service configuration"
else
    echo "ℹ️  Service configuration file not found"
fi

echo "✅ My CRM cron update service uninstalled"
