# Database Schema Documentation

## Overview

The CRM system now includes a comprehensive database schema that supports groups and group membership management. The database uses SQLite and includes automatic schema management to ensure all required tables and columns exist.

## Database Tables

### Contacts Table

The `contacts` table stores contact information with the following columns:

- `id` - Primary key, auto-incrementing integer
- `phone` - Contact's phone number
- `name` - Full name
- `email` - Email address
- `first_name` - First name
- `last_name` - Last name
- `address` - Physical address
- `notes` - Additional notes
- `creation_date` - When the contact was created
- `business` - Business/organization name
- `contact_group` - Legacy group field
- `birthday` - Birthday information
- `apple_contact_id` - Unique Apple contact identifier
- `profile_photo` - Profile photo as BLOB data
- `first_message_date` - Date of first message
- `last_message_date` - Date of last message
- `total_messages` - Total message count
- `messages_sent` - Messages sent count
- `messages_received` - Messages received count
- `is_primary_user` - Boolean flag for primary user
- `sent_last_message` - Boolean flag for last message sender
- `groups` - **NEW**: JSON string containing group memberships

### Groups Table

The `groups` table stores group information with the following columns:

- `id` - Primary key, TEXT (UUID string)
- `name` - Group name (required)
- `color` - Hex color code for group visualization
- `created_at` - ISO 8601 timestamp of group creation
- `parent_id` - UUID of parent group for hierarchical organization
- `member_phones` - JSON array of phone numbers belonging to this group
- `linked_group_ids` - JSON array of UUIDs for linked groups
- `metadata` - JSON object containing group metadata
- `is_deck` - Boolean flag indicating if this group is a deck
- `participants` - JSON string containing participant contact IDs
- `canvases` - JSON array of canvas IDs where this group appears

## JSON Field Formats

### Groups Field (in contacts table)
```json
{
  "1": 1,
  "5": 5,
  "12": 12
}
```
Where the key is the group ID as a string and the value is the group ID as an integer.

### Participants Field (in groups table) - SOURCE-BASED TRACKING
```json
[
  {
    "id": "+1234567890",
    "name": "John Doe",
    "UUID": "contact-uuid-string",
    "Source": [
      {
        "Type": "Canvas Group Circle",
        "UUID": "group-circle-ui-element-uuid"
      },
      {
        "Type": "Group Tool Bar",
        "UUID": "toolbar-ui-element-uuid"
      }
    ]
  },
  {
    "id": "+0987654321",
    "name": "Jane Smith",
    "UUID": "contact-uuid-string-2",
    "Source": [
      {
        "Type": "Canvas Group Circle",
        "UUID": "group-circle-ui-element-uuid"
      }
    ]
  }
]
```
Each participant has:
- `id`: Phone number (unique identifier)
- `name`: Contact display name
- `UUID`: Contact's UUID
- `Source`: Array of source objects tracking where this membership comes from
  - `Type`: Source type (e.g., "Canvas Group Circle", "Group Tool Bar")
  - `UUID`: UUID of the UI element that added this participant

**Important**: The system uses SOURCE-BASED tracking, meaning:
- Participants can have multiple sources
- Adding a participant merges sources (doesn't overwrite)
- Removing a source only removes that specific source
- Participants are only removed when they have no remaining sources

### Tags Field (in groups table)
```json
["work", "important", "follow-up"]
```
Array of tag strings.

## Database Management

### Universal Database Utility Module

The `database_utils.py` module provides a centralized way to manage database connections and operations:

- **DatabaseManager**: Main class for database operations
- **get_database_manager()**: Get or create global database manager instance
- **ensure_database_connection()**: Ensure database connection is established

### Schema Management

The database manager automatically:
1. Creates missing tables
2. Adds missing columns to existing tables
3. Preserves existing data during schema updates
4. Handles database connection errors with user-friendly dialogs

### Group Membership Operations

The system provides methods to:
- **Add contacts to groups** - Merges sources, doesn't overwrite existing participants
- **Remove contacts from groups** - Removes specific sources only
- **Get all groups for a contact**
- **Get all participants in a group**
- **Automatically update group size and timestamps**

#### Key Methods:

1. **`update_group_participants(group_id, participants_data)`**
   - MERGES new participants with existing ones
   - For existing participants: merges their sources
   - For new participants: adds them to the group
   - Prevents duplicate sources by checking Type+UUID combination
   - Updates group size and timestamp automatically

2. **`remove_group_participant_source(group_id, participants_data)`**
   - Removes specific sources from participants
   - Only removes the participant if no sources remain
   - Preserves participants with remaining sources from other UI elements
   - Updates group size and timestamp automatically

## Integration with Swift Application

### Canvas Group Updates - Source-Based Tracking

When contacts are added to or removed from groups in the canvas interface:

**Adding a Contact:**
1. The Swift `addParticipantToGroup()` is called with source information
2. It creates a participant object with:
   - Contact ID (phone)
   - Contact name
   - Contact UUID
   - Source array with Type and UUID of the UI element
3. Calls Python `update_group_participants` command
4. Python merges the new participant/source with existing participants
5. Group size and timestamp are automatically recalculated

**Removing a Contact:**
1. The Swift `removeParticipantFromGroup()` is called with source information
2. It creates a removal object with the source to remove
3. Calls Python `remove_group_participant_source` command
4. Python removes only the specified source from the participant
5. If no sources remain, the participant is removed entirely
6. Group size and timestamp are automatically recalculated

**Key Benefits:**
- Multiple UI elements can add the same contact without conflict
- Contacts remain in groups until all sources are removed
- Prevents accidental overwrites when multiple operations happen simultaneously
- Full audit trail of where each membership comes from

### Error Handling

- Database connection failures show a dialog with option to open settings
- Missing database files trigger automatic schema creation
- Failed operations are logged and don't crash the application

## Testing

Run the test script to verify database functionality:

```bash
python3 test_database_schema.py
```

This will:
- Test database connection
- Verify all required columns exist
- Test group membership operations
- Clean up test data

## File Structure

```
Resources/
├── database_utils.py              # Universal database management
├── update_group_membership.py     # Group membership update script
├── test_database_schema.py        # Database testing script
├── import_contacts.py             # Updated to use database utils
├── import_imessages.py            # Updated to use database utils
└── evaluate_date_of_first_contact.py  # Updated to use database utils
```

## Usage Examples

### Adding a contact to a group
```python
from database_utils import get_database_manager

db_manager = get_database_manager()
db_manager.update_group_membership(contact_id=1, group_id=5, operation="add")
```

### Getting all groups for a contact
```python
contact_groups = db_manager.get_contact_groups(contact_id=1)
print(f"Contact belongs to groups: {contact_groups}")
```

### Getting all participants in a group
```python
group_participants = db_manager.get_group_participants(group_id=5)
print(f"Group participants: {group_participants}")
```

## Migration Notes

- Existing databases will automatically have the new columns added
- No data loss occurs during schema updates
- The `groups` column in contacts table defaults to empty JSON object `{}`
- The `participants` column in groups table defaults to empty JSON object `{}`
- The `tags` column in groups table defaults to empty JSON array `[]`
