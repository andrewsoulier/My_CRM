#!/bin/bash
set -e

# Enhanced build script with integrated permission setup
# Usage: ./build_and_setup.sh "Build description" [--auto-permissions]

# Check if build description is provided
if [ $# -eq 0 ]; then
    echo "❌ Error: Build description is required"
    echo "Usage: $0 \"Build description (5-10 words)\" [--auto-permissions]"
    echo "Example: $0 \"New debug mouse point correction\" --auto-permissions"
    exit 1
fi

BUILD_DESCRIPTION="$1"
AUTO_PERMISSIONS=false

# Check for auto-permissions flag
if [ "$2" = "--auto-permissions" ]; then
    AUTO_PERMISSIONS=true
fi

echo "🏗️ Enhanced Build: My CRM App Bundle with Permission Setup"
echo "=========================================================="
echo "Build description: '$BUILD_DESCRIPTION'"
echo "Auto-permissions: $AUTO_PERMISSIONS"

# Run the original build script
echo "🔨 Running build process..."
"$(dirname "$0")/build_app.sh" "$BUILD_DESCRIPTION"

# Check if build was successful
if [ $? -ne 0 ]; then
    echo "❌ Build failed. Stopping."
    exit 1
fi

echo "✅ Build completed successfully!"

# Set up permissions
echo "🔐 Setting up Full Disk Access permissions..."

# Make sure the permission script is executable
chmod +x "$(dirname "$0")/setup_permissions.sh"

if [ "$AUTO_PERMISSIONS" = true ]; then
    echo "🤖 Running automated permission setup..."
    "$(dirname "$0")/setup_permissions.sh" setup
else
    echo "📋 Manual permission setup required:"
    echo "   1. Run: ./setup_permissions.sh"
    echo "   2. Or double-click the desktop shortcut"
    echo "   3. Follow the on-screen instructions"
fi

echo ""
echo "🎉 Enhanced build complete!"
echo "🚀 My CRM is ready to use with proper permissions!"
