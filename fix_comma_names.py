#!/usr/bin/env python3
"""
Fix Comma-Separated Names in Database

This script identifies contacts with names in "Last, First" format (indicated by a comma)
and converts them to "First Last" format in the `name` field.
"""

import os
import sys
import sqlite3
import logging
from typing import List, Tuple, Optional

# Add the iMessage Server Scraper Resources to path for database_utils
script_dir = os.path.dirname(os.path.abspath(__file__))
resources_path = os.path.join(script_dir, "App", "Feature Groups", "iMessage Server Scraper", "Resources")
sys.path.insert(0, resources_path)

from database_utils import DatabaseManager

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(os.path.join(script_dir, 'fix_comma_names.log'))
    ]
)
logger = logging.getLogger(__name__)

# Database path
DB_PATH = "/Users/andrewsoulier/My_CRM Project/my_crm_bannanas.db"


def convert_comma_name(name: str) -> Optional[str]:
    """
    Convert name from "Last, First" format to "First Last" format.
    
    Args:
        name: Name in "Last, First" format (or any format with comma)
    
    Returns:
        Converted name in "First Last" format, or None if conversion fails
    """
    if not name or ',' not in name:
        return None
    
    # Split on comma
    parts = name.split(',', 1)  # Split into max 2 parts (handle "Last, First, Jr.")
    
    if len(parts) != 2:
        # If split didn't produce exactly 2 parts, try taking first two parts
        all_parts = name.split(',')
        if len(all_parts) >= 2:
            parts = [all_parts[0].strip(), ','.join(all_parts[1:]).strip()]
        else:
            logger.warning(f"Unexpected name format: {name}")
            return None
    
    last_part = parts[0].strip()
    first_part = parts[1].strip()
    
    # Check for empty parts
    if not first_part or not last_part:
        logger.warning(f"Empty parts after splitting: {name}")
        return None
    
    # Reconstruct as "First Last"
    converted_name = f"{first_part} {last_part}"
    
    return converted_name


def find_comma_names(db_manager: DatabaseManager) -> List[Tuple[int, str, str]]:
    """
    Find all contacts with comma-separated names.
    
    Args:
        db_manager: Database manager instance
    
    Returns:
        List of tuples (id, original_name, converted_name)
    """
    try:
        db_manager.cursor.execute("""
            SELECT id, name FROM contacts 
            WHERE name LIKE '%,%'
            ORDER BY id
        """)
        
        results = []
        rows = db_manager.cursor.fetchall()
        
        for row in rows:
            contact_id, original_name = row
            converted_name = convert_comma_name(original_name)
            
            if converted_name:
                results.append((contact_id, original_name, converted_name))
            else:
                logger.warning(f"Could not convert name for contact ID {contact_id}: {original_name}")
        
        return results
    
    except Exception as e:
        logger.error(f"Error finding comma-separated names: {e}")
        raise


def update_contact_name(db_manager: DatabaseManager, contact_id: int, new_name: str) -> bool:
    """
    Update the name field for a contact.
    
    Args:
        db_manager: Database manager instance
        contact_id: Contact ID to update
        new_name: New name value
    
    Returns:
        True if successful, False otherwise
    """
    try:
        db_manager.cursor.execute("""
            UPDATE contacts 
            SET name = ? 
            WHERE id = ?
        """, (new_name, contact_id))
        return True
    except Exception as e:
        logger.error(f"Error updating contact ID {contact_id}: {e}")
        return False


def main():
    """Main function to fix comma-separated names"""
    logger.info("=" * 60)
    logger.info("Starting Comma-Separated Name Fix")
    logger.info("=" * 60)
    
    # Initialize database manager
    db_manager = DatabaseManager(DB_PATH)
    
    if not db_manager.connect():
        logger.error(f"Failed to connect to database at {DB_PATH}")
        return 1
    
    logger.info(f"Connected to database: {DB_PATH}")
    
    try:
        # Find all contacts with comma-separated names
        logger.info("Searching for contacts with comma-separated names...")
        contacts_to_fix = find_comma_names(db_manager)
        
        total_found = len(contacts_to_fix)
        logger.info(f"Found {total_found} contacts with comma-separated names")
        
        if total_found == 0:
            logger.info("No contacts found with comma-separated names. Exiting.")
            return 0
        
        # Show sample of changes
        logger.info("\nSample of changes to be made:")
        for i, (contact_id, original, converted) in enumerate(contacts_to_fix[:10], 1):
            logger.info(f"  {i}. ID {contact_id}: '{original}' → '{converted}'")
        if total_found > 10:
            logger.info(f"  ... and {total_found - 10} more")
        
        # Update contacts
        logger.info(f"\nUpdating {total_found} contacts...")
        updated_count = 0
        failed_count = 0
        
        for contact_id, original_name, converted_name in contacts_to_fix:
            if update_contact_name(db_manager, contact_id, converted_name):
                updated_count += 1
                if updated_count % 100 == 0:
                    logger.info(f"Progress: {updated_count}/{total_found} contacts updated...")
            else:
                failed_count += 1
        
        # Commit changes
        db_manager.conn.commit()
        
        logger.info("\n" + "=" * 60)
        logger.info("Update Complete!")
        logger.info("=" * 60)
        logger.info(f"  - Total contacts found: {total_found}")
        logger.info(f"  - Successfully updated: {updated_count}")
        logger.info(f"  - Failed: {failed_count}")
        logger.info("=" * 60)
        
        return 0
        
    except Exception as e:
        db_manager.conn.rollback()
        logger.error(f"Error during name fix: {e}")
        return 1
    
    finally:
        db_manager.disconnect()


if __name__ == "__main__":
    sys.exit(main())

