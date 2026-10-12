import sqlite3
import os
from datetime import datetime, timezone
import glob
import json
from database_utils import get_database_manager, ensure_database_connection

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Load settings file - try Application Support first, then fall back to Resources
APP_SUPPORT_DIR = os.path.expanduser("~/Library/Application Support/My_CRM")
APP_SUPPORT_PREFS = os.path.join(APP_SUPPORT_DIR, "User_Settings.json")
RESOURCES_PREFS = os.path.join(SCRIPT_DIR, "User_Settings.json")

if os.path.exists(APP_SUPPORT_PREFS):
    pref_path = APP_SUPPORT_PREFS
elif os.path.exists(RESOURCES_PREFS):
    pref_path = RESOURCES_PREFS
else:
    raise FileNotFoundError("User_Settings.json file not found in Application Support or Resources directory")

with open(pref_path, "r", encoding="utf-8") as f:
    prefs = json.load(f)

USER_PHONE = prefs["user"].get("phone", "")
USER_EMAILS = set([prefs["user"].get("email", "")])
USER_NAME = prefs["user"].get("name", "")
crm_path = os.path.expanduser(prefs["database"]["path"])
crm_path = os.path.abspath(crm_path)

# Normalize phone to last 10 digits
def normalize_phone(p):
    return ''.join(filter(str.isdigit, p))[-10:]

# Convert Apple timestamp to Unix timestamp
def convert_apple_timestamp(ts):
    ts = int(ts)
    if ts > 1e12:  # nanoseconds
        ts //= 1_000_000_000
    elif ts > 1e9:  # milliseconds
        ts //= 1_000
    
    # Convert Apple epoch to Unix epoch
    APPLE_EPOCH_OFFSET = 978307200
    return ts + APPLE_EPOCH_OFFSET

# --- Connect to CRM database ---
# Use the database manager to ensure schema is up to date
db_manager = get_database_manager()
if not ensure_database_connection():
    print("Failed to connect to database. Check settings.")
    exit(1)

crm_conn = db_manager.conn
crm_cur = db_manager.cursor

print("🔄 Starting optimized contact enrichment...")

# --- Check how many contacts need processing ---
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

# If all contacts are already processed, skip the heavy computation
if unprocessed_contacts == 0:
    print("✅ All contacts already processed. Skipping heavy computation.")
    crm_conn.close()
    exit(0)

# --- Mark the primary user ---
placeholders = ','.join(['?'] * len(USER_EMAILS))
crm_cur.execute(f"""
    UPDATE contacts
    SET is_primary_user = 1
    WHERE phone LIKE ? OR email IN ({placeholders})
""", (f"%{USER_PHONE[-10:]}", *USER_EMAILS))

print("✅ Primary user marked")

# --- Build lookup maps for UNPROCESSED contacts only ---
crm_cur.execute("SELECT id, phone FROM contacts WHERE first_message_date IS NULL OR first_message_date = ''")
contact_map = {row[0]: normalize_phone(row[1]) for row in crm_cur.fetchall()}
phone_to_id = {v: k for k, v in contact_map.items()}

print(f"📞 Loaded {len(contact_map)} unprocessed contacts for processing")

# --- Reassign contact_id for messages sent by me ---
# Clear any self-links for sent messages
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

print("✅ Contact IDs reassigned for sent messages (unprocessed contacts only)")

# --- OPTIMIZED: Use SQL aggregation only for unprocessed contacts ---
print("📊 Calculating message statistics using SQL aggregation (unprocessed contacts only)...")

# Create a temporary table with converted timestamps for faster processing
# Only include messages for unprocessed contacts
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

# Use SQL aggregation to calculate stats for each unprocessed contact
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

# Clean up temporary table
crm_cur.execute("DROP TABLE temp_messages")

print("✅ Message statistics calculated and updated")

# Commit changes
crm_conn.commit()
crm_conn.close()

print("✅ Contacts enriched from messages using optimized SQL aggregation.")
print("✅ Only contacts with messages were processed. Contacts without messages remain unprocessed for future checks.")
