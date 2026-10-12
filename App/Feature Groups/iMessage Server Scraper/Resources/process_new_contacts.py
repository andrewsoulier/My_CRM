#!/usr/bin/env python3
"""
Process new contacts for first contact date calculation.
This script only processes contacts that haven't been processed yet,
making it much faster and reducing database locking.
"""

import sqlite3
import os
import json
from database_utils import get_database_manager, ensure_database_connection

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Load settings file
APP_SUPPORT_DIR = os.path.expanduser("~/Library/Application Support/My_CRM")
APP_SUPPORT_PREFS = os.path.join(APP_SUPPORT_DIR, "User_Settings.json")
RESOURCES_PREFS = os.path.join(SCRIPT_DIR, "User_Settings.json")

if os.path.exists(APP_SUPPORT_PREFS):
    pref_path = APP_SUPPORT_PREFS
elif os.path.exists(RESOURCES_PREFS):
    pref_path = RESOURCES_PREFS
else:
    raise FileNotFoundError("User_Settings.json file not found")

with open(pref_path, "r", encoding="utf-8") as f:
    prefs = json.load(f)

USER_PHONE = prefs["user"].get("phone", "")
USER_EMAILS = set([prefs["user"].get("email", "")])

def normalize_phone(p):
    return ''.join(filter(str.isdigit, p))[-10:]

def main():
    print("🔄 Processing new contacts for first contact date...")
    
    # Connect to database
    db_manager = get_database_manager()
    if not ensure_database_connection():
        print("❌ Failed to connect to database. Check settings.")
        exit(1)

    crm_conn = db_manager.conn
    crm_cur = db_manager.cursor

    # Check how many new contacts need processing
    crm_cur.execute("""
        SELECT 
            COUNT(*) as total_contacts,
            SUM(CASE WHEN first_message_date IS NOT NULL AND first_message_date != '' THEN 1 ELSE 0 END) as processed_contacts,
            SUM(CASE WHEN first_message_date IS NULL OR first_message_date = '' THEN 1 ELSE 0 END) as unprocessed_contacts
        FROM contacts
    """)
    stats = crm_cur.fetchone()
    total_contacts, processed_contacts, unprocessed_contacts = stats

    print(f"📊 Contact processing status:")
    print(f"   Total contacts: {total_contacts}")
    print(f"   Already processed: {processed_contacts}")
    print(f"   Need processing: {unprocessed_contacts}")

    # If no new contacts, exit early
    if unprocessed_contacts == 0:
        print("✅ No new contacts to process.")
        crm_conn.close()
        return

    print(f"🔄 Processing {unprocessed_contacts} new contacts...")

    # Mark the primary user
    placeholders = ','.join(['?'] * len(USER_EMAILS))
    crm_cur.execute(f"""
        UPDATE contacts
        SET is_primary_user = 1
        WHERE phone LIKE ? OR email IN ({placeholders})
    """, (f"%{USER_PHONE[-10:]}", *USER_EMAILS))

    # Build lookup maps for unprocessed contacts only
    crm_cur.execute("SELECT id, phone FROM contacts WHERE first_message_date IS NULL OR first_message_date = ''")
    contact_map = {row[0]: normalize_phone(row[1]) for row in crm_cur.fetchall()}
    print(f"📞 Loaded {len(contact_map)} unprocessed contacts")

    # Reassign contact_id for messages sent by me (only for unprocessed contacts)
    crm_cur.execute("""
        UPDATE messages
        SET contact_id = NULL
        WHERE is_from_me = 1 AND contact_id = (
            SELECT id FROM contacts WHERE is_primary_user = 1
        )
    """)

    crm_cur.execute("SELECT id, phone FROM contacts WHERE is_primary_user = 0 AND (first_message_date IS NULL OR first_message_date = '')")
    others = crm_cur.fetchall()
    for cid, phone in others:
        norm_phone = normalize_phone(phone)
        crm_cur.execute("""
            UPDATE messages
            SET contact_id = ?
            WHERE is_from_me = 1 AND substr(phone_number, -10) = ?
        """, (cid, norm_phone))

    print("✅ Contact IDs reassigned for sent messages")

    # Calculate message statistics for unprocessed contacts only
    print("📊 Calculating message statistics...")

    # Create temporary table with converted timestamps for unprocessed contacts only
    crm_cur.execute("""
        CREATE TEMPORARY TABLE IF NOT EXISTS temp_messages AS
        SELECT 
            contact_id,
            is_from_me,
            CASE 
                WHEN timestamp > 1000000000000 THEN (timestamp / 1000000000) + 978307200
                WHEN timestamp > 1000000000 THEN (timestamp / 1000) + 978307200
                ELSE timestamp + 978307200
            END as unix_timestamp
        FROM messages 
        WHERE contact_id IS NOT NULL 
        AND contact_id IN (SELECT id FROM contacts WHERE first_message_date IS NULL OR first_message_date = '')
    """)

    # Update contacts with message statistics
    crm_cur.execute("""
        UPDATE contacts SET
            first_message_date = (
                SELECT datetime(MIN(unix_timestamp), 'unixepoch', 'utc')
                FROM temp_messages 
                WHERE temp_messages.contact_id = contacts.id
            ),
            last_message_date = (
                SELECT datetime(MAX(unix_timestamp), 'unixepoch', 'utc')
                FROM temp_messages 
                WHERE temp_messages.contact_id = contacts.id
            ),
            total_messages = (
                SELECT COUNT(*)
                FROM temp_messages 
                WHERE temp_messages.contact_id = contacts.id
            ),
            messages_sent = (
                SELECT COUNT(*)
                FROM temp_messages 
                WHERE temp_messages.contact_id = contacts.id AND is_from_me = 1
            ),
            messages_received = (
                SELECT COUNT(*)
                FROM temp_messages 
                WHERE temp_messages.contact_id = contacts.id AND is_from_me = 0
            ),
            sent_last_message = (
                SELECT is_from_me
                FROM temp_messages 
                WHERE temp_messages.contact_id = contacts.id
                ORDER BY unix_timestamp DESC
                LIMIT 1
            )
        WHERE id IN (SELECT DISTINCT contact_id FROM temp_messages)
    """)

    # Note: We don't mark contacts without messages as processed
    # This allows them to be checked again later when new messages might arrive

    # Clean up
    crm_cur.execute("DROP TABLE temp_messages")
    crm_conn.commit()
    crm_conn.close()

    print("✅ New contacts processed successfully!")
    print("✅ Only contacts with messages were processed. Contacts without messages remain unprocessed for future checks.")

if __name__ == "__main__":
    main()
