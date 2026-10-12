# Full Disk Access Automation Guide

## Overview

This guide explains how to automate the Full Disk Access permission setup for My CRM, reducing the need for manual intervention after each build or update.

## Important Limitations

**macOS does not allow apps to automatically grant themselves Full Disk Access permissions.** This is a security feature that requires user interaction. However, we can automate the process of requesting and guiding users through the permission setup.

## Why Full Disk Access Resets After Each Build

**Root Cause**: Each build creates a new binary with a different signature. macOS tracks Full Disk Access permissions by the app's code signature, not just the bundle identifier. When the signature changes, macOS treats it as a different app and revokes the permission.

**Technical Details**:
- Unsigned apps get an "adhoc" signature that changes with every build
- The CDHash (Code Directory Hash) changes with each compilation
- TCC (Transparency, Consent, and Control) database stores permissions by signature
- New signature = new app identity = permission revoked

**Solution**: Use consistent code signing to preserve the app's identity across builds.

## Available Solutions

### 1. Permission Setup Script (`setup_permissions.sh`)

A comprehensive script that:
- Checks if the app is properly installed
- Opens System Settings to the Full Disk Access section
- Provides step-by-step guidance
- Verifies that permissions are working
- Creates a desktop shortcut for easy access

**Usage:**
```bash
./setup_permissions.sh setup    # Interactive setup
./setup_permissions.sh check    # Check current status
./setup_permissions.sh verify   # Verify permissions work
./setup_permissions.sh help     # Show help
```

### 2. Code Signing Setup Script (`setup_certificate.sh`)

A script to set up consistent code signing to preserve Full Disk Access:

**Usage:**
```bash
./setup_certificate.sh check              # Check current setup
./setup_certificate.sh create-self-signed # Create self-signed certificate
./setup_certificate.sh instructions       # Show setup instructions
```

### 3. Enhanced Build Script (`build_and_setup.sh`)

An enhanced version of the build script that integrates permission setup:

**Usage:**
```bash
./build_and_setup.sh "Build description"
./build_and_setup.sh "Build description" --auto-permissions
```

### 4. Updated Build Script (`build_app.sh`)

The original build script now includes:
- Automatic code signing with available certificates
- Automatic permission script setup
- Instructions for running the permission setup
- Desktop shortcut creation

## How It Works

### Step 1: Code Signing Setup (One-time)
To preserve Full Disk Access across builds:
1. Run `./setup_certificate.sh` to check current setup
2. Choose one of three options:
   - **Developer ID** ($99/year) - Best for distribution
   - **Mac Developer Certificate** (Free with Xcode) - Good for development
   - **Self-signed Certificate** (Free) - Development only

### Step 2: Build Process
The build script:
1. Creates the app bundle and installs it to `/Applications/`
2. Automatically signs the app with available certificates
3. Preserves the app's identity across builds

### Step 3: Permission Setup
The permission setup script:
1. Checks if the app is properly signed
2. Opens System Settings to Privacy & Security > Full Disk Access
3. Guides the user to add the app manually
4. Verifies the permission is working
5. Creates a desktop shortcut for future use

### Step 4: Verification
The script tests access to restricted system files to confirm Full Disk Access is working.

## Best Practices

### For Development
1. **First-time setup**: Run `./setup_certificate.sh` to set up code signing
2. Use the enhanced build script: `./build_and_setup.sh "description" --auto-permissions`
3. Full Disk Access should now persist across builds
4. Keep the desktop shortcut for quick permission setup
5. Run `./setup_permissions.sh check` to verify permissions after updates

### For Distribution
1. Include the `setup_permissions.sh` script with your app
2. Provide clear instructions for users
3. Consider creating an installer that runs the permission setup

## Troubleshooting

### Permission Not Working
1. Run `./setup_permissions.sh verify` to test
2. Check System Settings > Privacy & Security > Full Disk Access
3. Remove and re-add the app if needed
4. Restart the app after granting permission

### App Not in Permission List
1. Make sure the app is in `/Applications/`
2. Use the "+" button to manually add the app
3. Navigate to `/Applications/My CRM.app`

### Script Permissions
If scripts are not executable:
```bash
chmod +x setup_permissions.sh
chmod +x build_and_setup.sh
```

## Technical Details

### Entitlements
The app uses sandboxed entitlements with specific file access exceptions:
- Messages database access
- Application Support directory
- Downloads, Documents, and Desktop access
- Network and USB device access

### System Integration
The scripts use:
- `open` command to launch System Settings
- File system checks to verify permissions
- Desktop shortcut creation for easy access

## Future Improvements

### Possible Enhancements
1. **Automated Testing**: Create test cases that verify Full Disk Access
2. **Installation Script**: Bundle everything into a single installer
3. **Permission Monitoring**: Monitor permission changes and notify users
4. **Alternative Approaches**: Explore other permission models if available

### macOS Version Compatibility
- Tested on macOS 14.0+
- May require updates for future macOS versions
- System Settings path may change between versions

## Security Considerations

### Why Manual Permission is Required
- Full Disk Access is a highly privileged permission
- Apple requires explicit user consent for security
- Prevents malicious apps from gaining unrestricted access

### Best Practices
- Only request Full Disk Access when necessary
- Clearly explain why the permission is needed
- Provide alternatives when possible
- Regularly review and audit permission usage

## Support

For issues with the permission setup:
1. Check the troubleshooting section above
2. Review system logs for permission errors
3. Test with a fresh app installation
4. Contact support with specific error messages

---

**Note**: This automation reduces manual steps but cannot eliminate the need for user interaction due to macOS security requirements.
