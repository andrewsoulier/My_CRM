# Getting Started with My CRM

Welcome! This guide will help you set up My CRM in just a few minutes.

## First Time Setup

### Step 1: Launch the App
- Find "My CRM" in your Applications folder
- Or press Cmd+Space and type "My CRM"
- The app will appear in your menu bar (top-right corner)

### Step 2: Initial Configuration
The app will automatically:
- Create a database at `~/Library/Application Support/My_CRM/my_crm.db`
- Create settings at `~/Library/Application Support/My_CRM/User_Settings.json`
- Set up all necessary folders
- Create database tables (contacts, groups, invites, messages, batch_messages)
- Import your contacts from macOS Contacts app

You don't need to do anything - it just works!

**What happens behind the scenes:**
1. FirstRunSetup creates the database file and directory structure
2. CRMDatabase.ensureSchema() creates all necessary tables
3. ContactsImporter reads contacts from macOS Contacts and populates the database
4. MessagesImporter runs if Full Disk Access is granted (imports iMessage history)

Check `~/Library/Application Support/My_CRM/Logs/crm_debug.log` to see the initialization process.

### Step 3: Enable iMessage Integration (Optional)
To access your iMessage history:

1. Open **System Settings** → **Privacy & Security** → **Full Disk Access**
2. Click the **+** button
3. Navigate to **Applications** → **My CRM.app**
4. Enable the checkbox next to "My CRM"
5. Restart My CRM

**Note:** This is optional. The app works without it, but you won't see iMessage data.

### Step 4: Start Using My CRM
1. Click the My CRM icon in your menu bar
2. Select "Open Note Book"
3. Start organizing your contacts!

## Features

- **Contacts Management:** Import and organize your contacts
- **Visual Groups:** Create groups on a visual canvas
- **iMessage Integration:** View message history (with FDA)
- **Quick Send:** Send messages directly from the app
- **Search:** Find contacts quickly with fuzzy search

## System Requirements

- macOS 14.0 or later
- ~10 MB disk space
- **No Python or other dependencies required!**

## Troubleshooting

### "The app can't be opened" or "damaged" warning
This is macOS Gatekeeper security when the app is copied between computers. **Solution:**

**If you received a DMG installer:**
1. Open the DMG file
2. Drag "My CRM" to Applications
3. Double-click the "Remove Quarantine.command" script in the DMG
4. Launch My CRM normally

**If you received just the .app file:**
1. Right-click "My CRM.app" in Applications
2. Select "Open" (not double-click!)
3. Click "Open" in the security dialog

**Or use Terminal:**
```bash
xattr -cr "/Applications/My CRM.app"
```

This is a one-time setup. After this, the app launches normally.

### "No contacts appear"
1. The app imports from macOS Contacts - make sure you have contacts there
2. Check the logs at `~/Library/Application Support/My_CRM/Logs/crm_debug.log` for import errors
3. Look for "👤 ContactsImporter" messages in the logs
4. Or manually add contacts through the app

### "Can't access Messages"
You need to grant Full Disk Access (see Step 3 above).

### "Database tables not created" or "no such table" errors
If you see these errors in the logs:
1. Check that `CRMDatabase.ensureSchema` appears in the logs with "✅ table ready" messages
2. Verify write permissions on `~/Library/Application Support/My_CRM/` directory
3. Check the database path in `~/Library/Application Support/My_CRM/User_Settings.json`
4. Try changing the database path to test with a fresh database (e.g., `my_crm_2.db`)
5. Restart the app to trigger initialization again

### Reset to Defaults
If something goes wrong:
1. Open Settings (from menu bar icon)
2. Locate the settings file path
3. Delete the file and restart the app
4. Fresh settings will be created automatically

## Privacy & Data

My CRM accesses:
- **macOS Contacts:** To import your contacts
- **iMessage Database:** Only if you grant Full Disk Access
- **Files You Select:** When you choose to import/export

All data stays on your Mac. Nothing is sent to the internet except:
- AI features (if you configure and use them)

## Need Help?

- Check the README.md for detailed documentation
- Review the .md files in the app folder for technical details
- File an issue if you find bugs

## Updates

To update My CRM:
1. Replace the app in Applications with the new version
2. Your data and settings are preserved
3. FDA permissions persist (same bundle ID)

---

**Enjoy organizing your relationships!**

