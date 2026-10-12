#!/bin/bash

CERT_NAME="My CRM Code Signing"

# Check if certificate already exists
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "✅ Certificate '$CERT_NAME' already exists"
    security find-identity -v -p codesigning
    exit 0
fi

echo "🔐 Creating code signing certificate using macOS certificate assistant..."

# Use macOS to create a proper code signing certificate
cat > /tmp/create_cert.sh << 'CERTSCRIPT'
#!/usr/bin/osascript
tell application "System Events"
    -- This would normally open Keychain Access and create cert
    -- But we'll use command line instead
end tell
CERTSCRIPT

# Better approach: Use security command to create a self-signed cert with proper attributes
cat > /tmp/cert_info.certSigningRequest << 'CSR'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = My CRM Code Signing
O = My CRM Development  
C = US

[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
CSR

echo "📝 Creating certificate request..."
openssl req -new -newkey rsa:2048 -nodes \
    -keyout /tmp/cert_key.pem \
    -out /tmp/cert_request.csr \
    -config /tmp/cert_info.certSigningRequest 2>/dev/null

echo "📝 Self-signing certificate with code signing extension..."
openssl x509 -req -days 3650 \
    -in /tmp/cert_request.csr \
    -signkey /tmp/cert_key.pem \
    -out /tmp/cert.pem \
    -extfile <(printf "keyUsage=critical,digitalSignature\nextendedKeyUsage=codeSigning") 2>/dev/null

echo "📥 Importing into keychain..."
# Create a PKCS12 bundle
openssl pkcs12 -export \
    -inkey /tmp/cert_key.pem \
    -in /tmp/cert.pem \
    -out /tmp/cert.p12 \
    -passout pass: 2>/dev/null

# Import the p12
security import /tmp/cert.p12 \
    -k ~/Library/Keychains/login.keychain-db \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -P "" 2>/dev/null

# Set trust
security add-trusted-cert -d -r trustRoot \
    -k ~/Library/Keychains/login.keychain-db \
    /tmp/cert.pem 2>/dev/null

# Clean up
rm -f /tmp/cert* 2>/dev/null

echo ""
echo "✅ Checking for code signing identities..."
security find-identity -v -p codesigning

