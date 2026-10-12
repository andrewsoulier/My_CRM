#!/bin/bash
set -e

# My CRM - Full Disk Access Setup Script
# This script helps automate the process of granting Full Disk Access permissions

APP_NAME="My CRM"
APP_BUNDLE_ID="com.mycrm.app"
APP_PATH="/Applications/My CRM.app"

echo "🔐 My CRM - Full Disk Access Setup"
echo "=================================="

# Function to check if app exists
check_app_exists() {
    if [ ! -d "$APP_PATH" ]; then
        echo "❌ Error: $APP_NAME not found at $APP_PATH"
        echo "Please build and install the app first using ./build_app.sh"
        exit 1
    fi
    echo "✅ Found $APP_NAME at $APP_PATH"
}

# Function to verify Full Disk Access permission
check_permission() {
    echo "🔍 Checking Full Disk Access permission..."
    
    # Try to access a restricted file to test permission
    if [ -f "/System/Library/UserEventNotifications/Agent" ] 2>/dev/null; then
        echo "✅ Full Disk Access appears to be granted"
        return 0
    else
        echo "⚠️ Full Disk Access permission not detected"
        return 1
    fi
}

# Function to check code signing status
check_code_signing() {
    echo "🔐 Checking code signing status..."
    
    if command -v codesign &> /dev/null; then
        SIGNATURE=$(codesign -dv "/Applications/My CRM.app" 2>&1 | grep "Signature=" | awk -F'=' '{print $2}')
        if [ "$SIGNATURE" = "adhoc" ]; then
            echo "⚠️ App is unsigned (adhoc) - Full Disk Access will reset after each build"
            echo "   Run './setup_certificate.sh' to set up consistent code signing"
            return 1
        else
            echo "✅ App is properly signed - Full Disk Access should persist"
            return 0
        fi
    else
        echo "❌ Cannot check code signing status"
        return 1
    fi
}

# Function to open System Settings to Full Disk Access
open_system_settings() {
    echo "🚀 Opening System Settings to Full Disk Access section..."
    
    # Check code signing first
    if ! check_code_signing; then
        echo ""
        echo "💡 TIP: To avoid having to re-grant Full Disk Access after each build:"
        echo "   Run: ./setup_certificate.sh"
        echo ""
    fi
    
    # Open System Settings to Privacy & Security
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    
    echo "📋 Please follow these steps:"
    echo "   1. Click the lock icon and enter your password"
    echo "   2. Find '$APP_NAME' in the list"
    echo "   3. If not listed, click '+' and navigate to $APP_PATH"
    echo "   4. Check the box next to '$APP_NAME'"
    echo "   5. Return to this terminal and press Enter"
    
    read -p "Press Enter after granting permission..."
}

# Function to verify and test the permission
verify_permission() {
    echo "🔍 Verifying Full Disk Access permission..."
    
    # Test access to various restricted locations
    TEST_PATHS=(
        "/System/Library/UserEventNotifications/Agent"
        "/Library/Application Support/com.apple.TCC/TCC.db"
        "/var/db/dslocal/nodes/Default/users"
    )
    
    for path in "${TEST_PATHS[@]}"; do
        if [ -f "$path" ] 2>/dev/null || [ -d "$path" ] 2>/dev/null; then
            echo "✅ Can access: $path"
        else
            echo "⚠️ Cannot access: $path"
        fi
    done
    
    # Test with a simple file access
    if [ -f "/System/Library/UserEventNotifications/Agent" ] 2>/dev/null; then
        echo "🎉 Full Disk Access is working correctly!"
        return 0
    else
        echo "❌ Full Disk Access may not be working properly"
        echo "   Try restarting the app or checking System Settings again"
        return 1
    fi
}

# Function to create a desktop shortcut for easy access
create_desktop_shortcut() {
    echo "📱 Creating desktop shortcut for easy access..."
    
    DESKTOP_SHORTCUT="$HOME/Desktop/My CRM - Full Disk Access Setup.command"
    
    cat > "$DESKTOP_SHORTCUT" << EOF
#!/bin/bash
cd "$(dirname "\$0")"
./setup_permissions.sh
EOF
    
    chmod +x "$DESKTOP_SHORTCUT"
    echo "✅ Desktop shortcut created: $DESKTOP_SHORTCUT"
}

# Function to show current permission status
show_status() {
    echo "📊 Current Permission Status:"
    echo "============================="
    
    # Check if app is in Full Disk Access list (requires system_profiler)
    if command -v system_profiler &> /dev/null; then
        echo "🔍 Checking Full Disk Access list..."
        # Note: This may not work on all macOS versions due to privacy restrictions
        echo "   (Full Disk Access list cannot be programmatically read)"
    fi
    
    # Check app bundle
    if [ -d "$APP_PATH" ]; then
        echo "✅ App bundle found at: $APP_PATH"
    else
        echo "❌ App bundle not found"
    fi
    
    # Test permission
    if check_permission; then
        echo "✅ Full Disk Access: GRANTED"
    else
        echo "❌ Full Disk Access: NOT GRANTED"
    fi
}

# Main execution
main() {
    case "${1:-setup}" in
        "check"|"status")
            check_app_exists
            show_status
            ;;
        "verify")
            check_app_exists
            verify_permission
            ;;
        "setup"|"")
            check_app_exists
            
            if check_permission; then
                echo "✅ Full Disk Access is already granted!"
                verify_permission
            else
                open_system_settings
                verify_permission
            fi
            
            create_desktop_shortcut
            ;;
        "help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  setup   - Interactive setup (default)"
            echo "  check   - Check current permission status"
            echo "  verify  - Verify Full Disk Access is working"
            echo "  help    - Show this help message"
            ;;
        *)
            echo "❌ Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
