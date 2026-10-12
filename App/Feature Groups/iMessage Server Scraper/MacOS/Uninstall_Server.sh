#!/bin/bash

echo "🧹 Uninstalling My CRM..."

osascript -e 'display dialog "Uninstalling My CRM and related services..." buttons ["OK"] default button "OK" with title "My CRM"'

# Unload and remove LaunchAgent
PLIST="$HOME/Library/LaunchAgents/com.mycrm.crmlaunch.plist"
if [ -f "$PLIST" ]; then
  echo "🗑 Removing LaunchAgent..."
  launchctl unload "$PLIST"
  rm "$PLIST"
fi

# Remove log files
LOG_DIR="$(dirname "$0")/../Resources/Logs"
if [ -d "$LOG_DIR" ]; then
  echo "🗑 Deleting logs..."
  rm -rf "$LOG_DIR"
fi

# Uninstall PyObjC Contacts framework
PYTHON_PATH=$(which python3.12 || which python3)
if [ -x "$PYTHON_PATH" ]; then
  echo "🧼 Uninstalling pyobjc-framework-Contacts..."
  "$PYTHON_PATH" -m pip uninstall -y pyobjc-framework-Contacts
fi

# Optionally unlink Python 3.12
read -p "Unlink python@3.12 installed via Homebrew? (y/N): " UNLINK
if [[ "$UNLINK" == "y" || "$UNLINK" == "Y" ]]; then
  brew unlink python@3.12
fi

# Optionally remove the CRM app itself
read -p "Delete the My_CRM.app directory? (y/N): " DELETE_APP
if [[ "$DELETE_APP" == "y" || "$DELETE_APP" == "Y" ]]; then
  echo "🗑 Deleting application folder..."
  APP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
  rm -rf "$APP_DIR"
fi

echo "✅ Uninstall complete."