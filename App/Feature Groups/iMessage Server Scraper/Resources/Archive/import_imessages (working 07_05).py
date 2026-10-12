import os
import sqlite3
import datetime
from Modules import imessage_tools
import glob


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CHAT_DB = os.path.expanduser("~/Library/Messages/chat.db")
CRM_DB_PATH = os.path.join(SCRIPT_DIR, "my_crm.db")
LOG_PATH = os.path.join(SCRIPT_DIR, "Logs", "imessage_tools_log.txt")

os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
if not os.path.exists(LOG_PATH):
    with open(LOG_PATH, "w") as f:
        f.write(f"{datetime.datetime.now()}: Log file created.\n")

print("📥 Reading messages from chat.db...")
# Dynamically select the first .vcf file in the script directory, if present
vcf_files = glob.glob(os.path.expanduser("~/CRM/*.vcf"))
USER_PHONE = ""
USER_EMAILS = set()
USER_NAME = ""

if vcf_files:
    with open(vcf_files[0], "r", encoding="utf-8") as f:
        vcard = f.read()
        import re
        # Extract the phone number (last 10 digits of first TEL entry)
        phone_match = re.search(r'TEL[^:]*:(\+?[\d\s\-()]+)', vcard)
        if phone_match:
            USER_PHONE = ''.join(filter(str.isdigit, phone_match.group(1)))[-10:]

        # Extract email addresses
        email_matches = re.findall(r'EMAIL[^:]*:([^\n\r]+)', vcard)
        USER_EMAILS = set(email_matches)

        # Extract full name
        fn_match = re.search(r'FN:(.+)', vcard)
        if fn_match:
            USER_NAME = fn_match.group(1).strip()
else:
    raise FileNotFoundError("No .vcf file found in the CRM directory.")
messages = imessage_tools.read_messages(CHAT_DB, n=None, self_number=USER_PHONE, human_readable_date=False)

print(f"📦 Storing {len(messages)} messages to {CRM_DB_PATH}...")
conn = sqlite3.connect(CRM_DB_PATH)
cur = conn.cursor()

# Drop and recreate messages table if guid is not the primary key
cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='messages'")
table_exists = cur.fetchone()

if table_exists:
    cur.execute("PRAGMA table_info(messages)")
    columns_info = cur.fetchall()
    guid_is_primary = any(col[1] == "guid" and col[5] for col in columns_info)
    if not guid_is_primary:
        cur.execute("DROP TABLE IF EXISTS messages")

cur.execute("""
CREATE TABLE IF NOT EXISTS messages (
    guid TEXT,
    rowid INTEGER,
    body TEXT,
    phone_number TEXT,
    is_from_me BOOLEAN,
    cache_roomname TEXT,
    group_chat_name TEXT,
    timestamp INTEGER,
    service TEXT,
    account TEXT,
    chat_id TEXT,
    attributedBody BLOB,
    subject TEXT,
    country TEXT,
    error INTEGER,
    date_read INTEGER,
    date_delivered INTEGER,
    is_sent INTEGER,
    is_read INTEGER,
    has_attachments BOOLEAN DEFAULT 0,
    contact_id INTEGER,
    message_type TEXT,
    is_first_message INTEGER DEFAULT 0,
    is_last_message INTEGER DEFAULT 0
)
""")

# --- Begin schema validation block ---
required_schema = {
    "contacts": [
        ("id", "INTEGER PRIMARY KEY AUTOINCREMENT"),
        ("phone", "TEXT UNIQUE"),
        ("name", "TEXT"),
        ("email", "TEXT"),
        ("first_name", "TEXT"),
        ("last_name", "TEXT"),
        ("address", "TEXT"),
        ("notes", "TEXT"),
        ("creation_date", "TEXT"),
        ("business", "TEXT"),
        ("contact_group", "TEXT"),
        ("birthday", "TEXT"),
        ("apple_contact_id", "TEXT"),
        ("first_message_date", "TEXT"),
        ("last_message_date", "TEXT"),
        ("total_messages", "INTEGER"),
        ("messages_sent", "INTEGER"),
        ("messages_received", "INTEGER"),
        ("is_primary_user", "INTEGER DEFAULT 0"),
        ("sent_last_message", "INTEGER"),
    ],
    "messages": [
        ("guid", "TEXT"),
        ("rowid", "INTEGER"),
        ("body", "TEXT"),
        ("phone_number", "TEXT"),
        ("is_from_me", "BOOLEAN"),
        ("cache_roomname", "TEXT"),
        ("group_chat_name", "TEXT"),
        ("timestamp", "INTEGER"),
        ("service", "TEXT"),
        ("account", "TEXT"),
        ("chat_id", "TEXT"),
        ("attributedBody", "BLOB"),
        ("subject", "TEXT"),
        ("country", "TEXT"),
        ("error", "INTEGER"),
        ("date_read", "INTEGER"),
        ("date_delivered", "INTEGER"),
        ("is_sent", "INTEGER"),
        ("is_read", "INTEGER"),
        ("has_attachments", "BOOLEAN DEFAULT 0"),
        ("contact_id", "INTEGER"),
        ("message_type", "TEXT"),
        ("is_first_message", "INTEGER DEFAULT 0"),
        ("is_last_message", "INTEGER DEFAULT 0")
    ],
    "group_participants": [
        ("chat_id", "TEXT"),
        ("participant", "TEXT")
    ]
}

