#!/bin/bash

# Script to set up SSH key authentication for andreassoul-fuji.nord

echo "=========================================="
echo "SSH Key Setup for andreassoul-fuji.nord"
echo "=========================================="
echo ""

REMOTE_HOST="andreassoul-fuji.nord"
REMOTE_USER="andrewsoulier"
SSH_KEY="$HOME/.ssh/id_ed25519"

echo "This script will help you set up SSH key authentication."
echo ""
echo "STEP 1: Copy your public key"
echo "----------------------------------------"
echo "Run this command manually and enter password when prompted (28VP04!!):"
echo ""
echo "cat ~/.ssh/id_ed25519.pub | ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no $REMOTE_USER@$REMOTE_HOST 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'"
echo ""
echo "----------------------------------------"
echo ""
echo "After running the above command, test with:"
echo "ssh $REMOTE_HOST 'echo \"✅ SSH key authentication successful!\"'"
echo ""
echo "=========================================="
echo ""

read -p "Would you like me to try now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Attempting to install SSH key..."
    echo "Please enter password when prompted: 28VP04!!"
    echo ""
    cat "$SSH_KEY.pub" | ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no "$REMOTE_USER@$REMOTE_HOST" 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ SSH key installed successfully!"
        echo ""
        echo "Testing connection..."
        ssh "$REMOTE_HOST" 'echo "✅ Connection successful!"'
    else
        echo ""
        echo "❌ Failed to install SSH key"
        echo "You may need to do this manually"
    fi
fi

