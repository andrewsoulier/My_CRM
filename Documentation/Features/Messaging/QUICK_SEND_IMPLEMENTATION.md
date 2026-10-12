# Quick Send Feature Implementation

## Overview
The Quick Send feature allows users to send personalized bulk messages to contacts and groups using iMessage/SMS with field replacement and scheduling capabilities.

## Latest Updates (November 9, 2025)

### Automation Permission Recheck Hardening

- **Silent Verification**: `MessagesAuthorizationManager` now relies on the macOS `AEDeterminePermissionToAutomateTarget` API to verify automation access without firing an AppleScript that can reset granted permissions.
- **No More Toggle-Off**: Clicking "Check Again" in the Quick Send authorization modal performs a read-only permission check, preventing System Settings from automatically unchecking the Messages automation toggle.
- **Improved Status Reporting**: The authorization flow now distinguishes between "Not Yet Requested" and "Denied" states based on the OSStatus responses from the automation permission API.
- **System Prompt First**: The Quick Send modal now provides a dedicated "Request Permission" action that relies entirely on macOS to display the automation consent prompt when needed.
- **Unified Preflight**: `MessagesPreflight` is now a thin wrapper over `MessagesAuthorizationManager`, removing redundant AppleScript probes and ensuring every screen reports the same state.
- **Handshake Recovery**: When macOS reports ambiguous automation status (`-1744/-1743`), the permission button performs a lightweight AppleScript handshake so the TCC database and UI remain in sync without forcing the toggle off.
- **Remote Triage Checklist**: Added standard operating procedure for querying `~/Library/Application Support/com.apple.TCC/TCC.db` and removing stale `com.apple.macl` attributes from `~/Library/Application Support/My_CRM/my_crm.db` when WAL checkpoints report `rc=10` on remote machines.
- **LocalDB Relocation**: When WAL checkpoints still emit `rc=10` after ACL cleanup, relocate the active database to `~/Library/Application Support/My_CRM/LocalDB/my_crm.db`, rename the former file with a `-- Old --` prefix, and update `User_Settings.json` to point to the new path.

## Historical Updates (October 29, 2025)

### Critical Bug Fixes and Group Tracking Enhancement

**Fixed Critical Database Update Bug**:
- Fixed column name mismatch in `updateBatchMessage` SQL query (was using `chip_metadata`, should be `field_metadata`)
- This was preventing ALL edits to scheduled messages from saving to the database
- Added enhanced logging to track database operations and row changes

**Implemented Group Tracking System**:
- Extended `BatchRecipient` model with `sourceGroupId` field to track which group each recipient came from
- Extended `BatchMessage` model with `sourceGroups` array to track originally selected groups
- Added `source_groups` column to database with automatic migration
- When creating a message from groups, the system now:
  - Tracks which groups were selected
  - Tags each recipient with their source group ID
  - Stores this information in the database

**Enhanced Edit Modal**:
- Edit modal now displays groups as colored chips with member counts (e.g., "Family (5)")
- Individual contacts shown separately from grouped contacts
- When saving edits, group members are automatically recalculated from current group membership
- If members are added/removed from a group, the message recipients update automatically

**Scheduling System Verification**:
- Confirmed that `handleEditSave` properly cancels and reschedules messages with updated times
- The launchd plist is regenerated with the new schedule time
- Scheduled messages read from database at trigger time, ensuring they use the latest message content and scheduled time

**Benefits**:
- Users can now edit message content and see changes persist ✓
- Users can change scheduled send times and they actually update ✓
- Group membership changes automatically reflect in scheduled messages ✓
- Better UI showing groups vs individual contacts ✓

## Features Implemented

### 1. Navigation Integration
- Added "Quick Send" page to the Tools section of the navigation bar
- Icon: paperplane.fill
- Accessible from the main navigation menu

### 2. User Interface Components

