#!/bin/bash
set -e

# Check if build description is provided
if [ $# -eq 0 ]; then
    echo "❌ Error: Build description is required"
    echo "Usage: $0 \"Build description (5-10 words)\" [options]"
    echo "Example: $0 \"New debug mouse point correction\""
    echo ""
    echo "Options:"
    echo "  --clean              Force full rebuild (removes .build directory)"
    echo "  --with-dmg           Create DMG installer"
    echo "  --with-archive       Create project archive"
    echo "  --deploy-remote      Deploy to remote computers"
    echo "  --verify             Run distribution verification"
    echo "  --health-check       Run post-launch health checks"
    echo "  --jobs N             Number of parallel jobs (default: CPU count)"
    exit 1
fi

BUILD_DESCRIPTION="$1"
shift

# Parse optional flags
CLEAN_BUILD=false
CREATE_DMG=false
CREATE_ARCHIVE=false
DEPLOY_REMOTE=false
RUN_VERIFY=false
RUN_HEALTH_CHECK=false
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo "4")

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --with-dmg)
            CREATE_DMG=true
            shift
            ;;
        --with-archive)
            CREATE_ARCHIVE=true
            shift
            ;;
        --deploy-remote)
            DEPLOY_REMOTE=true
            shift
            ;;
        --verify)
            RUN_VERIFY=true
            shift
            ;;
        --health-check)
            RUN_HEALTH_CHECK=true
            shift
            ;;
        --jobs)
            JOBS="$2"
            shift 2
            ;;
        *)
            echo "⚠️  Unknown option: $1"
            shift
            ;;
    esac
done

echo "🏗️ Building My CRM App Bundle with description: '$BUILD_DESCRIPTION'..."
if [ "$CLEAN_BUILD" = true ]; then
    echo "   🔄 Clean build enabled (will remove .build directory)"
fi
if [ "$CREATE_DMG" = true ]; then
    echo "   📦 DMG creation enabled"
fi
if [ "$CREATE_ARCHIVE" = true ]; then
    echo "   📁 Archive creation enabled"
fi
if [ "$DEPLOY_REMOTE" = true ]; then
    echo "   🌐 Remote deployment enabled"
fi
echo "   ⚡ Parallel jobs: $JOBS"

# ------------------------------------------------------------------------------
# Deployment Configuration
# ------------------------------------------------------------------------------

# Shared SSH options
SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
SSH_OPTIONS="-o ConnectTimeout=5 -o StrictHostKeyChecking=no"

# Computer list: label|host|user|password|app_path
# Add additional remote machines here as needed.
REMOTE_COMPUTERS=(
    "Fuji Remote|andreassoul-fuji.nord|andrewsoulier|28VP04!!|/Applications/My CRM.app"
)

LOCAL_LABEL="Local Mac"
LOCAL_APP_PATH="/Applications/My CRM.app"
LOCAL_LOG_PATH="$HOME/Library/Logs/My CRM"

# Process termination script reused for remote hosts
MYCRM_KILL_SCRIPT=$'pkill -f -i "my.?crm" 2>/dev/null || true\npkill -f -i "my_crm" 2>/dev/null || true\npkill -f -i "mycrm" 2>/dev/null || true\npkill -f "com.mycrm.app" 2>/dev/null || true\npkill -f "/Applications/My CRM.app" 2>/dev/null || true\npkill -f "My CRM.app" 2>/dev/null || true\nsleep 2\npkill -9 -f -i "my.?crm" 2>/dev/null || true\npkill -9 -f -i "my_crm" 2>/dev/null || true\npkill -9 -f -i "mycrm" 2>/dev/null || true\npkill -9 -f "com.mycrm.app" 2>/dev/null || true\npkill -9 -f "/Applications/My CRM.app" 2>/dev/null || true\npkill -9 -f "My CRM.app" 2>/dev/null || true\n'

REMOTE_LOG_SCAN_SCRIPT=$'log show --last 2m --style syslog --predicate \'process == "My CRM"\' --info --debug 2>/dev/null | grep -v -i "jump.*desktop" | egrep -i \'error|fault|critical\''
REMOTE_CPU_SNAPSHOT_SCRIPT=$'ps -Ao pid,%cpu,command | grep -i \'[M]y CRM\''

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

run_remote_script_with_auth() {
    local host="$1"
    local user="$2"
    local password="$3"
    local script="$4"

    local success=1

    if [ -f "$SSH_KEY_PATH" ]; then
        if ssh -i "$SSH_KEY_PATH" $SSH_OPTIONS -o BatchMode=yes "$user@$host" 'bash -s' <<< "$script" 2>/dev/null; then
            success=0
        fi
    fi

    if [ $success -ne 0 ] && command -v sshpass &> /dev/null && [ -n "$password" ]; then
        if sshpass -p "$password" ssh $SSH_OPTIONS "$user@$host" 'bash -s' <<< "$script" 2>/dev/null; then
            success=0
        fi
    fi

    return $success
}

