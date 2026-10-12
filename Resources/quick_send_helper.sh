#!/bin/bash

# Quick Send Helper Script
# This script is called by launchd to process scheduled messages

# Get the message ID from the first argument
MESSAGE_ID="$1"

if [ -z "$MESSAGE_ID" ]; then
    echo "Error: No message ID provided"
    exit 1
fi

# Log the execution
echo "$(date): Processing scheduled message: $MESSAGE_ID" >> ~/Library/Logs/MyCRM_QuickSend.log

# Use AppleScript to tell the main app to process the message
osascript -e "
tell application \"My CRM\"
    activate
end tell

tell application \"System Events\"
    tell process \"My CRM\"
        -- Send a custom event to process the scheduled message
        -- This is a simplified approach; in practice you'd use a more robust IPC method
        keystroke \"$MESSAGE_ID\" using {command down, option down, shift down}
    end tell
end tell
" 2>&1 >> ~/Library/Logs/MyCRM_QuickSend.log

# Alternative approach: Use URL scheme or file-based communication
# Create a trigger file that the app monitors
TRIGGER_DIR="$HOME/Library/Application Support/My_CRM/Triggers"
mkdir -p "$TRIGGER_DIR"
echo "$MESSAGE_ID" > "$TRIGGER_DIR/scheduled_message_$(date +%s).trigger"

echo "$(date): Trigger file created for message: $MESSAGE_ID" >> ~/Library/Logs/MyCRM_QuickSend.log