# Ensure all required tables and columns exist
for table, columns in required_schema.items():
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table,))
    if not cur.fetchone():
        columns_def = ", ".join([f"{name} {type_}" for name, type_ in columns])
        cur.execute(f"CREATE TABLE IF NOT EXISTS {table} ({columns_def})")
    else:
        existing_cols = set(row[1] for row in cur.execute(f"PRAGMA table_info({table})").fetchall())
        for col_name, col_type in columns:
            if col_name not in existing_cols:
                cur.execute(f"ALTER TABLE {table} ADD COLUMN {col_name} {col_type}")
# --- End schema validation block ---

required_columns = [
    ("rowid", "INTEGER PRIMARY KEY"),
    ("guid", "TEXT"),
    ("body", "TEXT"),
    ("phone_number", "TEXT"),
    ("is_from_me", "BOOLEAN"),
    ("cache_roomname", "TEXT"),
    ("group_chat_name", "TEXT"),
    ("timestamp", "INTEGER"),
    ("service", "TEXT"),
    ("account", "TEXT"),
    ("chat_id", "TEXT"),
    ("attributedBody", "BLOB"),
    ("subject", "TEXT"),
    ("country", "TEXT"),
    ("error", "INTEGER"),
    ("date_read", "INTEGER"),
    ("date_delivered", "INTEGER"),
    ("is_sent", "INTEGER"),
    ("is_read", "INTEGER"),
    ("has_attachments", "BOOLEAN DEFAULT 0"),
    ("contact_id", "INTEGER"),
    ("message_type", "TEXT"),
    ("is_first_message", "INTEGER DEFAULT 0"),
    ("is_last_message", "INTEGER DEFAULT 0")
]

existing_columns = set(row[1] for row in cur.execute("PRAGMA table_info(messages)").fetchall())
for col_name, col_type in required_columns:
    if col_name not in existing_columns:
        cur.execute(f"ALTER TABLE messages ADD COLUMN {col_name} {col_type}")

first_message_tracker = {}

for msg in messages:
    # If a sender phone number is present, associate it with a contact
    contact_id = None
    phone = msg.get("phone_number")
    associated_message_type = msg.get("associated_message_type")

    if phone:
        cur.execute("INSERT OR IGNORE INTO contacts (phone) VALUES (?)", (phone,))
        cur.execute("SELECT id FROM contacts WHERE phone = ?", (phone,))
        result = cur.fetchone()
        if result:
            contact_id = result[0]
            # Increment messages_received if the message is not from self
            if not msg.get("is_from_me"):
                cur.execute(
                    "UPDATE contacts SET messages_received = COALESCE(messages_received, 0) + 1 WHERE id = ?",
                    (contact_id,)
                )

    # If the message is a tapback (like thumbs-up), label it accordingly
    if associated_message_type == 1:
        message_type = "tapback"
    elif associated_message_type == 2:
        message_type = "reaction"
    else:
        message_type = None

    def decode_if_bytes(value):
        if isinstance(value, (bytes, bytearray, memoryview)):
            try:
                return value.tobytes().decode('utf-8', errors='replace') if isinstance(value, memoryview) else value.decode('utf-8', errors='replace')
            except Exception:
                return None
        return value

    msg["body"] = decode_if_bytes(msg.get("body"))
    msg["attributedBody"] = decode_if_bytes(msg.get("attributedBody"))

    cur.execute("""
        INSERT OR IGNORE INTO messages (
            guid, rowid, body, phone_number, is_from_me, cache_roomname, group_chat_name, timestamp,
            service, account, chat_id, attributedBody, subject, country, error,
            date_read, date_delivered, is_sent, is_read, has_attachments,
            contact_id, message_type, is_first_message
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        msg.get("guid"),
        msg.get("rowid"),
        msg.get("body"),
        phone,
        msg.get("is_from_me"),
        msg.get("cache_roomname"),
        msg.get("group_chat_name"),
        msg.get("date"),
        msg.get("service"),
        msg.get("account"),
        msg.get("chat_id"),
        msg.get("attributedBody"),
        msg.get("subject"),
        msg.get("country"),
        msg.get("error"),
        msg.get("date_read"),
        msg.get("date_delivered"),
        msg.get("is_sent"),
        msg.get("is_read"),
        msg.get("has_attachments", 0),
        contact_id,
        message_type,
        0
    ))

    with open(LOG_PATH, "a") as log_file:
        log_file.write(f"{datetime.datetime.now()}: {str(msg)}\n")

conn.commit()
print("🔁 Updating first and last message flags...")
# Reset all values
cur.execute("UPDATE messages SET is_first_message = 0, is_last_message = 0")

# Mark first and last message per contact_id
cur.execute("""
    UPDATE messages SET is_first_message = 1
    WHERE rowid IN (
        SELECT rowid FROM messages
        WHERE contact_id IS NOT NULL
        GROUP BY contact_id
        HAVING MIN(timestamp)
    )
""")
cur.execute("""
    UPDATE messages SET is_last_message = 1
    WHERE rowid IN (
        SELECT rowid FROM messages
        WHERE contact_id IS NOT NULL
        GROUP BY contact_id
        HAVING MAX(timestamp)
    )
""")
conn.commit()
conn.close()
print("✅ Message import and logging complete.")