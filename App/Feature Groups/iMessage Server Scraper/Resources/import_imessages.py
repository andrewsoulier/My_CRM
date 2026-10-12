import subprocess
import shutil
import time
import os
import sqlite3
import datetime
from Modules import imessage_tools
import glob
import json
import logging
from database_utils import get_database_manager, ensure_database_connection

# -----------------------------------------------------------------------------
# Logging & helpers
# -----------------------------------------------------------------------------
LOGGER = logging.getLogger("MyCRM")



def have(cmd: str) -> bool:
    return shutil.which(cmd) is not None


def safe_notify(title: str, message: str):
    """Best-effort macOS notification that never raises or blocks.
    Uses osascript notification and optionally terminal-notifier if installed.
    """
    # osascript notification (non-blocking; do not fail the script if it errors)
    osa = "/usr/bin/osascript"
    # Pre-escape double quotes for AppleScript to avoid backslashes inside f-string expressions
    safe_title = str(title).replace('"', '\\"')
    safe_message = str(message).replace('"', '\\"')
    script = f'display notification "{safe_message}" with title "{safe_title}"'
    try:
        if os.path.isfile(osa) and os.access(osa, os.X_OK):
            subprocess.run([osa, "-e", script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    except Exception as e:
        try:
            LOGGER.warning("osascript notification failed: %s", e)
        except Exception:
            pass

    # terminal-notifier (optional)
    try:
        if have("terminal-notifier"):
            subprocess.run([
                "terminal-notifier",
                "-title", title,
                "-message", message,
                "-sound", "default",
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    except Exception as e:
        try:
            LOGGER.warning("terminal-notifier failed: %s", e)
        except Exception:
            pass


def apple_epoch_to_dt(value: int) -> datetime.datetime:
    """Convert Apple epoch (Jan 1, 2001) timestamps to datetime.
    Accepts seconds or nanoseconds; returns a safe datetime on error.
    """
    if not value:
        return datetime.datetime.fromtimestamp(0)
    try:
        # Heuristic: >1e12 → nanoseconds; else seconds
        if value > 10**12:
            secs = (value / 1_000_000_000) + 978_307_200
        else:
            secs = value + 978_307_200
        return datetime.datetime.fromtimestamp(secs)
    except Exception:
        return datetime.datetime.fromtimestamp(0)


# -----------------------------------------------------------------------------
# Paths & config
# -----------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Prefer environment provided by Start.py; fall back to User_Settings.json if present
ENV_DB = os.environ.get("MYCRM_DB")
ENV_LOG_DIR = os.environ.get("MYCRM_LOG_DIR")

# Try Application Support first, then fall back to Resources directory
APP_SUPPORT_DIR = os.path.expanduser("~/Library/Application Support/My_CRM")
APP_SUPPORT_PREFS = os.path.join(APP_SUPPORT_DIR, "User_Settings.json")
RESOURCES_PREFS = os.path.join(SCRIPT_DIR, "User_Settings.json")

prefs = {}
if os.path.exists(APP_SUPPORT_PREFS):
    PREFS_PATH = APP_SUPPORT_PREFS
elif os.path.exists(RESOURCES_PREFS):
    PREFS_PATH = RESOURCES_PREFS
else:
    PREFS_PATH = None

if PREFS_PATH:
    try:
        with open(PREFS_PATH, "r", encoding="utf-8") as f:
            prefs = json.load(f)
    except Exception as e:
        print(f"⚠️ Could not read User_Settings.json: {e}")

user_prefs = prefs.get("user", {}) if isinstance(prefs.get("user", {}), dict) else {}
USER_PHONE = user_prefs.get("phone", "")
USER_EMAILS = set([user_prefs.get("email", "")])
USER_NAME = user_prefs.get("name", "")

db_pref_path = (prefs.get("database", {}) or {}).get("path") if isinstance(prefs.get("database", {}), dict) else None
db_pref_path = os.path.expanduser(db_pref_path) if db_pref_path else None

if ENV_DB:
    CRM_DB_PATH = os.path.abspath(os.path.expanduser(ENV_DB))
elif db_pref_path and os.path.exists(db_pref_path):
    CRM_DB_PATH = os.path.abspath(db_pref_path)
else:
    err = ("❌ No database path found. Set MYCRM_DB or provide 'database.path' in User_Settings.json.\n"
           "Aborting import to avoid creating a new/empty database.")
    try:
        LOGGER.error(err)
    except Exception:
        pass
    raise SystemExit(err)

CHAT_DB = os.path.expanduser("~/Library/Messages/chat.db")

 # Default log directory: Application Support/My_CRM/logs
default_log_dir = os.path.expanduser("~/Library/Application Support/My_CRM/logs")
LOG_DIR = ENV_LOG_DIR if ENV_LOG_DIR else default_log_dir
os.makedirs(LOG_DIR, exist_ok=True)
LOG_PATH = os.path.join(LOG_DIR, "import_imessages.log")

# Initialize logging sinks (file + console)
if not LOGGER.handlers:
    LOGGER.setLevel(os.environ.get("MYCRM_LOG_LEVEL", "INFO"))
    fh = logging.FileHandler(LOG_PATH, encoding="utf-8")
    fh.setLevel(LOGGER.level)
    ch = logging.StreamHandler()
    ch.setLevel(LOGGER.level)
    fmt = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
    fh.setFormatter(fmt)
    ch.setFormatter(fmt)
    LOGGER.addHandler(fh)
    LOGGER.addHandler(ch)
LOGGER.info("Logging initialized at %s", LOG_PATH)

LOGGER.info("Import starting. DB=%s, CHAT_DB=%s, LOG=%s", ENV_DB or db_pref_path, CHAT_DB, LOG_PATH)

# -----------------------------------------------------------------------------
# Ensure minimal schema and pull last timestamp
# -----------------------------------------------------------------------------
# Use the database manager to ensure schema is up to date
db_manager = get_database_manager()
if not ensure_database_connection():
    LOGGER.error("Failed to connect to database. Check settings.")
    sys.exit(1)

conn = db_manager.conn
cur = db_manager.cursor

required_tables = {
    "messages": [
        ("guid", "TEXT PRIMARY KEY"),
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
        ("is_last_message", "INTEGER DEFAULT 0"),
        ("is_new", "INTEGER DEFAULT 0"),
        ("source", "TEXT DEFAULT 'imessage'")
    ],
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
        ("sent_last_message", "INTEGER")
    ],
    "group_participants": [
        ("chat_id", "TEXT"),
        ("participant", "TEXT")
    ]
}

for table_name, columns in required_tables.items():
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table_name,))
    exists = cur.fetchone()
    if not exists:
        col_defs = ", ".join([f"{col} {dtype}" for col, dtype in columns])
        cur.execute(f"CREATE TABLE {table_name} ({col_defs})")
    else:
        existing = set(r[1] for r in cur.execute(f"PRAGMA table_info({table_name})"))
        for col, dtype in columns:
            if col not in existing:
                cur.execute(f"ALTER TABLE {table_name} ADD COLUMN {col} {dtype}")

cur.execute(
    """
    SELECT
        MAX(COALESCE(timestamp, 0)),
        MAX(COALESCE(date_read, 0)),
        MAX(COALESCE(date_delivered, 0))
    FROM messages
    """
)
row = cur.fetchone()
last_run_timestamp = max([t for t in (row or []) if t]) if row and any(row) else 0
if last_run_timestamp > 0:
    readable_time = apple_epoch_to_dt(last_run_timestamp)
    print(f"🕓 Last recorded message timestamp: {readable_time}")
else:
    print(f"🕓 No previous message timestamps found at {CRM_DB_PATH} — starting fresh.")
# Don't close the connection here - it's needed later
# conn.close()

# -----------------------------------------------------------------------------
# Notify start (non-blocking)
# -----------------------------------------------------------------------------
readable_start_time = (
    "start of history" if last_run_timestamp == 0 else apple_epoch_to_dt(last_run_timestamp).strftime('%Y-%m-%d %H:%M:%S')
)
safe_notify("My CRM", f"📲 Importing messages received after {readable_start_time} → {CRM_DB_PATH}")

# -----------------------------------------------------------------------------
# Read messages from chat.db
# -----------------------------------------------------------------------------
print("📥 Reading messages from chat.db...")
mac_absolute_min_timestamp = last_run_timestamp
messages = imessage_tools.read_messages(
    CHAT_DB,
    n=None,
    self_number=USER_PHONE,
    human_readable_date=False,
    min_timestamp=mac_absolute_min_timestamp
)

# --- Diagnostics: how many messages did we collect? ---
try:
    LOGGER.info("Read %s raw messages from chat.db after min_timestamp=%s", len(messages), mac_absolute_min_timestamp)
except Exception:
    pass
# --- Normalize messages so NULLs don't break inserts ---
def _normalize_message(m: dict) -> dict:
    m = dict(m)
    # text-like fields
    for k in ("body","subject","country","cache_roomname","group_chat_name","service","account","chat_id"):
        if m.get(k) is None:
            m[k] = ""
    # int/bool-ish fields
    for k in ("date_read","date_delivered","is_sent","is_read","error","associated_message_type"):
        if m.get(k) is None:
            m[k] = 0
    ha = m.get("has_attachments")
    m["has_attachments"] = 1 if ha in (True, 1, "1") else 0
    m["is_from_me"] = 1 if m.get("is_from_me") in (True, 1, "1") else 0
    # timestamp unification
    m["timestamp"] = m.get("timestamp", m.get("date"))
    # guid fallback
    if not m.get("guid"):
        m["guid"] = f"ROWID-{m.get('rowid')}"
    return m
messages = [_normalize_message(m) for m in (messages or [])]
if messages:
    try:
        ts_vals = [m.get("timestamp") or 0 for m in messages]
        LOGGER.info("After normalize: %s messages. ts(min/max)=%s/%s, sample guid=%s",
                    len(messages), min(ts_vals), max(ts_vals), messages[0].get("guid"))
    except Exception:
        pass
else:
    LOGGER.warning("No messages returned from chat.db. Nothing to store.")

# -----------------------------------------------------------------------------
# Store messages
# -----------------------------------------------------------------------------
print(f"📦 Storing {len(messages)} messages to {CRM_DB_PATH}...")
# Database connection is already established by database manager

# Drop and recreate messages table if guid is not the primary key
cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='messages'")
table_exists = cur.fetchone()

if table_exists:
    cur.execute("PRAGMA table_info(messages)")
    columns_info = cur.fetchall()
    guid_is_primary = any(col[1] == "guid" and col[5] for col in columns_info)
    if not guid_is_primary:
        cur.execute("DROP TABLE IF EXISTS messages")

cur.execute(
    """
CREATE TABLE IF NOT EXISTS messages (
    guid TEXT PRIMARY KEY,
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
    is_last_message INTEGER DEFAULT 0,
    is_new INTEGER DEFAULT 0,
    source TEXT DEFAULT 'imessage'
)
"""
)

# --- Insert / Upsert messages ---
if messages:
    insert_fields = [
        "guid","rowid","body","phone_number","is_from_me","cache_roomname","group_chat_name",
        "timestamp","service","account","chat_id","attributedBody","subject","country","error",
        "date_read","date_delivered","is_sent","is_read","has_attachments","contact_id","message_type",
        "is_first_message","is_last_message","is_new","source"
    ]
    placeholders = ",".join(["?"] * len(insert_fields))
    set_clause = ",".join([f"{f}=excluded.{f}" for f in insert_fields if f != "guid"])
    upsert_sql = f"INSERT INTO messages ({','.join(insert_fields)}) VALUES ({placeholders}) ON CONFLICT(guid) DO UPDATE SET {set_clause}"
    try:
        payload = [tuple(m.get(k) for k in insert_fields) for m in messages]
        LOGGER.info("Upserting %s messages into SQLite…", len(payload))
        cur.executemany(upsert_sql, payload)
        conn.commit()
        LOGGER.info("Upsert committed successfully.")
    except Exception as e:
        LOGGER.error("Message upsert failed: %s", e, exc_info=True)
        conn.rollback()
else:
    LOGGER.info("Skip insert: no messages to write.")

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
        ("profile_photo", "BLOB"),
        ("first_message_date", "TEXT"),
        ("last_message_date", "TEXT"),
        ("total_messages", "INTEGER"),
        ("messages_sent", "INTEGER"),
        ("messages_received", "INTEGER"),
        ("is_primary_user", "INTEGER DEFAULT 0"),
        ("sent_last_message", "INTEGER"),
    ],
    "messages": [
        ("guid", "TEXT PRIMARY KEY"),
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
        ("is_last_message", "INTEGER DEFAULT 0"),
        ("is_new", "INTEGER DEFAULT 0"),
        ("source", "TEXT DEFAULT 'imessage'")
    ],

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