run_remote_script_capture_exit() {
    local host="$1"
    local user="$2"
    local password="$3"
    local script="$4"

    local output=""
    local exit_code=255

    set +e
    if [ -f "$SSH_KEY_PATH" ]; then
        output=$(ssh -i "$SSH_KEY_PATH" $SSH_OPTIONS -o BatchMode=yes "$user@$host" 'bash -s' <<< "$script" 2>/dev/null)
        exit_code=$?
    fi

    if { [ $exit_code -eq 255 ] || [ $exit_code -eq 126 ] || [ $exit_code -eq 127 ]; } && command -v sshpass &> /dev/null && [ -n "$password" ]; then
        output=$(sshpass -p "$password" ssh $SSH_OPTIONS "$user@$host" 'bash -s' <<< "$script" 2>/dev/null)
        exit_code=$?
    fi
    set -e

    printf '%s' "$output"
    return $exit_code
}

copy_app_to_remote() {
    local host="$1"
    local user="$2"
    local password="$3"
    local destination_path="$4"

    local temp_archive
    temp_archive=$(mktemp "/tmp/mycrm_app_XXXXXX.tar.gz")
    local success=1

    tar -czf "$temp_archive" -C "$(dirname "$APP_BUNDLE")" "$(basename "$APP_BUNDLE")"

    local destination_parent
    destination_parent=$(dirname "$destination_path")

    if [ -f "$SSH_KEY_PATH" ]; then
        if cat "$temp_archive" | ssh -i "$SSH_KEY_PATH" $SSH_OPTIONS -o BatchMode=yes "$user@$host" "mkdir -p \"$destination_parent\" && rm -rf \"$destination_path\" && tar -xzf - -C \"$destination_parent\"" 2>/dev/null; then
            success=0
        fi
    fi

    if [ $success -ne 0 ] && command -v sshpass &> /dev/null && [ -n "$password" ]; then
        if cat "$temp_archive" | sshpass -p "$password" ssh $SSH_OPTIONS "$user@$host" "mkdir -p \"$destination_parent\" && rm -rf \"$destination_path\" && tar -xzf - -C \"$destination_parent\"" 2>/dev/null; then
            success=0
        fi
    fi

    rm -f "$temp_archive"
    return $success
}

# Kill all processes related to My_CRM first
echo "🛑 Killing all My_CRM related processes on LOCAL computer..."
# Kill processes by name (case insensitive)
pkill -f -i "my.?crm" 2>/dev/null || true
pkill -f -i "my_crm" 2>/dev/null || true
pkill -f -i "mycrm" 2>/dev/null || true

# Kill processes by bundle identifier
pkill -f "com.mycrm.app" 2>/dev/null || true

# Kill any processes that might be running the app bundle
pkill -f "/Applications/My CRM.app" 2>/dev/null || true
pkill -f "My CRM.app" 2>/dev/null || true

# Give processes a moment to terminate gracefully
sleep 2

# Force kill any remaining processes if they exist
pkill -9 -f -i "my.?crm" 2>/dev/null || true
pkill -9 -f -i "my_crm" 2>/dev/null || true
pkill -9 -f -i "mycrm" 2>/dev/null || true
pkill -9 -f "com.mycrm.app" 2>/dev/null || true
pkill -9 -f "/Applications/My CRM.app" 2>/dev/null || true
pkill -9 -f "My CRM.app" 2>/dev/null || true

echo "✅ Local My_CRM processes terminated"

