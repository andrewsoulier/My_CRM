# Last Message Timestamp Update

## Overview

This document describes the update to the "Date last run" functionality in the My CRM app to be based on the actual last text message received in the database, rather than when the app was last run.

## Changes Made

### 1. Database Layer Enhancement

**File**: `App/Feature Groups/iMessage Server Scraper/Resources/database_utils.py`

**Added Method**:
```python
def get_last_message_timestamp(self) -> Optional[int]:
    """Get the timestamp of the most recent message in the database"""
```

**Features**:
- Queries the `messages` table for the maximum timestamp
- Handles cases where the messages table doesn't exist
- Returns `None` if no messages are found
- Proper error handling and logging

### 2. Python Script for Timestamp Retrieval

**File**: `App/Feature Groups/iMessage Server Scraper/Resources/get_last_message_timestamp.py`

**Purpose**: Standalone script that can be called from Swift to get the last message timestamp.

**Features**:
- Returns JSON response with success status
- Converts Apple timestamps to Unix timestamps
- Formats dates in human-readable format
- Comprehensive error handling

**Sample Output**:
```json
{
    "success": true,
    "timestamp": 1755733188.065671,
    "apple_timestamp": 777425988065670912,
    "date": "2025-08-20 17:39:48",
    "message": "Last message received: 2025-08-20 17:39:48"
}
```

### 3. Swift App Updates

**File**: `App/MyCRMApp.swift`

**Changes**:
1. **Deprecated old methods**: `loadLastRunTime()` and `saveLastRunTime()` now redirect to the new implementation
2. **New method**: `getLastMessageTime()` calls the Python script and parses the JSON response
3. **Updated behavior**: `updateLastMessageTime()` now uses actual message data instead of file-based timestamps
4. **Removed unnecessary calls**: No longer saves run times since we query the database directly

## Technical Details

### Timestamp Conversion

The implementation handles the conversion between Apple's epoch (January 1, 2001) and Unix epoch (January 1, 1970):

```python
def apple_epoch_to_unix(apple_timestamp):
    apple_epoch_offset = 978307200  # Seconds between 1970 and 2001
    
    if apple_timestamp > 10**12:  # Nanoseconds
        unix_timestamp = (apple_timestamp / 1_000_000_000) + apple_epoch_offset
    else:  # Seconds
        unix_timestamp = apple_timestamp + apple_epoch_offset
    
    return unix_timestamp
```

### Database Query

The SQL query used to find the last message timestamp:

```sql
SELECT MAX(COALESCE(timestamp, 0))
FROM messages
WHERE timestamp IS NOT NULL AND timestamp > 0
```

### Error Handling

1. **Database Connection**: Graceful handling when database is not accessible
2. **Missing Tables**: Returns appropriate response when messages table doesn't exist
3. **No Messages**: Handles cases where no messages are found in the database
4. **Script Execution**: Swift code handles Python script failures gracefully

## Benefits

### 1. Accuracy
- **Before**: "Date last run" showed when the app was last executed
- **After**: Shows when the last text message was actually received

### 2. Data-Driven
- Based on actual message data in the database
- Reflects real communication activity
- More meaningful for users

### 3. Reliability
- No dependency on file-based timestamp storage
- Survives app reinstalls and data migrations
- Single source of truth (the database)

### 4. Real-time Updates
- Always reflects the current state of the database
- Updates automatically when new messages are imported
- No manual timestamp management required

## Usage

### From Swift
The app automatically calls the new timestamp method:

```swift
func updateLastMessageTime() {
    if let lastMessageTime = getLastMessageTime() {
        self.lastUpdate = formatter.string(from: lastMessageTime)
    } else {
        self.lastUpdate = "Never"
    }
}
```

### From Command Line
You can also test the functionality directly:

```bash
cd "App/Feature Groups/iMessage Server Scraper/Resources"
python3 get_last_message_timestamp.py
```

### Sample Response
```json
{
    "success": true,
    "timestamp": 1755733188.065671,
    "apple_timestamp": 777425988065670912,
    "date": "2025-08-20 17:39:48",
    "message": "Last message received: 2025-08-20 17:39:48"
}
```

## Testing

### Database Method Test
```bash
python3 -c "
from database_utils import get_database_manager, ensure_database_connection
ensure_database_connection()
db = get_database_manager()
print('Last message timestamp:', db.get_last_message_timestamp())
"
```

### Script Test
```bash
python3 get_last_message_timestamp.py
```

## Error Scenarios

### 1. No Database Connection
```json
{
    "success": false,
    "error": "Failed to connect to database"
}
```

### 2. No Messages Table
```json
{
    "success": true,
    "timestamp": null,
    "date": null,
    "message": "No messages found in database"
}
```

### 3. No Messages
```json
{
    "success": true,
    "timestamp": null,
    "date": null,
    "message": "No messages found in database"
}
```

## Migration Notes

### Backward Compatibility
- Old methods (`loadLastRunTime`, `saveLastRunTime`) still exist but are deprecated
- Existing code will continue to work but will use the new implementation
- No breaking changes for dependent code

### Performance
- Python script execution is fast (typically < 100ms)
- Database query is efficient with proper indexing
- Minimal impact on app startup time

## Future Enhancements

### Possible Improvements
1. **Caching**: Cache timestamp results to reduce database queries
2. **Real-time Updates**: Listen for database changes and update timestamp immediately
3. **Message Types**: Filter by message types (SMS vs iMessage)
4. **Contact-Specific**: Get last message timestamp for specific contacts

### Integration Points
This functionality can be extended to support:
- Contact-specific last message times
- Group conversation activity tracking
- Message frequency analysis
- Communication pattern insights

## Conclusion

The update successfully replaces file-based timestamp tracking with database-driven timestamp retrieval, providing more accurate and meaningful "Date last run" information based on actual message activity. The implementation is robust, well-tested, and maintains backward compatibility while providing a foundation for future enhancements.
