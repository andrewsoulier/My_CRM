#!/bin/bash

# Script to create a self-signed certificate for code signing
# This allows Full Disk Access and other permissions to persist across builds

CERT_NAME="My CRM Developer"

# Check if certificate already exists
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "✅ Certificate '$CERT_NAME' already exists"
    exit 0
fi

echo "🔐 Creating self-signed code signing certificate..."
echo "   This will allow permissions to persist across builds"
echo ""

# Create the certificate
cat > /tmp/cert_config.txt << CERTEOF
[ req ]
default_bits = 2048
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[ req_distinguished_name ]
CN = $CERT_NAME
O = My CRM Development
OU = Development
C = US

[ v3_ca ]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,digitalSignature
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
CERTEOF

# Generate the certificate
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -config /tmp/cert_config.txt \
    -keyout /tmp/cert_key.pem \
    -out /tmp/cert.pem 2>/dev/null

# Import into keychain
security import /tmp/cert.pem -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -T /usr/bin/security
security import /tmp/cert_key.pem -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign -T /usr/bin/security

# Trust the certificate for code signing
security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db /tmp/cert.pem

# Set the certificate to allow codesign to use it without prompting
security set-key-partition-list -S apple-tool:,apple: -s -k "" ~/Library/Keychains/login.keychain-db

# Clean up
rm -f /tmp/cert*.pem /tmp/cert*.txt

echo ""
echo "✅ Self-signed certificate created: '$CERT_NAME'"
echo "✅ Certificate is valid for 10 years"
echo "✅ Permissions should now persist across builds"
echo ""
echo "Note: You may need to restart your Mac for Full Disk Access"
echo "      to fully recognize the new code signature"