if [ ${#REMOTE_COMPUTERS[@]} -gt 0 ]; then
    echo "🌐 Killing all My_CRM related processes on configured remote computers..."
    for remote_entry in "${REMOTE_COMPUTERS[@]}"; do
        IFS="|" read -r REMOTE_LABEL REMOTE_HOST REMOTE_USER REMOTE_PASS REMOTE_APP_PATH <<< "$remote_entry"
        echo "   ➤ $REMOTE_LABEL ($REMOTE_HOST)"
        if run_remote_script_with_auth "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_PASS" "$MYCRM_KILL_SCRIPT"; then
            echo "      ✅ Remote My_CRM processes terminated on $REMOTE_LABEL"
        else
            echo "      ⚠️  Could not connect to $REMOTE_LABEL"
            echo "         • Verify the machine is online and reachable"
            echo "         • Ensure SSH keys or passwords are correct"
        fi
    done
else
    echo "ℹ️  No remote computers configured for this build."
fi

echo "✅ My_CRM processes terminated on all configured computers (local + remote)"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Clean dmg_staging before build to prevent SPM from scanning it
if [ -d "$PROJECT_DIR/dmg_staging" ]; then
    echo "🧹 Cleaning dmg_staging directory before build..."
    rm -rf "$PROJECT_DIR/dmg_staging" 2>/dev/null || true
fi

# Create build directory
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/My CRM.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Check if we have Swift Package Manager
if ! command -v swift &> /dev/null; then
    echo "❌ Swift not found. Please install Xcode or Xcode command line tools."
    exit 1
fi

# Build using Swift Package Manager
echo "🔨 Building with Swift Package Manager..."
cd "$PROJECT_DIR"

# Clean previous builds only if --clean flag is set
if [ "$CLEAN_BUILD" = true ]; then
    echo "🧹 Removing .build directory for clean build..."
    rm -rf .build 2>/dev/null || true
else
    echo "⚡ Using incremental build (use --clean for full rebuild)..."
fi

# Build the app with parallel compilation
echo "⚡ Building with $JOBS parallel jobs..."
swift build -c release --jobs "$JOBS"

# Get the path to the built executable
EXECUTABLE_PATH=".build/release/My CRM"
if [ ! -f "$EXECUTABLE_PATH" ]; then
    EXECUTABLE_PATH=$(find .build -path "*/release/My CRM" -type f 2>/dev/null | head -1)
fi

# Check if build was successful
if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "❌ Build failed - executable not found at $EXECUTABLE_PATH"
    exit 1
fi

echo "✅ Swift Package Manager build successful"

# Create app bundle structure
echo "📦 Creating app bundle structure..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy the built executable
echo "📱 Copying executable..."
cp "$EXECUTABLE_PATH" "$MACOS_DIR/My CRM"
chmod +x "$MACOS_DIR/My CRM"

# Copy Info.plist
echo "📄 Copying Info.plist..."
if [ -f "$PROJECT_DIR/App/Info.plist" ]; then
    cp "$PROJECT_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
    echo "✅ Info.plist copied from App directory"
else
    echo "⚠️ App/Info.plist not found, creating default Info.plist..."
    cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>My CRM</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.andrewsoulier.mycrm</string>
	<key>CFBundleName</key>
	<string>My CRM</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSUserNotificationAlertStyle</key>
	<string>alert</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
</dict>
</plist>
EOF
fi

# Create PkgInfo
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Copy the iMessage Server Scraper resources if they exist (excluding Python scripts)
echo "📁 Copying iMessage Server Scraper resources (Swift-only, excluding Python)..."
if [ -d "$PROJECT_DIR/App/Feature Groups/iMessage Server Scraper" ]; then
    # Create directory structure
    mkdir -p "$RESOURCES_DIR/Feature Groups/iMessage Server Scraper/MacOS"
    mkdir -p "$RESOURCES_DIR/Feature Groups/iMessage Server Scraper/Resources"
    
    # Copy MacOS shell scripts (keep these for optional features)
    if [ -d "$PROJECT_DIR/App/Feature Groups/iMessage Server Scraper/MacOS" ]; then
        cp "$PROJECT_DIR/App/Feature Groups/iMessage Server Scraper/MacOS/"*.sh "$RESOURCES_DIR/Feature Groups/iMessage Server Scraper/MacOS/" 2>/dev/null || true
        cp "$PROJECT_DIR/App/Feature Groups/iMessage Server Scraper/MacOS/"*.plist "$RESOURCES_DIR/Feature Groups/iMessage Server Scraper/MacOS/" 2>/dev/null || true
        
        # Make shell scripts executable
        chmod +x "$RESOURCES_DIR/Feature Groups/iMessage Server Scraper/MacOS/"*.sh 2>/dev/null || true
        echo "✅ Shell scripts copied and made executable"
    fi
    
    # Copy ONLY non-Python resources (excluding all .py files)
    if [ -d "$PROJECT_DIR/App/Feature Groups/iMessage Server Scraper/Resources" ]; then
        # Copy specific file types we want (excluding .py, .pyc, __pycache__)
        find "$PROJECT_DIR/App/Feature Groups/iMessage Server Scraper/Resources" -type f \
            ! -name "*.py" \
            ! -name "*.pyc" \
            ! -path "*__pycache__*" \
            ! -path "*Archive*" \
            ! -name "requirements.txt" \
            ! -name "*-- Old --*" \
            -exec cp --parents {} "$RESOURCES_DIR/" 2>/dev/null \; || true
        
        echo "✅ Resources copied (Python scripts excluded for portability)"
        echo "   📊 Python scripts excluded: *.py, *.pyc, requirements.txt, -- Old -- files"
    fi
    
    echo "✅ iMessage Server Scraper resources copied (Swift-only build)"
    
    # Verify shell scripts copied successfully
    echo "🔍 Verifying resource copy..."
    if [ -f "$RESOURCES_DIR/Feature Groups/iMessage Server Scraper/MacOS/Launch_Server.sh" ]; then
        echo "✅ Launch_Server.sh verified in bundle"
    else
        echo "⚠️ Launch_Server.sh not found in bundle (optional feature)"
    fi
    
    # Confirm Python scripts excluded
    PYTHON_COUNT=$(find "$RESOURCES_DIR/Feature Groups/iMessage Server Scraper" -name "*.py" 2>/dev/null | wc -l)
    if [ "$PYTHON_COUNT" -eq 0 ]; then
        echo "✅ Confirmed: No Python scripts in app bundle (100% Swift)"
    else
        echo "⚠️ Warning: $PYTHON_COUNT Python files still in bundle"
    fi
else
    echo "⚠️ iMessage Server Scraper resources not found"
fi

# Copy Assets.xcassets if they exist
echo "🎨 Copying Assets.xcassets..."
if [ -d "$PROJECT_DIR/Resources/Assets.xcassets" ]; then
    mkdir -p "$RESOURCES_DIR/Assets.xcassets"
    cp -r "$PROJECT_DIR/Resources/Assets.xcassets/"* "$RESOURCES_DIR/Assets.xcassets/"
    echo "✅ Assets.xcassets copied successfully"
else
    echo "⚠️ Assets.xcassets not found"
fi

# Create AppIcon.icns from asset catalog
echo "🎨 Creating AppIcon.icns..."
if [ -d "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset" ]; then
    # Create temporary iconset directory
    TEMP_ICONSET="$PROJECT_DIR/temp_app_iconset.iconset"
    mkdir -p "$TEMP_ICONSET"
    
    # Copy and rename icon files to proper iconset format
    cp "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset/icon_16.png" "$TEMP_ICONSET/icon_16x16.png"
    cp "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset/icon_32.png" "$TEMP_ICONSET/icon_16x16@2x.png"
    cp "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset/icon_32.png" "$TEMP_ICONSET/icon_32x32.png"
    cp "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset/icon_32@2x.png" "$TEMP_ICONSET/icon_32x32@2x.png"
    cp "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset/icon_128.png" "$TEMP_ICONSET/icon_128x128.png"
    cp "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset/icon_128@2x.png" "$TEMP_ICONSET/icon_128x128@2x.png"
    cp "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset/icon_256.png" "$TEMP_ICONSET/icon_256x256.png"
    cp "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset/icon_256@2x.png" "$TEMP_ICONSET/icon_256x256@2x.png"
    cp "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset/icon_512.png" "$TEMP_ICONSET/icon_512x512.png"
    cp "$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset/icon_512@2x.png" "$TEMP_ICONSET/icon_512x512@2x.png"
    
    # Create .icns file
    iconutil -c icns "$TEMP_ICONSET"
    cp "$PROJECT_DIR/temp_app_iconset.icns" "$RESOURCES_DIR/AppIcon.icns"
    
    # Clean up
    rm -rf "$TEMP_ICONSET" "$PROJECT_DIR/temp_app_iconset.icns"
    echo "✅ AppIcon.icns created successfully"
else
    echo "⚠️ AppIcon.appiconset not found"
fi

# Create StatusBarIcon.icns from asset catalog
echo "🎨 Creating StatusBarIcon.icns..."
if [ -d "$PROJECT_DIR/Resources/Assets.xcassets/StatusBarIcon.imageset" ]; then
    # Create temporary iconset directory
    TEMP_STATUSBAR_ICONSET="$PROJECT_DIR/temp_statusbar_iconset.iconset"
    mkdir -p "$TEMP_STATUSBAR_ICONSET"
    
    # Copy and rename icon files to proper iconset format
    cp "$PROJECT_DIR/Resources/Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon16.png" "$TEMP_STATUSBAR_ICONSET/icon_16x16.png"
    cp "$PROJECT_DIR/Resources/Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon32.png" "$TEMP_STATUSBAR_ICONSET/icon_16x16@2x.png"
    cp "$PROJECT_DIR/Resources/Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon32.png" "$TEMP_STATUSBAR_ICONSET/icon_32x32.png"
    cp "$PROJECT_DIR/Resources/Assets.xcassets/StatusBarIcon.imageset/StatusBarIcon64.png" "$TEMP_STATUSBAR_ICONSET/icon_32x32@2x.png"
    
    # Create .icns file
    iconutil -c icns "$TEMP_STATUSBAR_ICONSET"
    cp "$PROJECT_DIR/temp_statusbar_iconset.icns" "$RESOURCES_DIR/StatusBarIcon.icns"
    
    # Clean up
    rm -rf "$TEMP_STATUSBAR_ICONSET" "$PROJECT_DIR/temp_statusbar_iconset.icns"
    echo "✅ StatusBarIcon.icns created successfully"
else
    echo "⚠️ StatusBarIcon.imageset not found"
fi

# Copy any other resources
echo "📁 Copying additional resources..."
if [ -d "$PROJECT_DIR/Resources" ]; then
    cp -r "$PROJECT_DIR/Resources/"* "$RESOURCES_DIR/" 2>/dev/null || true
    
    # Make sure the Quick Send helper script is executable
    if [ -f "$RESOURCES_DIR/quick_send_helper.sh" ]; then
        chmod +x "$RESOURCES_DIR/quick_send_helper.sh"
        echo "✅ Quick Send helper script made executable"
    fi
fi

echo "✅ App bundle created at: $APP_BUNDLE"

# Sign the app BEFORE copying (sign once, copy many)
echo "🔐 Setting up consistent code signing for Full Disk Access..."
SIGNING_IDENTITY=""
SIGN_SUCCESS=false

# Try to find an existing signing identity
if command -v security &> /dev/null; then
    # Look for Developer ID Application first
    DEVELOPER_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}')
    if [ -n "$DEVELOPER_ID" ]; then
        SIGNING_IDENTITY="$DEVELOPER_ID"
        echo "📜 Found Developer ID: $DEVELOPER_ID"
    else
        # Look for Mac Developer
        MAC_DEV_ID=$(security find-identity -v -p codesigning | grep "Mac Developer" | head -1 | awk '{print $2}')
        if [ -n "$MAC_DEV_ID" ]; then
            SIGNING_IDENTITY="$MAC_DEV_ID"
            echo "📜 Found Mac Developer ID: $MAC_DEV_ID"
        else
            # Look for Apple Development certificate
            APPLE_DEV_ID=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk '{print $2}')
            if [ -n "$APPLE_DEV_ID" ]; then
                SIGNING_IDENTITY="$APPLE_DEV_ID"
                echo "📜 Found Apple Development ID: $APPLE_DEV_ID"
            fi
        fi
    fi
