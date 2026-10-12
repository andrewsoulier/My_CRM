#!/bin/bash

echo "🔨 Building Drop Test App..."

# Create a temporary directory for the build
BUILD_DIR="drop_test_build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Create Package.swift for the test app
cat > "$BUILD_DIR/Package.swift" << 'EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DropTestApp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DropTestApp", targets: ["DropTestApp"])
    ],
    targets: [
        .executableTarget(
            name: "DropTestApp",
            path: "Sources"
        )
    ]
)
EOF

# Create Sources directory and copy the app
mkdir -p "$BUILD_DIR/Sources"
cp DropTestApp.swift "$BUILD_DIR/Sources/main.swift"

# Build the app
cd "$BUILD_DIR"
swift build

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "🚀 Running Drop Test App..."
    echo "📋 Instructions:"
    echo "   1. Drag contacts from My CRM to the blue drop zone"
    echo "   2. Watch the log output below"
    echo "   3. Press Ctrl+C to stop"
    echo ""
    .build/debug/DropTestApp
else
    echo "❌ Build failed!"
    exit 1
fi
