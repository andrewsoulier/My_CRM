#!/bin/bash
set -e

# My CRM - Simple DMG Creator (No fancy layout)
# Creates a basic DMG for quick distribution

echo "📦 My CRM - Simple DMG Creator"
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
VOLUME_NAME="My CRM"

# Check if app exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ Error: My CRM.app not found in /Applications/"
    echo "   Run ./build_app.sh first to build the app"
    exit 1
fi

# Get app version
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
echo "📋 Copying My CRM.app..."
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

# Create Applications symlink
echo "🔗 Creating Applications symlink..."
ln -s /Applications "$STAGING_DIR/Applications"

# Create helper script
echo "📝 Creating helper script..."
cat > "$STAGING_DIR/Remove Quarantine.command" << 'EOF'
#!/bin/bash
echo "Removing macOS quarantine from My CRM..."
xattr -cr "/Applications/My CRM.app" 2>/dev/null
echo "✅ Done! You can now launch My CRM."
read -p "Press Enter to close..."
EOF
chmod +x "$STAGING_DIR/Remove Quarantine.command"

# Create simple README
cat > "$STAGING_DIR/README.txt" << 'EOF'
My CRM Installer

INSTALLATION:
1. Drag "My CRM.app" to the "Applications" folder
2. Double-click "Remove Quarantine.command"
3. Launch My CRM

If macOS blocks the app, the "Remove Quarantine" script fixes it.

System Requirements: macOS 14.0+
EOF

# Copy docs if available
if [ -f "$PROJECT_DIR/GETTING_STARTED.md" ]; then
    cp "$PROJECT_DIR/GETTING_STARTED.md" "$STAGING_DIR/"
fi

if [ -f "$PROJECT_DIR/QUICK_INSTALL_GUIDE.txt" ]; then
    cp "$PROJECT_DIR/QUICK_INSTALL_GUIDE.txt" "$STAGING_DIR/"
fi

# Remove old DMG
rm -f "$PROJECT_DIR"/"${DMG_BASE_NAME}"_*.dmg

# Create DMG
echo "💾 Creating DMG..."
hdiutil create -srcfolder "$STAGING_DIR" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

# Clean up
rm -rf "$STAGING_DIR"

# Get size
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)

echo ""
echo "=============================================="
echo "✅ DMG created successfully!"
echo "=============================================="
echo ""
echo "📦 File: $DMG_FILE_NAME"
echo "📏 Size: $DMG_SIZE"
echo "📍 Location: $PROJECT_DIR"
echo ""
echo "Ready to distribute! 🚀"
echo ""