fi

# Sign the app bundle if we have an identity
if [ -n "$SIGNING_IDENTITY" ]; then
    echo "🔏 Signing app bundle with: $SIGNING_IDENTITY"
    echo "   Using entitlements: $PROJECT_DIR/My CRM/My_CRM.entitlements"
    
    # Remove extended attributes that might interfere with signing
    xattr -cr "$APP_BUNDLE" 2>/dev/null
    
    # Sign the app bundle with entitlements
    codesign --force --sign "$SIGNING_IDENTITY" \
        --entitlements "$PROJECT_DIR/My CRM/My_CRM.entitlements" \
        --timestamp \
        --options runtime \
        "$APP_BUNDLE" 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✅ App bundle signed successfully with entitlements"
        SIGN_SUCCESS=true
        
        # Verify the signature
        echo "🔍 Verifying code signature..."
        codesign -dv "$APP_BUNDLE" 2>&1 | grep -E "(Identifier|Authority|TeamIdentifier)" | head -3
    else
        echo "⚠️ App signing failed - trying without runtime option..."
        # Try again without runtime option
        codesign --force --sign "$SIGNING_IDENTITY" \
            --entitlements "$PROJECT_DIR/My CRM/My_CRM.entitlements" \
            "$APP_BUNDLE" 2>&1
        
        if [ $? -eq 0 ]; then
            echo "✅ App bundle signed successfully (without runtime hardening)"
            SIGN_SUCCESS=true
        else
            echo "⚠️ Code signing failed - permissions may reset on each build"
        fi
    fi
