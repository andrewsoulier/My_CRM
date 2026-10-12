#!/bin/bash
set -e

# My CRM - Code Signing Certificate Setup
# This script helps set up a consistent code signing certificate to preserve Full Disk Access

echo "🔐 My CRM - Code Signing Certificate Setup"
echo "=========================================="

# Function to check if we have a signing identity
check_signing_identity() {
    if command -v security &> /dev/null; then
        # Check for Developer ID
        if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
            DEVELOPER_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}')
            echo "✅ Found Developer ID: $DEVELOPER_ID"
            return 0
        fi
        
        # Check for Mac Developer
        if security find-identity -v -p codesigning | grep -q "Mac Developer"; then
            MAC_DEV_ID=$(security find-identity -v -p codesigning | grep "Mac Developer" | head -1 | awk '{print $2}')
            echo "✅ Found Mac Developer ID: $MAC_DEV_ID"
            return 0
        fi
    fi
    
    echo "❌ No code signing identity found"
    return 1
}

# Function to create a self-signed certificate
create_self_signed_cert() {
    echo "🔧 Creating self-signed certificate for consistent signing..."
    
    # Create a temporary directory for certificate files
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Create certificate configuration
    cat > mycrm.conf << 'EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = CA
L = San Francisco
O = My CRM
OU = Development
CN = My CRM Self-Signed

[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
EOF

    # Generate private key
    openssl genrsa -out mycrm.key 2048
    
    # Generate certificate
    openssl req -new -x509 -key mycrm.key -out mycrm.crt -days 3650 -config mycrm.conf -extensions v3_req
    
    # Convert to p12 format
    openssl pkcs12 -export -out mycrm.p12 -inkey mycrm.key -in mycrm.crt -password pass:mycrm123 -name "My CRM Self-Signed"
    
    # Import into keychain
    security import mycrm.p12 -k ~/Library/Keychains/login.keychain -P mycrm123 -T /usr/bin/codesign -A
    
    # Trust the certificate for code signing
    security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain mycrm.crt
    
    echo "✅ Self-signed certificate created and imported"
    
    # Clean up
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    
    return 0
}

# Function to show certificate setup instructions
show_instructions() {
    echo ""
    echo "📋 Code Signing Setup Instructions"
    echo "=================================="
    echo ""
    echo "To preserve Full Disk Access across builds, you need a code signing certificate."
    echo ""
    echo "Option 1 - Apple Developer ID (Recommended for distribution):"
    echo "  1. Go to https://developer.apple.com"
    echo "  2. Sign in with your Apple ID"
    echo "  3. Enroll in Apple Developer Program ($99/year)"
    echo "  4. Create a 'Developer ID Application' certificate"
    echo "  5. Download and install the certificate"
    echo ""
    echo "Option 2 - Mac Developer Certificate (Free with Xcode):"
    echo "  1. Open Xcode"
    echo "  2. Go to Xcode > Preferences > Accounts"
    echo "  3. Add your Apple ID"
    echo "  4. Click 'Manage Certificates'"
    echo "  5. Click '+' and select 'Mac Development'"
    echo ""
    echo "Option 3 - Self-Signed Certificate (Development only):"
    echo "  This script can create a self-signed certificate for development."
    echo "  Note: This won't work for distribution but will preserve FDA locally."
    echo ""
}

# Function to test the setup
test_setup() {
    echo "🧪 Testing code signing setup..."
    
    if check_signing_identity; then
        echo "✅ Code signing is properly configured"
        echo "   Full Disk Access should now persist across builds"
        return 0
    else
        echo "❌ Code signing setup incomplete"
        return 1
    fi
}

# Main execution
main() {
    case "${1:-check}" in
        "check")
            echo "🔍 Checking current code signing setup..."
            if check_signing_identity; then
                echo "🎉 Code signing is already configured!"
                test_setup
            else
                show_instructions
            fi
            ;;
        "create-self-signed")
            if create_self_signed_cert; then
                echo "🎉 Self-signed certificate created!"
                test_setup
            else
                echo "❌ Failed to create self-signed certificate"
                exit 1
            fi
            ;;
        "instructions")
            show_instructions
            ;;
        "test")
            test_setup
            ;;
        "help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  check             - Check current setup (default)"
            echo "  create-self-signed - Create a self-signed certificate"
            echo "  instructions      - Show setup instructions"
            echo "  test             - Test the current setup"
            echo "  help             - Show this help message"
            ;;
        *)
            echo "❌ Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Check prerequisites
if ! command -v openssl &> /dev/null; then
    echo "❌ OpenSSL not found. Please install Xcode command line tools:"
    echo "   xcode-select --install"
    exit 1
fi

# Run main function
main "$@"
