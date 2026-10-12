# Batch Messaging Authorization Guide

## Overview

My CRM's batch messaging feature requires specific macOS permissions to send messages through the Messages app. This guide explains the required permissions, how to grant them, and how to troubleshoot common issues.

## Required Permissions

### 1. Automation Permission (Required)
**What it does**: Allows My CRM to control the Messages app via AppleScript to send messages on your behalf.

**How to grant**:
1. Open **System Settings** (or System Preferences on older macOS)
2. Navigate to **Privacy & Security** → **Automation**
3. Find **My CRM** in the list
4. Enable the checkbox next to **Messages**
5. Restart My CRM if it was already running

**Error if missing**: `"Not authorized to send Apple events to Messages. (-1743)"`

### 2. Full Disk Access (Recommended)
**What it does**: Allows My CRM to read the Messages database for enhanced features like conversation history and delivery status.

**How to grant**:
1. Open **System Settings** → **Privacy & Security** → **Full Disk Access**
2. Click the **+** button
3. Navigate to and select **My CRM.app**
4. Restart My CRM

**Note**: This permission is optional for sending messages but recommended for full functionality.

### 3. Messages App Running
**Requirement**: The macOS Messages app must be running for My CRM to send messages.

**How to launch**:
- My CRM can automatically launch Messages when needed
- Or manually open Messages from `/System/Applications/Messages.app`

## Setup Instructions

### First-Time Setup

1. **Launch My CRM**
   - Open My CRM from Applications or Spotlight

2. **Navigate to Quick Send**
   - Click "Quick Send" in the navigation bar

3. **Compose a Message**
   - Add recipients and message content

4. **Attempt to Send**
   - Click "Send Now" or "Schedule Send"
   - If permissions are missing, My CRM will guide you through granting them

5. **Grant Permissions**
   - Follow the on-screen instructions
   - Use "Request Permission" in My CRM to trigger the macOS automation consent prompt
   - If the prompt does not appear, click "Open System Settings" to enable Messages for My CRM
   - Grant the requested permissions
   - (Optional) Validate the grant with `sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db "SELECT auth_value FROM access WHERE service='kTCCServiceAppleEvents' AND client='com.andrewsoulier.mycrm';"` — a value of `2` confirms Messages is trusted

6. **Verify Setup**
   - Return to My CRM
   - Click "Check Again" to verify permissions (the app now performs a silent automation status check, so previously granted permissions stay enabled and no extra prompt flashes)
   - Try sending a test message

### macOS Version-Specific Notes

#### macOS Ventura (13.0) and later
- Settings are in **System Settings** app
- Automation settings: `Privacy & Security → Automation`

#### macOS Monterey (12.0) and earlier
- Settings are in **System Preferences** app
- Automation settings: `Security & Privacy → Privacy → Automation`

## Troubleshooting

### Error: "Not authorized to send Apple events" (-1743)

**Cause**: Automation permission not granted

**Solution**:
1. Open System Settings → Privacy & Security → Automation
2. Find My CRM and enable Messages
3. Restart My CRM
4. Try sending again

### Error: "Messages app is not running"

**Cause**: Messages app is closed

**Solution**:
1. Click "Launch Messages" in the authorization dialog
2. Or manually open Messages from Applications
3. Keep Messages running while using batch send features

### Error: "Application isn't running" 

**Cause**: Messages app crashed or was force quit

**Solution**:
1. Force quit Messages if it appears stuck (Activity Monitor)
2. Relaunch Messages
3. Wait 5-10 seconds for Messages to fully start
4. Try sending again

### Messages send but show as "failed"

**Possible causes**:
- Invalid phone number format (use E.164: +1234567890)
- Recipient not in your contacts
- iMessage not signed in
- Network connectivity issues

**Solution**:
1. Verify phone numbers are in correct format
2. Ensure you're signed into iMessage (Messages → Settings)
3. Check internet connection
4. Try sending a test message manually in Messages app

### Disk I/O error (rc=10) during authorization check

**Cause**: SQLite cannot write WAL/SHM files because the database directory has restricted attributes or lives on a locked volume.

