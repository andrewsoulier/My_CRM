import logging
import os

# Configure logging
log_dir = os.path.join(os.path.dirname(__file__), "Logs")
os.makedirs(log_dir, exist_ok=True)
log_file_path = os.path.join(log_dir, "imessage_tools_log.txt")
logging.basicConfig(
    filename=log_file_path,
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    filemode='w'  # This will reset the log file on each run
)
logging.info("Logging initialized.")
import sqlite3
import datetime
import subprocess

def get_chat_mapping(db_location):
    conn = sqlite3.connect(db_location)
    cursor = conn.cursor()

    cursor.execute("SELECT room_name, display_name FROM chat")
    result_set = cursor.fetchall()

    mapping = {room_name: display_name for room_name, display_name in result_set}

    conn.close()

    return mapping
def read_messages(db_location, n=10, self_number='Me', human_readable_date=True, min_timestamp=None):
    # Open Messages DB read-only and 'immutable' to avoid WAL/SHM writes.
    # NOTE: This does NOT bypass macOS TCC; Full Disk Access is still required.
    uri = f"file:{db_location}?mode=ro&immutable=1"
    conn = sqlite3.connect(uri, uri=True)
    cursor = conn.cursor()

    # Check available columns in the message table
    cursor.execute("PRAGMA table_info(message)")
    message_columns = [row[1] for row in cursor.fetchall()]

    base_columns = [
        "message.ROWID", "message.guid", "message.date", "message.text",
        "message.attributedBody", "handle.id", "message.is_from_me",
        "message.cache_roomnames", "message.service", "message.account",
        "chat.chat_identifier", "message.subject", "message.country",
        "message.error", "message.date_read", "message.date_delivered",
        "message.is_sent", "message.is_read"
    ]

    if "has_attachments" in message_columns:
        base_columns.append("message.has_attachments")
    else:
        base_columns.append("NULL AS has_attachments")

    if "associated_message_type" in message_columns:
        base_columns.append("message.associated_message_type")
    else:
        base_columns.append("NULL AS associated_message_type")

    query = f"""
    SELECT {', '.join(base_columns)}
    FROM message
    LEFT JOIN handle ON message.handle_id = handle.ROWID
    LEFT JOIN chat_message_join cmj ON message.ROWID = cmj.message_id
    LEFT JOIN chat ON chat.ROWID = cmj.chat_id
    """

    if min_timestamp is not None:
        query += """
        WHERE
            COALESCE(message.date, 0) > ?
            OR COALESCE(message.date_read, 0) > ?
            OR COALESCE(message.date_delivered, 0) > ?
        """
        query_params = (min_timestamp, min_timestamp, min_timestamp)
    else:
        query_params = ()

    if n is not None:
        query += f" ORDER BY message.date DESC LIMIT {n}"

    results = cursor.execute(query, query_params).fetchall()
    messages = []

    for result in results:
        rowid, guid, date, text, attributed_body, handle_id, is_from_me, cache_roomname, service, account, chat_id, subject, \
        country, error, date_read, date_delivered, is_sent, is_read, has_attachments, associated_message_type = result

        phone_number = self_number if handle_id is None else handle_id

        # Fallback body decoding logic
        if text is not None:
            body = text
        elif attributed_body:
            try:
                attributed_body = attributed_body.decode('utf-8', errors='replace')
                if "NSNumber" in attributed_body:
                    attributed_body = attributed_body.split("NSNumber")[0]
                if "NSString" in attributed_body:
                    attributed_body = attributed_body.split("NSString")[1]
                if "NSDictionary" in attributed_body:
                    attributed_body = attributed_body.split("NSDictionary")[0]
                attributed_body = attributed_body[6:-12]
                body = attributed_body
            except Exception as e:
                logging.warning("⚠️ Error decoding attributed_body: %s", str(e))
                body = None
        else:
            body = None

        if human_readable_date:
            date_string = '2001-01-01'
            mod_date = datetime.datetime.strptime(date_string, '%Y-%m-%d')
            unix_timestamp = int(mod_date.timestamp())*1000000000
            new_date = int((date+unix_timestamp)/1000000000)
            date = datetime.datetime.fromtimestamp(new_date).strftime("%Y-%m-%d %H:%M:%S")

        mapping = get_chat_mapping(db_location)
        mapped_name = mapping.get(cache_roomname, None)

        # Null-check and warning
        if any(v is None for v in (guid, service, chat_id, attributed_body, subject, country, error, date_read, date_delivered, is_sent, is_read, has_attachments, associated_message_type)):
            logging.warning("⚠️ Null fields detected in message rowid %s: %s", rowid, result)

        logging.info("Message record: %s", {
            'rowid': rowid,
            'guid': guid,
            'date': date,
            'body': body,
            'phone_number': phone_number,
            'is_from_me': is_from_me,
            'cache_roomname': cache_roomname,
            'group_chat_name': mapped_name,
            'service': service,
            'account': account,
            'chat_id': chat_id,
            'attributedBody': attributed_body,
            'subject': subject,
            'country': country,
            'error': error,
            'date_read': date_read,
            'date_delivered': date_delivered,
            'is_sent': is_sent,
            'is_read': is_read,
            'has_attachments': has_attachments,
            'associated_message_type': associated_message_type
        })

        messages.append(
            {
                "rowid": rowid,
                'guid': guid,
                "date": date,
                "body": body,
                "phone_number": phone_number,
                "is_from_me": is_from_me,
                "cache_roomname": cache_roomname,
                "group_chat_name": mapped_name,
                "service": service,
                "account": account,
                "chat_id": chat_id,
                "attributedBody": attributed_body,
                "subject": subject,
                "country": country,
                "error": error,
                "date_read": date_read,
                "date_delivered": date_delivered,
                "is_sent": is_sent,
                "is_read": is_read,
                "has_attachments": has_attachments,
                "associated_message_type": associated_message_type
            }
        )

    conn.close()
    return messages