else
    echo "⚠️ No code signing identity found"
    echo "   To preserve Full Disk Access across builds:"
    echo "   1. Get a Developer ID from Apple ($99/year)"
    echo "   2. Use Xcode to sign with your Apple ID (free)"
    echo "   3. Current builds will work but FDA will need re-setup"
fi

# Now copy the signed app to both locations
# Remove existing app from Applications if it exists
if [ -d "/Applications/My CRM.app" ]; then
    echo "🗑️ Removing existing app from /Applications/..."
    rm -rf "/Applications/My CRM.app"
fi

# Copy to Applications folder
echo "📋 Copying signed app to /Applications/..."
cp -r "$APP_BUNDLE" "/Applications/"
echo "✅ App copied to /Applications/My CRM.app"

# Copy to external Applications folder if available
EXTERNAL_APPS_PATH="/Volumes/Data/Applications"
if [ -d "$EXTERNAL_APPS_PATH" ]; then
    echo "📁 External Applications folder available..."
    
    # Remove existing app from external Applications if it exists
    if [ -d "$EXTERNAL_APPS_PATH/My CRM.app" ]; then
        echo "🗑️  Removing existing app from external Applications..."
        rm -rf "$EXTERNAL_APPS_PATH/My CRM.app" 2>/dev/null || {
            echo "⚠️  Could not remove old app from external path (permissions)"
            echo "   Continuing with build anyway..."
        }
    fi
    
    # Copy to external Applications folder (don't fail if this doesn't work)
    echo "📋 Copying signed app to external Applications..."
    if cp -r "$APP_BUNDLE" "$EXTERNAL_APPS_PATH/" 2>/dev/null; then
        echo "✅ App copied to $EXTERNAL_APPS_PATH/My CRM.app"
    else
        echo "⚠️  Failed to copy to external Applications (check permissions)"
        echo "   Local installation in /Applications is complete"
    fi
else
    echo "ℹ️  External Applications folder not available: $EXTERNAL_APPS_PATH"
    echo "   (Skipping external copy - local installation complete)"
fi