**Solution**:
1. Confirm the database is under `~/Library/Application Support/My_CRM`
2. Remove stale ACL metadata: `xattr -d com.apple.macl ~/Library/Application\ Support/My_CRM/my_crm.db`
3. Run `sqlite3 ~/Library/Application\ Support/My_CRM/my_crm.db "PRAGMA wal_checkpoint(PASSIVE);"` to ensure the warning is resolved
4. If the path is synced/read-only, relocate the database to a writable local directory (e.g., `~/Library/Application Support/My_CRM/LocalDB/my_crm.db`), rename the previous copy with a `-- Old --` prefix, and update `User_Settings.json`

### Batch messages timing out

**Cause**: Messages app overloaded or network issues

**Solution**:
- Reduce batch size (send to fewer recipients at once)
- Increase delay between messages in settings
- Check for macOS or Messages updates
- Restart both My CRM and Messages app

## Error Code Reference

| Error Code | Meaning | Solution |
|-----------|---------|----------|
| -1743 | Not authorized for Apple Events | Grant Automation permission |
| -1728 | Application not found | Ensure Messages app is installed |
| -10810 | Messages not running | Launch Messages app |
| Timeout | Send operation took too long | Check network, reduce batch size |

## Best Practices

### For Reliable Batch Sending

1. **Keep Messages Running**
   - Don't quit Messages while sending batches
   - Messages can run in background

2. **Use Appropriate Delays**
   - Default: 0.5 seconds between messages
   - For large batches: Consider 1-2 seconds
   - Prevents rate limiting

3. **Test First**
   - Send a test message to yourself before batches
   - Verify phone number formats
   - Check preview for field replacements

4. **Monitor Progress**
   - Watch the progress indicator
   - Check logs for detailed error information
   - Review failed messages in history

5. **Handle Failures**
   - Failed messages are automatically retried once
   - Non-retriable errors (invalid numbers) are skipped
   - You can resume failed batches from history

### Phone Number Format

Always use E.164 international format:
- ✅ Correct: `+12345678900`
- ❌ Wrong: `(234) 567-8900`
- ❌ Wrong: `234-567-8900`

My CRM will attempt to normalize numbers, but E.164 format is most reliable.

## Advanced Configuration

### Adjusting Send Settings

Coming soon: Configurable settings for:
- Delay between messages
- Maximum retry attempts
- Timeout duration
- Batch size limits

### Logging and Diagnostics

Detailed logs are stored at:
- `~/Library/Application Support/My_CRM/Logs/crm_debug.log`
- `~/Library/Application Support/My_CRM/Logs/group_behavior.log`

Enable debug logging for troubleshooting:
1. Contact support for debug instructions
2. Logs contain detailed send attempts and errors
3. Include logs when reporting issues

## FAQ

**Q: Do I need to keep Messages visible while sending?**
A: No, Messages can run in the background. It just needs to be running (not quit).

**Q: Can I send messages when iMessage is offline?**
A: Messages will attempt to send via SMS if iMessage is unavailable, but you need an iPhone connected for SMS relay.

**Q: How many messages can I send at once?**
A: There's no hard limit, but we recommend batches under 100 for optimal reliability.

**Q: Will batch sending drain my iPhone battery?**
A: If using SMS relay through iPhone, there may be minimal battery impact. iMessages sent from Mac don't affect iPhone.

**Q: Can I schedule messages when my Mac is asleep?**
A: No, your Mac must be awake and Messages must be running for scheduled sends to work.

**Q: What happens if My CRM crashes during sending?**
A: My CRM tracks progress and will detect stuck messages on restart. Messages that were partially sent won't be duplicated.

## Getting Help

If you continue to experience issues:

1. **Check System Requirements**
   - macOS 12.0 (Monterey) or later
   - Messages app installed and configured
   - Signed into iMessage

2. **Review Logs**
   - Check `~/Library/Application Support/My_CRM/Logs/`
   - Look for error messages in `crm_debug.log`

3. **Contact Support**
   - Include macOS version
   - Include error messages from logs
   - Describe what you were trying to do

4. **Community Resources**
   - Check documentation for updates
   - Review closed issues for similar problems

## Version History

### v1.0 - Initial Release
- Basic batch messaging with authorization checks
- Automatic retry logic
- Pre-send validation
- Timeout handling
- Error categorization

### Future Enhancements
- Configurable send settings in UI
- Pause/resume for in-progress batches
- Advanced retry strategies
- Delivery confirmation tracking
- Rate limit detection and handling