def print_messages(messages):
    for message in messages:
        print(f"RowID: {message['rowid']}")
        print(f"GUID: {message['guid']}")
        print(f"Body: {message['body']}")
        print(f"Phone Number: {message['phone_number']}")
        print(f"Is From Me: {message['is_from_me']}")
        print(f"Cache Roomname: {message['cache_roomname']}")
        print(f"Group Chat Name: {message['group_chat_name']}")
        print(f"Date: {message['date']}")
        print(f"Service: {message['service']}")
        print(f"Account: {message['account']}")
        print(f"Chat ID: {message['chat_id']}")
        print(f"Attributed Body: {message['attributedBody']}")
        print(f"Subject: {message['subject']}")
        print(f"Country: {message['country']}")
        print(f"Error: {message['error']}")
        print(f"Date Read: {message['date_read']}")
        print(f"Date Delivered: {message['date_delivered']}")
        print(f"Is Sent: {message['is_sent']}")
        print(f"Is Read: {message['is_read']}")
        print(f"Has Attachments: {message['has_attachments']}")
        print(f"Associated Message Type: {message['associated_message_type']}")
        print("\n")


def send_message(message, phone_number, group_chat = False):
    # creating a file - note: text files end up being sent as normal text messages, so this is handy for
    # sending messages that osascript doesn't like due to strange formatting or characters
    file_path = os.path.abspath('imessage_tmp.txt')

    with open(file_path, 'w') as f:
        f.write(message)

    if not group_chat:
        command = f'tell application "Messages" to send (read (POSIX file "{file_path}") as «class utf8») to buddy "{phone_number}"'
    else:
        command = f'tell application "Messages" to send (read (POSIX file "{file_path}") as «class utf8») to chat "{phone_number}"'

    subprocess.run(['osascript', '-e', command])

    print(f"Sent message to {phone_number}: {message}")