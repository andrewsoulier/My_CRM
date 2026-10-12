#!/usr/bin/env python3
"""
Script to get the timestamp of the most recent message in the database.
This is used by the Swift app to show the "Date last run" based on actual message data.
"""

import sys
import json
from datetime import datetime
from database_utils import get_database_manager, ensure_database_connection

def apple_epoch_to_unix(apple_timestamp):
    """Convert Apple epoch (Jan 1, 2001) to Unix timestamp (Jan 1, 1970)"""
    if not apple_timestamp:
        return 0
    
    # Apple epoch starts at Jan 1, 2001, Unix epoch starts at Jan 1, 1970
    # The difference is 978,307,200 seconds (31 years)
    apple_epoch_offset = 978307200
    
    # Handle both seconds and nanoseconds
    if apple_timestamp > 10**12:  # Nanoseconds
        unix_timestamp = (apple_timestamp / 1_000_000_000) + apple_epoch_offset
    else:  # Seconds
        unix_timestamp = apple_timestamp + apple_epoch_offset
    
    return unix_timestamp

def main():
    """Get the last message timestamp and return it as JSON"""
    try:
        # Connect to database
        if not ensure_database_connection():
            print(json.dumps({"success": False, "error": "Failed to connect to database"}))
            return
        
        # Get database manager
        db_manager = get_database_manager()
        
        # Get last message timestamp
        last_timestamp = db_manager.get_last_message_timestamp()
        
        if last_timestamp is None:
            # No messages found
            result = {
                "success": True,
                "timestamp": None,
                "date": None,
                "message": "No messages found in database"
            }
        else:
            # Convert Apple timestamp to Unix timestamp
            unix_timestamp = apple_epoch_to_unix(last_timestamp)
            
            # Convert to readable date
            try:
                date_obj = datetime.fromtimestamp(unix_timestamp)
                formatted_date = date_obj.strftime("%Y-%m-%d %H:%M:%S")
            except (ValueError, OSError):
                formatted_date = "Invalid date"
            
            result = {
                "success": True,
                "timestamp": unix_timestamp,
                "apple_timestamp": last_timestamp,
                "date": formatted_date,
                "message": f"Last message received: {formatted_date}"
            }
        
        print(json.dumps(result))
        
    except Exception as e:
        print(json.dumps({
            "success": False, 
            "error": f"Failed to get last message timestamp: {str(e)}"
        }))
    finally:
        # Clean up database connection
        try:
            db_manager = get_database_manager()
            if db_manager.conn:
                db_manager.disconnect()
        except:
            pass

if __name__ == "__main__":
    main()