#### To Field
- **Contact/Group Search**: Real-time search with autocomplete
- **Drag & Drop**: Full support for dragging contacts and groups from the navigation bar into the recipient field
  - Drop destination for `Contact` objects
  - Drop destination for `ContactGroup` objects
  - Automatic logging of dropped items
  - Seamless integration with existing add methods
- **Recipient Chips**: Visual representation of selected contacts/groups
  - Grey chips for individual contacts
  - Color-matched chips for groups (uses the group's assigned color)
  - Remove button (X) on each chip
- **Duplicate Prevention**: Automatically skips duplicate contacts across all recipients (individual contacts and group members) based on phone number

#### Message Body Editor
- **@-mention System**: Slack-like chip system with @ trigger
- **Inline Chip Badges**: Visual chip badges rendered directly in the text editor
- **Chip Dropdown Menu**: Comprehensive dropdown showing all chip types organized by category
- **Keyboard Navigation**: 
  - **Arrow Keys**: Navigate up/down through chip options
  - **Tab/Enter**: Select highlighted chip and insert it into the message
  - **Escape**: Close the dropdown menu
  - **Auto Cursor Positioning**: Cursor automatically moves to the end of inserted chip for seamless typing
- **Edit on Click**: Click any chip to edit its properties
- **Smart Chips**: Color-coded chips for different types (contact fields, images, links, etc.)
- **Field Autocomplete**: Real-time filtering as user types after @
- **Safe Fields Only**: Excludes sensitive database fields like IDs, timestamps, etc.

#### Preview and Field Replacement Behavior
- `@name` now resolves from `Contact.displayName` for robust naming (uses first/last/name fallback).
- Group recipients in preview resolve real member contacts from the database by phone; placeholders are only used when a member phone has no matching contact.
- If a contact chip is missing its `contact` object, the preview resolves it by phone via the database for accurate field values.

#### Available Contact Fields
- `@phone` - Phone number
- `@name` - Full name
- `@first_name` - First name
- `@last_name` - Last name
- `@email` - Email address
- `@business` - Business/Company
- `@address` - Address
- `@birthday` - Birthday (formatted)
- `@contact_group` - Contact group
- `@notes` - Notes

#### Action Buttons
- **Preview**: Shows personalized message sample using first contact
- **Send Now**: Immediate message sending
- **Schedule Send**: Opens date/time picker for scheduling
- **Notify Checkbox**: Optional notification when sending completes

### 3. Message Preview System
- **Preview Modal**: Shows original template and personalized sample
- **Multiple Recipients**: Can preview for different contacts
- **Confirmation**: Clear confirmation before sending/scheduling

### 4. Scheduling System
- **Date/Time Picker**: 
  - Specific date/time selection
  - Relative time selection (in X hours/days)
- **macOS Integration**: Uses launchd for reliable scheduling
- **Helper Script**: Bundled within app bundle (`Resources/quick_send_helper.sh`) for portability - creates trigger files for scheduled execution
- **Validation**: Prevents scheduling messages in the past

### 5. Database Schema

#### Batch Messages Table
```sql
CREATE TABLE batch_messages (
    id TEXT PRIMARY KEY,
    message_template TEXT NOT NULL,
    recipients TEXT NOT NULL,           -- JSON array of BatchRecipient
    scheduled_time TEXT,               -- ISO8601 timestamp
    created_time TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    total_recipients INTEGER NOT NULL,
    sent_count INTEGER DEFAULT 0,
    failed_count INTEGER DEFAULT 0,
    failed_contacts TEXT DEFAULT '{}', -- JSON map of phone -> error
    completed_time TEXT,
    notify_when_sent INTEGER DEFAULT 0,
    error_log TEXT DEFAULT '[]',       -- JSON array of BatchError
    field_metadata TEXT                -- JSON metadata for smart chips (v2.0)
);
```

#### Smart Chip Metadata Format (v2.0)

The `field_metadata` field stores rich chip information while keeping the `message_template` human-readable:

```json
{
  "messageTemplate": "Hi @name, check out this image: @image_1 and visit @link_1 for more info.",
  "fieldMetadata": {
    "chips": [
      {
        "type": "contact_field",
        "field": "name",
        "startIndex": 3,
        "endIndex": 8,
        "displayText": "@name",
        "chipId": "chip_1"
      },
      {
        "type": "image",
        "startIndex": 45,
        "endIndex": 53,
        "displayText": "@image_1",
        "chipId": "chip_2",
        "metadata": {
          "imageUrl": "https://example.com/image.jpg",
          "altText": "Product image",
          "width": 200,
          "height": 150,
          "alignment": "center"
        }
      },
      {
        "type": "link",
        "startIndex": 58,
        "endIndex": 66,
        "displayText": "@link_1",
        "chipId": "chip_3",
        "metadata": {
          "url": "https://company.com/products",
          "displayText": "our products",
          "openInNewTab": true,
          "style": "button"
        }
      }
    ],
    "version": "2.0"
  }
}
```

#### Supported Chip Types

1. **Contact Field Chips** (`contact_field`)
   - Replaces `@field` with contact data
   - Fields: `@name`, `@phone`, `@email`, `@business`, etc.
   - No additional metadata required

2. **Image Chips** (`image`)
   - Embeds images in messages
   - Metadata: `imageUrl`, `altText`, `width`, `height`, `alignment`
   - Display: `@image_1`, `@image_2`, etc.

3. **Link Chips** (`link`)
   - Creates clickable links
   - Metadata: `url`, `displayText`, `openInNewTab`, `style`
   - Display: `@link_1`, `@link_2`, etc.

4. **Date/Time Chips** (`datetime`)
   - Dynamic date/time insertion
   - Metadata: `format`, `timezone`, `defaultValue`
   - Display: `@datetime_1`, `@date_1`, etc.

5. **Variable Chips** (`variable`)
   - Custom template variables
   - Metadata: `variableName`, `defaultValue`, `editable`
   - Display: `@var_company`, `@var_location`, etc.

6. **Attachment Chips** (`attachment`)
   - File attachments
   - Metadata: `filePath`, `fileName`, `fileSize`, `mimeType`
   - Display: `@attachment_1`, `@file_1`, etc.

#### Backward Compatibility

- Messages without `field_metadata` are treated as plain text
- Existing `@field` patterns are automatically inferred as `contact_field` chips
- Migration automatically converts legacy messages to v2.0 format

### 6. Message Processing
- **Batch Processing**: Processes recipients one by one
- **0.5 Second Delays**: Between each message to avoid rate limiting
- **Automatic Routing**: Messages.app automatically handles iMessage/SMS routing based on recipient capability
- **Retry Logic**: Single retry attempt for failed messages
- **Progress Tracking**: Real-time progress updates
- **Error Logging**: Detailed error tracking and reporting

### 7. Status Management
- **Real-time Updates**: Live progress indicators
- **Status Types**:
  - `pending` - Ready to send
  - `scheduled` - Scheduled for future
  - `sending` - Currently processing
  - `completed` - Successfully sent
  - `failed` - Failed to send
  - `cancelled` - User cancelled
- **Duplicate Prevention**: 
  - Once a scheduled message starts processing, status immediately changes to `sending`
  - Scheduler only processes messages with `scheduled` status
  - Prevents duplicate sends even if app restarts during processing
- **Recovery Mechanism**:
  - On app startup, checks for messages stuck in `sending` status
  - If messages were partially sent (sentCount > 0), marks as `failed` to prevent duplicates
  - If no messages were sent yet, resets to appropriate status:
    - Future scheduled messages → reset to `scheduled`
    - Past scheduled messages → processes immediately
    - Non-scheduled messages → reset to `pending`

### 8. Queued & History Management
- **Tabbed Interface**: Compose, Queued, History tabs
- **Editable Queue**: Users can edit/delete scheduled messages
- **Edit Modal**: Full-featured edit window for queued messages
  - Edit message content with smart chip support
  - Modify schedule timing (change, reschedule, or remove schedule)
  - Update notification preferences
  - Recipients displayed (read-only after creation)
  - Live preview of message with smart chips
- **History Tracking**: Complete history of sent messages
- **Table View**: Sortable table with status, progress, timestamps
- **Real-time Updates**: Live updates during sending

### 9. Notification System
- **Permission Request**: Automatic notification permission request
- **Completion Notifications**: Optional notifications when sending completes
- **Error Notifications**: Critical notifications for failures

## Technical Architecture

### Services
1. **BatchMessageService**: Handles message processing and sending
2. **SchedulingService**: Manages macOS launchd integration
3. **SQLiteDataProvider**: Extended with batch message storage

### Components
1. **QuickSendView**: Main page container
2. **RecipientSearchField**: Contact/group search with autocomplete
3. **MessageBodyEditor**: Main editor with chip system integration
4. **ChipTextView**: Custom NSTextView with inline chip rendering
5. **ChipDropdownMenu**: Dropdown menu for chip selection with categories
6. **ChipBadgeView**: Uniform styled chip badge renderer
7. **ChipEditModal**: Adaptive modal for editing chip properties
8. **MessagePreviewModal**: Preview and confirmation dialog
9. **SchedulePickerModal**: Date/time selection interface
10. **BatchMessageTableView**: Queue/history management
11. **BatchMessageEditModal**: Full-featured edit modal for queued messages

### Data Models
1. **BatchMessage**: Core message data structure
2. **BatchRecipient**: Individual recipient with field values
3. **RecipientChip**: UI representation of recipients
4. **BatchError**: Error tracking structure

## Usage Workflow

1. **Navigate** to Quick Send from Tools menu
2. **Add Recipients** by searching or dragging contacts/groups
3. **Compose Message** with optional @field replacements
4. **Preview** the personalized message
5. **Send** immediately or schedule for later
6. **Monitor** progress in real-time
7. **Review** history and manage queued messages

## Error Handling
- **Network Failures**: Automatic retry with detailed logging
- **Permission Issues**: Clear error messages and guidance
- **Invalid Recipients**: Skip invalid contacts with logging
- **Scheduling Conflicts**: Validation and user feedback
- **Database Errors**: Graceful degradation with error reporting

## Performance Considerations
- **Lazy Loading**: Efficient contact/group loading
- **Memory Management**: Proper cleanup of large recipient lists
- **Background Processing**: Non-blocking UI during sending
- **Rate Limiting**: Built-in delays to prevent service throttling

## Security & Privacy
- **Field Filtering**: Only safe contact fields exposed
- **Data Sanitization**: Proper escaping of message content
- **Permission Checks**: Proper notification permissions
- **Local Processing**: All processing done locally

## Future Enhancements
- **Templates**: Save and reuse message templates
- **Advanced Scheduling**: Recurring messages, timezone support
- **Analytics**: Delivery tracking and statistics
- **Rich Content**: Image and attachment support
- **Integration**: Calendar and reminder integration

## Files Modified/Created
- `Core/Models/BatchMessage.swift` - Data models
- `Core/Models/SmartChipModels.swift` - Chip data structures
- `Core/Services/BatchMessageService.swift` - Message processing
- `Core/Services/SchedulingService.swift` - Scheduling system (updated to use bundled helper script)
- `Core/Services/ChipTypeRegistry.swift` - Chip type handlers
- `Core/Services/SQLiteDataProvider.swift` - Database integration (added updateBatchMessage method)
- `UI/Pages/QuickSendView.swift` - Main interface (added edit functionality)
- `UI/Components/RecipientSearchField.swift` - Search component
- `UI/Components/MessageBodyEditor.swift` - Editor with chip system (completely rebuilt)
- `UI/Components/ChipTextView.swift` - Custom NSTextView with inline chip rendering via NSTextAttachment
- `UI/Components/ChipDropdownView.swift` - Categorized chip selection dropdown with keyboard navigation
- `UI/Components/ChipConfigurationModal.swift` - Chip editing/configuration modal for all chip types
- `UI/Components/MessagePreviewModal.swift` - Preview dialog
- `UI/Components/SchedulePickerModal.swift` - Scheduling interface
- `UI/Components/BatchMessageTableView.swift` - Queue/history tables
- `UI/Modals/BatchMessageEditModal.swift` - Edit modal for queued messages
- `Resources/quick_send_helper.sh` - Bundled helper script for scheduled message execution
- `State/AppState.swift` - Navigation integration
- `UI/Shell/WorkspaceView.swift` - Page routing
- `UI/Shell/PageNavBarView.swift` - Navigation menu
- `UI/Shell/MainCRMView.swift` - Notification permissions

### Deprecated Files (Marked for Deletion)
- `UI/Components/-- Old -- SmartChipTextView.swift` - Replaced by ChipTextView
- `UI/Components/-- Old -- SmartChipOverlay.swift` - Replaced by inline chip rendering

## Testing
- ✅ Build successful with no compilation errors
- ✅ App launches and runs without crashes
- ✅ Navigation integration working
- ✅ Database schema created successfully
- ✅ All UI components compile and render
- ✅ Smart chip input system fully functional

## Smart Chip Input System (Oct 2024 Update)

### Architecture

The new chip input system provides a smooth, inline editing experience similar to Slack mentions:

**ChipTextView** (`UI/Components/ChipTextView.swift`)
- SwiftUI wrapper around a custom NSTextView
- Detects "@" character and triggers dropdown
- Renders chips as NSTextAttachment objects (non-editable inline blocks)
- Handles keyboard navigation (Arrow keys, Enter, Tab, Escape)
- Calculates dropdown position relative to cursor
- Manages chip metadata synchronization

**ChipDropdownView** (`UI/Components/ChipDropdownView.swift`)
- Categorized display of all available chips
- Real-time filtering as user types
- Keyboard-navigable with selection highlighting
- Scrollable to keep window size manageable
- Categories: Contact Fields, Media, Date & Time, Variables, Links

**ChipConfigurationModal** (`UI/Components/ChipConfigurationModal.swift`)
- Type-specific configuration forms for each chip type
- Validation before insertion
- File picker for attachments
- URL validators for images and links

**MessageBodyEditor** (`UI/Components/MessageBodyEditor.swift`)
- Completely rebuilt to use new chip system
- Manages dropdown visibility and positioning
- Coordinates between text view, dropdown, and config modals
- Maintains backward compatibility with existing ChipMetadata format

### User Experience Flow

1. User types "@" in the message body
2. Dropdown appears showing all available chips, grouped by category
3. As user continues typing, chips filter in real-time
4. User navigates with arrow keys, selects with Enter/Tab
5. For simple chips (contact fields), chip inserts immediately
6. For complex chips (images, links, etc.), configuration modal appears
7. After configuration, chip appears as inline badge in text
8. Clicking a chip opens its configuration for editing
9. Backspace deletes entire chip as a single unit

### Technical Implementation

- **NSTextAttachment**: Used for rendering chips as non-editable inline objects
- **Custom Image Generation**: Each chip rendered as rounded badge image
- **Coordinate-based Positioning**: Dropdown positioned using NSLayoutManager for exact cursor location
- **Event Handling**: Custom keyDown override for dropdown keyboard navigation
- **Metadata Sync**: ChipMetadata updates automatically when chips added/removed
- **Uniform Styling**: All chips use consistent blue badge styling

### Migration Notes

- Removed old implementations: ChipDropdownMenu, ChipEditModal, ChipBadgeView
- Kept existing ChipMetadata and SmartChipModels for database compatibility
- ChipTypeRegistry unchanged, still handles chip validation and rendering

The Quick Send feature is now fully implemented with an enhanced chip input system. Users can access it from the Tools section of the navigation menu to send personalized bulk messages with rich inline chips.

## Bug Fixes

### October 14, 2025 - Text Input Issue Fixed
**Issue**: Users were unable to click on or input text into the message body field.

**Root Causes**: 
1. The placeholder text overlay in the ZStack was intercepting hit testing events
2. The frame constraints were not properly allowing the text view to expand and receive interactions
3. The NSTextView was missing proper sizing configuration for autoresizing

**Solution**: 
1. **QuickSendView.swift**:
   - Added `.allowsHitTesting(false)` modifier to the placeholder Text view to prevent it from intercepting user interactions (line 278)
   - Changed frame constraint from `.frame(minHeight: 120)` to `.frame(height: 120)` for fixed sizing (line 290)
   - Reduced padding from default to 8 points for better fit (line 291)
   - Added `.frame(maxWidth: .infinity, maxHeight: .infinity)` to MessageBodyEditor (line 288)

2. **MessageBodyEditor.swift**:
   - Changed ZStack alignment to `.topLeading` for proper positioning (line 22)
   - Replaced `.frame(minHeight: 120)` with `.frame(maxWidth: .infinity, maxHeight: .infinity)` on ChipTextView to allow full expansion (line 36)
   - Added `.zIndex(1000)` to dropdown overlay to ensure proper layering (line 41)

3. **ChipTextView.swift**:
   - Added `autoresizingMask = [.width, .height]` to enable proper resizing (line 48)
   - Set `minSize` to `NSSize(width: 0, height: 100)` to ensure minimum height (line 52)
   - Set `maxSize` to allow unlimited growth (line 53)
   - Set `textContainer?.heightTracksTextView = false` for proper text flow (line 50)
   - Added `drawsBackground = false` to scroll view to prevent visual conflicts (line 61)
   - Improved `handleDropdownKeyEvent` to not prematurely hide dropdown (lines 258-262)

**Files Modified**:
- `UI/Pages/QuickSendView.swift` - Frame sizing and placeholder hit testing fixes
- `UI/Components/MessageBodyEditor.swift` - Frame expansion and layout improvements
- `UI/Components/ChipTextView.swift` - NSTextView sizing configuration and dropdown handling

**Result**: Text input now works correctly. Users can click into the message body field and type freely. The @ mention system continues to function as expected, and the text view properly expands to fill the available space.

### October 15, 2025 - Queued Message Edit Feature
**Enhancement**: Added ability to edit queued messages from the Quick Send queue list.

**Implementation**:
1. **BatchMessageEditModal.swift** (New file):
   - Full-featured modal for editing queued messages
   - Recipients section (read-only display of message recipients)
   - MessageBodyEditor integration for smart chip editing
   - Schedule timing controls (change, reschedule, or clear schedule)
   - Notify when sent checkbox
   - Save/Cancel buttons with keyboard shortcuts (Enter/Escape)
   - 600x600 window size for comfortable editing

2. **QuickSendView.swift** (Updated):
   - Added state variables for edit modal (`showingEditModal`, `messageToEdit`)
   - Implemented `handleEditSave()` method to update messages
   - Wired up edit button in queued messages table to open edit modal
   - Automatic rescheduling when schedule time is changed
   - Success/error notifications after save

3. **SQLiteDataProvider.swift** (Updated):
   - Added `updateBatchMessage()` method for updating existing messages
   - Uses SQL UPDATE statement with transaction support
   - Updates message_template, chip_metadata, recipients, scheduled_time, status, and notification settings
   - Synchronizes in-memory array with database changes
   - Comprehensive logging and error handling

**Features**:
- Edit message content with full smart chip support (same as compose view)
- Modify scheduled time using the same SchedulePickerModal
- Change or remove schedule (convert scheduled message to immediate send)
- Update notification preferences
- Recipients are displayed but cannot be modified (by design)
- Automatic rescheduling via SchedulingService when time changes
- Transaction-based updates ensure data consistency
- Real-time updates in queue view after save

**User Experience**:
1. User clicks edit (pencil icon) on a queued message
2. Edit modal opens with current message content and settings
3. User can modify message text, add/remove chips, and change schedule
4. Clicking "Save Changes" updates the database and reschedules if needed
5. Modal closes and queue view refreshes with updated information
6. Success notification confirms the update

**Files Modified**:
- `UI/Modals/BatchMessageEditModal.swift` - New edit modal component
- `UI/Pages/QuickSendView.swift` - Added edit functionality and modal integration
- `Core/Services/SQLiteDataProvider.swift` - Added updateBatchMessage method

**Result**: Users can now fully edit queued messages including message content, smart chips, and schedule timing. The edit experience matches the compose experience with full smart chip editing support.

### October 15, 2025 - Delete Scheduled Job on Queue Deletion
**Enhancement**: Ensured that deleting a scheduled message from the queue also cancels the scheduled launchd job.

**Implementation**:
1. **QuickSendView.swift** (Updated):
   - Added `handleDelete(message:)` method to properly handle message deletion
   - Checks if message is scheduled and cancels the launchd job via SchedulingService
   - Deletes message from database and memory
   - Shows success notification to user
   - Both queued and history views now use the same delete handler for consistency

**Flow**:
1. User clicks delete (trash icon) on a queued message
2. System checks if message has a scheduled job (`status == .scheduled && scheduledTime != nil`)
3. If scheduled, calls `schedulingService.cancelScheduledMessage()` to remove the launchd job
4. Deletes message from database via `dataProvider.deleteBatchMessage()`
5. Removes message from in-memory array
6. Shows "Message deleted successfully" notification

**Why This Matters**:
- Prevents "orphaned" scheduled jobs that would try to send deleted messages
- Ensures complete cleanup when a user cancels a scheduled message
- Database and scheduling system stay in sync
- Proper error handling if scheduled job doesn't exist or fails to cancel

**Files Modified**:
- `UI/Pages/QuickSendView.swift` - Added handleDelete method with scheduling service integration

**Result**: Deleting a scheduled message now properly cancels both the database entry AND the scheduled launchd job, preventing orphaned jobs and ensuring complete cleanup.

### October 26, 2025 - Helper Script Bundled in App for Portability
**Enhancement**: Moved the Quick Send helper script from Application Support directory into the app bundle for improved portability.

**Problem**: 
- The helper script was dynamically created in `~/Library/Application Support/My_CRM/quick_send_helper.sh` on first launch
- This meant the script was stored outside the app bundle, making the app less portable
- If the app was moved to a different location or machine, the script needed to be recreated

**Solution**:
1. **Created `Resources/quick_send_helper.sh`**:
   - Physical shell script file bundled with the app
   - Contains the same scheduling logic for processing scheduled messages
   - Set to be copied into app bundle during build

2. **Updated `Core/Services/SchedulingService.swift`**:
   - Changed initialization to look for bundled script using `Bundle.main.url(forResource:withExtension:)`
   - Removed `createHelperScript()` method - no longer needed
   - Added fallback to Application Support directory for backward compatibility
   - Helper script path now points to bundled resource

**Benefits**:
- App is fully self-contained and portable
- No need to write to Application Support directory on first launch
- Works immediately after moving the app to a new location
- Simplified initialization code
- Better security - no dynamic script creation

**Files Modified**:
- `Resources/quick_send_helper.sh` - New bundled helper script
- `Core/Services/SchedulingService.swift` - Updated to use bundled script
- `QUICK_SEND_IMPLEMENTATION.md` - Updated documentation

**Result**: The Quick Send helper script is now bundled within the app, making it fully portable and self-contained. The app works correctly regardless of where it's moved or copied.
