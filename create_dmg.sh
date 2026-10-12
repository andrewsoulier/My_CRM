#!/bin/bash
set -e

# My CRM - DMG Creator
# Creates a professional distributable DMG for My CRM

echo "📦 My CRM - DMG Creator"
echo "=============================================="
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Configuration
APP_NAME="My CRM"
APP_BUNDLE="/Applications/My CRM.app"
DMG_NAME="My CRM Installer"
DMG_BASE_NAME="$DMG_NAME"
DMG_PATH=""
TEMP_DMG="$PROJECT_DIR/temp_dmg.dmg"
VOLUME_NAME="My CRM"
DMG_SIZE="100m"

# Check if app exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ Error: My CRM.app not found in /Applications/"
    echo "   Run ./build_app.sh first to build the app"
    exit 1
fi

# Get app version from Info.plist
APP_VERSION=$(defaults read "$APP_BUNDLE/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
echo "📱 App version: $APP_VERSION"

SANITIZED_VERSION=$(printf "%s" "$APP_VERSION" | tr ' ' '_' | tr -cd '[:alnum:]._-' )
if [ -z "$SANITIZED_VERSION" ]; then
    SANITIZED_VERSION="unknown"
fi

if [[ "$SANITIZED_VERSION" == v* ]]; then
    VERSION_SUFFIX="$SANITIZED_VERSION"
else
    VERSION_SUFFIX="v$SANITIZED_VERSION"
fi

DMG_VERSIONED_BASENAME="${DMG_BASE_NAME}_${VERSION_SUFFIX}"
DMG_FILE_NAME="${DMG_VERSIONED_BASENAME}.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_FILE_NAME"

# Create staging directory
STAGING_DIR="$PROJECT_DIR/dmg_staging"
echo "🗂️  Creating staging directory..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy app to staging
echo "📋 Copying My CRM.app to staging..."
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

# Create symlink to Applications folder
echo "🔗 Creating Applications symlink..."
ln -s /Applications "$STAGING_DIR/Applications"

# Create installation helper script
echo "📝 Creating installation helper..."
cat > "$STAGING_DIR/Install My CRM.command" << 'EOF'
#!/bin/bash

# My CRM Installation Helper
# This script removes macOS Gatekeeper quarantine to allow the app to run

echo ""
echo "🚀 My CRM Installation Helper"
echo "================================"
echo ""

APP_PATH="/Applications/My CRM.app"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "❌ My CRM.app not found in /Applications/"
    echo ""
    echo "Please drag My CRM.app to the Applications folder first."
    echo ""
    read -p "Press Enter to exit..."
    exit 1
fi

echo "Found My CRM in Applications ✓"
echo ""
echo "Removing macOS quarantine attribute..."

# Remove quarantine attribute
xattr -cr "$APP_PATH" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Installation complete!"
    echo ""
    echo "You can now:"
    echo "  • Launch My CRM from Applications"
    echo "  • Or press Cmd+Space and type 'My CRM'"
    echo ""
    echo "First-time setup:"
    echo "  • Check the README for features"
    echo "  • Grant Full Disk Access for iMessage integration (optional)"
    echo ""
else
    echo "⚠️  Could not remove quarantine (might not be needed)"
    echo ""
    echo "If the app doesn't open, try:"
    echo "  1. Right-click My CRM.app in Applications"
    echo "  2. Select 'Open' from the menu"
    echo "  3. Click 'Open' in the security dialog"
    echo ""
fi

read -p "Press Enter to exit..."
EOF

chmod +x "$STAGING_DIR/Install My CRM.command"

# Create README for the DMG
echo "📄 Creating README..."
cat > "$STAGING_DIR/README.txt" << 'EOF'
My CRM Installer
================

Welcome to My CRM! Thank you for trying our contact relationship manager.

INSTALLATION INSTRUCTIONS:
==========================

1. Drag "My CRM.app" to the "Applications" folder
2. Double-click "Install My CRM.command" to complete setup
3. Launch My CRM from Applications or Spotlight (Cmd+Space)

FIRST TIME SETUP:
=================

• The app will automatically create its database and settings
• No configuration needed - it just works!
• For iMessage integration, grant Full Disk Access in System Settings

TROUBLESHOOTING:
================

If macOS blocks the app with "can't be opened" warning:

Option 1 (Easiest):
  • Double-click "Install My CRM.command" script

Option 2 (Manual):
  • Right-click My CRM.app → Select "Open" → Click "Open"

Option 3 (Terminal):
  • Open Terminal and run:
    xattr -cr "/Applications/My CRM.app"

SYSTEM REQUIREMENTS:
====================

• macOS 14.0 or later
• ~10 MB disk space
• No Python or other dependencies required!

PRIVACY & DATA:
===============

All your data stays on your Mac. The app accesses:
  • macOS Contacts (to import contacts)
  • iMessage database (only if you grant Full Disk Access)
  • Files you explicitly select

Nothing is sent to the internet except AI features if you configure them.

NEED HELP?
==========

Check the documentation files included in this installer or visit:
• Getting Started Guide (open "GETTING_STARTED.md")
• Full documentation in the app's source

Enjoy organizing your relationships!

---
My CRM v1.0.0
100% Swift, Zero Dependencies, Completely Portable
EOF

# Copy documentation
echo "📚 Copying documentation..."
if [ -f "$PROJECT_DIR/GETTING_STARTED.md" ]; then
    cp "$PROJECT_DIR/GETTING_STARTED.md" "$STAGING_DIR/"
fi

if [ -f "$PROJECT_DIR/DISTRIBUTION_GUIDE.md" ]; then
    cp "$PROJECT_DIR/DISTRIBUTION_GUIDE.md" "$STAGING_DIR/"
fi

if [ -f "$PROJECT_DIR/QUICK_INSTALL_GUIDE.txt" ]; then
    cp "$PROJECT_DIR/QUICK_INSTALL_GUIDE.txt" "$STAGING_DIR/"
fi

# Create a simple background (using folder settings)
echo "🎨 Configuring DMG appearance..."

# Clean up any existing DMG files
echo "🗑️  Cleaning up old DMG files..."
rm -f "$PROJECT_DIR"/"${DMG_BASE_NAME}"_*.dmg "$TEMP_DMG"

# Create temporary DMG
echo "💾 Creating temporary DMG..."
hdiutil create -srcfolder "$STAGING_DIR" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size "$DMG_SIZE" \
    "$TEMP_DMG"

# Mount the DMG
echo "📂 Mounting DMG..."
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG" | egrep '^/dev/' | sed 1q | awk '{print $3}')

echo "🎯 Mounted at: $MOUNT_DIR"

# Wait for mount
sleep 2

# Set up the DMG window appearance using AppleScript
echo "🖼️  Configuring DMG window..."

osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 800, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 72
        set background picture of viewOptions to file ".background:background.png"
        
        -- Position items
        set position of item "My CRM.app" of container window to {150, 140}
        set position of item "Applications" of container window to {500, 140}
        set position of item "README.txt" of container window to {150, 300}
        set position of item "Install My CRM.command" of container window to {500, 300}
        
        -- Hide documentation files from main view but keep them accessible
        if exists item "GETTING_STARTED.md" then
            set position of item "GETTING_STARTED.md" of container window to {300, 500}
        end if
        if exists item "DISTRIBUTION_GUIDE.md" then
            set position of item "DISTRIBUTION_GUIDE.md" of container window to {450, 500}
        end if
        
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

# Give it time to apply settings
sleep 3

# Ensure proper permissions
echo "🔐 Setting permissions..."
chmod -Rf go-w "$MOUNT_DIR" 2>/dev/null || true

# Sync to ensure all changes are written
sync

# Unmount
echo "⏏️  Unmounting DMG..."
hdiutil detach "$MOUNT_DIR" -quiet -force || true

# Wait for unmount
sleep 2

# Convert to compressed read-only DMG
echo "🗜️  Compressing final DMG..."
hdiutil convert "$TEMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH"

# Clean up
echo "🧹 Cleaning up..."
rm -f "$TEMP_DMG"
rm -rf "$STAGING_DIR"

# Get final DMG size
DMG_SIZE_MB=$(du -h "$DMG_PATH" | cut -f1)

echo ""
echo "=============================================="
echo "✅ DMG created successfully!"
echo "=============================================="
echo ""
echo "📦 File: $DMG_FILE_NAME"
echo "📏 Size: $DMG_SIZE_MB"
echo "📍 Location: $PROJECT_DIR"
echo ""
echo "What's included:"
echo "  ✓ My CRM.app"
echo "  ✓ Applications folder shortcut"
echo "  ✓ Installation helper script"
echo "  ✓ README with instructions"
echo "  ✓ Getting Started guide"
echo "  ✓ Distribution documentation"
echo ""
echo "🚀 Distribution Ready!"
echo ""
echo "To distribute:"
echo "  1. Share '$DMG_FILE_NAME' with users"
echo "  2. Users open the DMG"
echo "  3. Users drag My CRM to Applications"
echo "  4. Users run 'Install My CRM.command'"
echo "  5. Done!"
echo ""
echo "Testing:"
echo "  • Open the DMG: open '$DMG_PATH'"
echo "  • Test installation on another Mac"
echo ""