if [ "$DEPLOY_REMOTE" = true ] && [ ${#REMOTE_COMPUTERS[@]} -gt 0 ]; then
    echo ""
    echo "🚚 Deploying My CRM.app to remote computers..."
    for remote_entry in "${REMOTE_COMPUTERS[@]}"; do
        IFS="|" read -r REMOTE_LABEL REMOTE_HOST REMOTE_USER REMOTE_PASS REMOTE_APP_PATH <<< "$remote_entry"
        echo "   ➤ Deploying to $REMOTE_LABEL ($REMOTE_HOST)..."
        if copy_app_to_remote "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_PASS" "$REMOTE_APP_PATH"; then
            echo "      ✅ Deployment completed for $REMOTE_LABEL"
        else
            echo "      ⚠️  Deployment failed for $REMOTE_LABEL"
            echo "         • Confirm SSH access is available"
            echo "         • Verify destination path: $REMOTE_APP_PATH"
        fi
    done
elif [ ${#REMOTE_COMPUTERS[@]} -gt 0 ]; then
    echo "ℹ️  Remote deployment skipped (use --deploy-remote to enable)"
fi

if [ "$SIGN_SUCCESS" = true ]; then
    echo ""
    echo "✅ Code signing complete - Full Disk Access should persist across builds"
    echo "   Bundle ID: com.andrewsoulier.mycrm"
fi

# Create project archive (conditional)
if [ "$CREATE_ARCHIVE" = true ]; then
    echo "📦 Creating project archive..."
    ARCHIVE_DIR="/Users/andrewsoulier/My_CRM Project/Working Files, not part of app/Project Archives"
    TIMESTAMP=$(date +"%Y_%m_%d")
    ARCHIVE_NAME="${TIMESTAMP} ${BUILD_DESCRIPTION}"
    ARCHIVE_PATH="${ARCHIVE_DIR}/${ARCHIVE_NAME}"

    # Create archive directory if it doesn't exist
    mkdir -p "$ARCHIVE_DIR"

    # Create the archive (excluding build artifacts and temporary files)
    echo "🗜️ Archiving project to: $ARCHIVE_PATH"
    cd "$PROJECT_DIR"
    tar --exclude='.build' \
        --exclude='build' \
        --exclude='dmg_staging' \
        --exclude='*.zip' \
        --exclude='.git' \
        --exclude='node_modules' \
        --exclude='*.log' \
        --exclude='temp_*' \
        --exclude='*.tmp' \
        -czf "${ARCHIVE_PATH}.tar.gz" .

    echo "✅ Project archived as: ${ARCHIVE_NAME}.tar.gz"
else
    echo "ℹ️  Project archiving skipped (use --with-archive to enable)"
fi

# Make setup_permissions.sh executable
echo "🔐 Setting up permission automation..."
chmod +x "$PROJECT_DIR/setup_permissions.sh"

echo ""
echo "=============================================="
echo "🎉 Build complete! My CRM.app is now installed in /Applications/"
echo "=============================================="
echo ""

# Run distribution verification (conditional)
if [ "$RUN_VERIFY" = true ]; then
    echo "🔍 Running distribution verification..."
    if [ -f "$PROJECT_DIR/verify_distribution.sh" ]; then
        chmod +x "$PROJECT_DIR/verify_distribution.sh"
        "$PROJECT_DIR/verify_distribution.sh"
        VERIFY_RESULT=$?
        if [ $VERIFY_RESULT -ne 0 ]; then
            echo ""
            echo "⚠️  Some verification checks failed. Review above."
            echo "    The app will still work, but may not be optimal for distribution."
        fi
    else
        echo "⚠️  verify_distribution.sh not found - skipping verification"
    fi
else
    echo "ℹ️  Distribution verification skipped (use --verify to enable)"
fi

echo ""
echo "🚀 You can now launch the app from Applications or Spotlight!"
echo ""

# Create DMG installer automatically (conditional)
if [ "$CREATE_DMG" = true ]; then
    echo "=============================================="
    echo "📦 Creating DMG Installer..."
    echo "=============================================="
    echo ""

DMG_BASE_NAME="My CRM Installer"

# Determine app version for DMG naming
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true)
if [ -z "$APP_VERSION" ]; then
    APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$CONTENTS_DIR/Info.plist" 2>/dev/null || true)
fi
if [ -z "$APP_VERSION" ]; then
    APP_VERSION="unknown"
fi

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
GOOGLE_DRIVE_PATH="/Users/andrewsoulier/Library/CloudStorage/GoogleDrive-soulier.studios@gmail.com"
PROJECT_ROOT="/Users/andrewsoulier/My_CRM Project"

# Create DMG staging directory
DMG_STAGING="$PROJECT_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Copy app to staging
echo "📋 Copying My CRM.app to DMG staging..."
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

# Create Applications symlink
echo "🔗 Creating Applications symlink..."
ln -s /Applications "$DMG_STAGING/Applications"

# Create helper script
echo "📝 Creating quarantine removal helper..."
cat > "$DMG_STAGING/Remove Quarantine.command" << 'DMGEOF'
#!/bin/bash
echo ""
echo "🚀 My CRM Installation Helper"
echo "================================"
echo ""

APP_PATH="/Applications/My CRM.app"

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

xattr -cr "$APP_PATH" 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ Installation complete!"
    echo ""
    echo "You can now launch My CRM from Applications or Spotlight!"
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
DMGEOF

chmod +x "$DMG_STAGING/Remove Quarantine.command"

# Create README
cat > "$DMG_STAGING/README.txt" << 'DMGEOF'
My CRM Installer

INSTALLATION:
1. Drag "My CRM.app" to the "Applications" folder
2. Double-click "Remove Quarantine.command"
3. Launch My CRM

If macOS blocks the app, the "Remove Quarantine" script fixes it.

System Requirements: macOS 14.0+
DMGEOF

# Copy documentation
if [ -f "$PROJECT_DIR/GETTING_STARTED.md" ]; then
    cp "$PROJECT_DIR/GETTING_STARTED.md" "$DMG_STAGING/"
fi

if [ -f "$PROJECT_DIR/QUICK_INSTALL_GUIDE.txt" ]; then
    cp "$PROJECT_DIR/QUICK_INSTALL_GUIDE.txt" "$DMG_STAGING/"
fi

# Remove old DMG (forcefully, even if mounted)
echo "🗑️ Removing old DMG files..."
rm -f "$DMG_PATH"
rm -f "$PROJECT_ROOT/${DMG_BASE_NAME}_"*.dmg

# Unmount any existing DMG volumes
echo "🔓 Checking for mounted DMG volumes..."
hdiutil detach "/Volumes/My CRM" 2>/dev/null || true

# Create DMG with verbose error reporting
echo "💾 Creating DMG..."
DMG_CREATE_OUTPUT=$(hdiutil create -srcfolder "$DMG_STAGING" \
    -volname "My CRM" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH" 2>&1)

if [ $? -eq 0 ]; then
    DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
    echo "✅ DMG created successfully! (Size: $DMG_SIZE)"
    
    # Copy to project root
    echo "📦 Copying DMG to project root..."
    cp -f "$DMG_PATH" "$PROJECT_ROOT/$DMG_FILE_NAME"
    if [ $? -eq 0 ]; then
        echo "✅ DMG copied to project root: $PROJECT_ROOT/$DMG_FILE_NAME"
    else
        echo "⚠️  Failed to copy DMG to project root"
    fi
    
    # Copy to cloud/network storage with timestamp
    # Try primary path first, fall back to Google Drive
    PRIMARY_DMG_PATH="/Volumes/andrewsoulier/Documents/MY_CRM"
    CLOUD_COPY_SUCCESS=false
    CLOUD_COPY_LOCATION=""
    
    # Create timestamped DMG name
    TIMESTAMP=$(date +"%Y_%m_%d_%H_%M_%S")
    DMG_TIMESTAMPED_NAME="${DMG_BASE_NAME}_${TIMESTAMP}_${VERSION_SUFFIX}.dmg"
    
    # Try primary path first
    if [ -d "$PRIMARY_DMG_PATH" ]; then
        echo "📁 Primary storage path available..."
        echo "🗑️  Removing old DMG files from primary storage..."
        rm -f "$PRIMARY_DMG_PATH/${DMG_BASE_NAME}_"*.dmg 2>/dev/null || true
        
        # Copy to primary path with timestamp
        cp -f "$DMG_PATH" "$PRIMARY_DMG_PATH/$DMG_TIMESTAMPED_NAME"
        if [ $? -eq 0 ]; then
            echo "✅ DMG copied to primary storage successfully!"
            echo "   Location: /Volumes/andrewsoulier/Documents/MY_CRM"
            echo "   Filename: $DMG_TIMESTAMPED_NAME"
            CLOUD_COPY_SUCCESS=true
            CLOUD_COPY_LOCATION="$PRIMARY_DMG_PATH/$DMG_TIMESTAMPED_NAME"
        else
            echo "⚠️  Failed to copy to primary storage, trying fallback..."
        fi
    else
        echo "⚠️  Primary storage path not available: $PRIMARY_DMG_PATH"
        echo "   Trying fallback to Google Drive..."
    fi
    
    # If primary path failed or unavailable, try Google Drive
    if [ "$CLOUD_COPY_SUCCESS" = false ] && [ -d "$GOOGLE_DRIVE_PATH" ]; then
        echo "☁️  Preparing DMG for Google Drive (fallback)..."
        
        # Delete old DMG files in Google Drive
        echo "🗑️  Removing old DMG files from Google Drive..."
        rm -f "$GOOGLE_DRIVE_PATH/${DMG_BASE_NAME}_"*.dmg 2>/dev/null || true
        
        # Copy to Google Drive with timestamp
        cp -f "$DMG_PATH" "$GOOGLE_DRIVE_PATH/$DMG_TIMESTAMPED_NAME"
        if [ $? -eq 0 ]; then
            echo "✅ DMG copied to Google Drive successfully!"
            echo "   Filename: $DMG_TIMESTAMPED_NAME"
            CLOUD_COPY_SUCCESS=true
            CLOUD_COPY_LOCATION="$GOOGLE_DRIVE_PATH/$DMG_TIMESTAMPED_NAME"
        else
            echo "⚠️  Failed to copy to Google Drive (check permissions)"
        fi
    elif [ "$CLOUD_COPY_SUCCESS" = false ]; then
        echo "⚠️  Google Drive path also not found - no cloud copy made"
        echo "   Path: $GOOGLE_DRIVE_PATH"
    fi
    
    echo ""
    echo "DMG Locations:"
    echo "  • Build directory: $DMG_PATH"
    echo "  • Project root:    $PROJECT_ROOT/$DMG_FILE_NAME"
    if [ "$CLOUD_COPY_SUCCESS" = true ]; then
        echo "  • Cloud storage:   $CLOUD_COPY_LOCATION"
    fi
else
    echo "❌ Failed to create DMG"
    echo "Error details:"
    echo "$DMG_CREATE_OUTPUT"
    echo ""
    echo "Common causes:"
    echo "  • DMG file is still mounted - unmounting now..."
    hdiutil detach "/Volumes/My CRM" -force 2>/dev/null || true
    echo "  • Insufficient disk space"
    echo "  • Permission issues with build directory"
    echo "  • Corrupted staging directory"
    echo ""
    echo "You can try running the build again after the unmount."
fi

    # Clean up
    rm -rf "$DMG_STAGING"
else
    echo "ℹ️  DMG creation skipped (use --with-dmg to enable)"
fi

echo ""
echo "🚀 Launching My CRM on configured computers..."

LAUNCHED_LOCAL=false
if open "$LOCAL_APP_PATH" >/dev/null 2>&1; then
    echo "✅ Launched on $LOCAL_LABEL"
    LAUNCHED_LOCAL=true
else
    echo "⚠️  Failed to launch on $LOCAL_LABEL at $LOCAL_APP_PATH"
fi

if [ ${#REMOTE_COMPUTERS[@]} -gt 0 ]; then
    for remote_entry in "${REMOTE_COMPUTERS[@]}"; do
        IFS="|" read -r REMOTE_LABEL REMOTE_HOST REMOTE_USER REMOTE_PASS REMOTE_APP_PATH <<< "$remote_entry"
        REMOTE_LAUNCH_SCRIPT="open \"${REMOTE_APP_PATH//\"/\\\"}\""
        if run_remote_script_with_auth "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_PASS" "$REMOTE_LAUNCH_SCRIPT"; then
            echo "✅ Launched on $REMOTE_LABEL"
        else
            echo "⚠️  Failed to launch on $REMOTE_LABEL"
        fi
    done
fi

if [ "$RUN_HEALTH_CHECK" = true ]; then
    echo "⏳ Waiting 5 seconds for applications to initialize..."
    sleep 5

    echo ""
    echo "🩺 Post-launch health checks (logs & CPU)..."

    LOCAL_CPU_OUTPUT=$(ps -Ao pid,%cpu,command | grep -i '[M]y CRM' || true)
    if [ -n "$LOCAL_CPU_OUTPUT" ]; then
        echo "   • $LOCAL_LABEL CPU snapshot:"
        printf '%s\n' "$LOCAL_CPU_OUTPUT" | sed 's/^/     /'
    else
        echo "   • ⚠️  $LOCAL_LABEL process not detected in CPU snapshot"
    fi

    LOCAL_LOG_ERRORS=$(log show --last 2m --style syslog --predicate 'process == "My CRM"' --info --debug 2>/dev/null | grep -v -i "jump.*desktop" | egrep -i 'error|fault|critical' || true)
    if [ -n "$LOCAL_LOG_ERRORS" ]; then
        echo "   • ⚠️  $LOCAL_LABEL log findings (last 2m):"
        printf '%s\n' "$LOCAL_LOG_ERRORS" | sed 's/^/     /'
    else
        echo "   • ✅ No errors detected in $LOCAL_LABEL logs (last 2m)"
    fi

    if [ ${#REMOTE_COMPUTERS[@]} -gt 0 ]; then
        for remote_entry in "${REMOTE_COMPUTERS[@]}"; do
            IFS="|" read -r REMOTE_LABEL REMOTE_HOST REMOTE_USER REMOTE_PASS REMOTE_APP_PATH <<< "$remote_entry"
            echo "   • Remote health check: $REMOTE_LABEL"

            set +e
            REMOTE_CPU_OUTPUT=$(run_remote_script_capture_exit "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_PASS" "$REMOTE_CPU_SNAPSHOT_SCRIPT")
            REMOTE_CPU_EXIT=$?
            set -e

            if [ $REMOTE_CPU_EXIT -eq 0 ] && [ -n "$REMOTE_CPU_OUTPUT" ]; then
                echo "     CPU snapshot:"
                printf '%s\n' "$REMOTE_CPU_OUTPUT" | sed 's/^/       /'
            elif [ $REMOTE_CPU_EXIT -eq 1 ]; then
                echo "     ⚠️  Process not detected in CPU snapshot"
            else
                echo "     ⚠️  Unable to retrieve CPU snapshot (exit $REMOTE_CPU_EXIT)"
            fi

            set +e
            REMOTE_LOG_OUTPUT=$(run_remote_script_capture_exit "$REMOTE_HOST" "$REMOTE_USER" "$REMOTE_PASS" "$REMOTE_LOG_SCAN_SCRIPT")
            REMOTE_LOG_EXIT=$?
            set -e

            if [ $REMOTE_LOG_EXIT -eq 0 ] && [ -n "$REMOTE_LOG_OUTPUT" ]; then
                echo "     ⚠️  Log findings (last 2m):"
                printf '%s\n' "$REMOTE_LOG_OUTPUT" | sed 's/^/       /'
            elif [ $REMOTE_LOG_EXIT -eq 1 ]; then
                echo "     ✅ No errors detected in logs (last 2m)"
            else
                echo "     ⚠️  Unable to retrieve logs (exit $REMOTE_LOG_EXIT)"
            fi
        done
    fi
else
    echo "ℹ️  Health checks skipped (use --health-check to enable)"
fi

echo ""
echo "=============================================="
echo ""
echo "🔐 To set up Full Disk Access permissions, run:"
echo "   ./setup_permissions.sh"
echo ""
