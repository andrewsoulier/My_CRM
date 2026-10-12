import os
import json
import sqlite3
import datetime
import base64

import Contacts  # pyobjc-framework-Contacts
import objc      # for autorelease pool
from database_utils import get_database_manager, ensure_database_connection

print("Contacts file: " + Contacts.__file__)

def fetch_mac_contacts():
    store = Contacts.CNContactStore.alloc().init()
    keys_to_fetch = [
        Contacts.CNContactGivenNameKey,
        Contacts.CNContactFamilyNameKey,
        Contacts.CNContactEmailAddressesKey,
        Contacts.CNContactPhoneNumbersKey,
        Contacts.CNContactPostalAddressesKey,
        Contacts.CNContactNoteKey,
        Contacts.CNContactBirthdayKey,
        Contacts.CNContactOrganizationNameKey,
        Contacts.CNContactIdentifierKey,
        Contacts.CNContactImageDataKey,  # Add profile photo data
        Contacts.CNContactThumbnailImageDataKey,  # Add thumbnail data as fallback
    ]
    request = Contacts.CNContactFetchRequest.alloc().initWithKeysToFetch_(keys_to_fetch)

    mac_contacts = []

    def handler(contact, stop_ptr):
        mac_contacts.append(contact)

    # Wrap ObjC-heavy enumeration in an autorelease pool
    with objc.autorelease_pool():
        ok = store.enumerateContactsWithFetchRequest_error_usingBlock_(request, None, handler)
        # enumerate... returns None; if there were an ObjC exception it would raise in PyObjC

    return mac_contacts

def ensure_profile_photo_column(cursor, log):
    """Check if profile_photo column exists, add it if not"""
    cursor.execute("PRAGMA table_info(contacts)")
    existing_fields = [row[1] for row in cursor.fetchall()]
    
    if "profile_photo" not in existing_fields:
        cursor.execute("ALTER TABLE contacts ADD COLUMN profile_photo BLOB")
        log.write("Added missing field: profile_photo\n")
        return True
    return False

def get_contact_photo_data(contact, log):
    """Extract profile photo data from contact, preferring full image over thumbnail"""
    try:
        if contact.areKeysAvailable_(["imageData"]):
            image_data = contact.imageData()
            if image_data:
                return image_data
        elif contact.areKeysAvailable_(["thumbnailImageData"]):
            thumbnail_data = contact.thumbnailImageData()
            if thumbnail_data:
                log.write(f"\tUsing thumbnail image for contact\n")
                return thumbnail_data
    except Exception as e:
        log.write(f"\tError reading profile photo: {e}\n")
    
    return None

def update_crm_database(db_path, mac_contacts):
    # Use the database manager to ensure schema is up to date
    db_manager = get_database_manager()
    if not ensure_database_connection():
        print("Failed to connect to database. Check settings.")
        return
    
    conn = db_manager.conn
    cursor = db_manager.cursor
    log_dir = os.environ.get("MYCRM_LOG_DIR") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "Logs")
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, "contact_scan_log.txt")
    with open(log_file, "w", encoding="utf-8") as log:
        log.write(f"Contact Sync Log - {datetime.datetime.now()}\n\n")

        # Ensure all required fields exist
        required_fields = [
            "id", "phone", "name", "email", "first_name", "last_name", "address",
            "notes", "creation_date", "business", "contact_group", "birthday", "apple_contact_id", "profile_photo"
        ]
        cursor.execute("PRAGMA table_info(contacts)")
        existing_fields = [row[1] for row in cursor.fetchall()]
        for field in required_fields:
            if field not in existing_fields:
                cursor.execute(f"ALTER TABLE contacts ADD COLUMN {field} TEXT")
                log.write(f"Added missing field: {field}\n")

        # Schema is already ensured by database manager

        for contact in mac_contacts:
            with objc.autorelease_pool():
                try:
                    first_name = str(contact.givenName())
                    last_name = str(contact.familyName())
                    full_name = f"{first_name} {last_name}".strip()

                    email = None
                    try:
                        if contact.areKeysAvailable_(["emailAddresses"]):
                            email_addresses = contact.emailAddresses()
                            if email_addresses:
                                email = email_addresses[0].value()
                    except Exception as e:
                        log.write(f"\tError reading emailAddresses: {e}\n")

                    notes = str(contact.note()) if contact.areKeysAvailable_(["note"]) else None

                    birthday_str = None
                    try:
                        if contact.areKeysAvailable_(["birthday"]):
                            birthday = contact.birthday()
                            if birthday:
                                parts = [str(birthday.month()), str(birthday.day())]
                                if birthday.year() != 0:
                                    parts.insert(0, str(birthday.year()))
                                birthday_str = "-".join(parts)
                    except Exception as e:
                        log.write(f"\tError reading birthday: {e}\n")

                    business = str(contact.organizationName()) if contact.areKeysAvailable_(["organizationName"]) else None
                    apple_contact_id = str(contact.identifier()) if contact.identifier() else None

                    # Get profile photo data
                    profile_photo_data = get_contact_photo_data(contact, log)

                    address = None
                    try:
                        if contact.areKeysAvailable_(["postalAddresses"]):
                            addresses = contact.postalAddresses()
                            if addresses:
                                addr_val = addresses[0].value()
                                address = f"{addr_val.street()} {addr_val.city()} {addr_val.state()} {addr_val.postalCode()}".strip()
                    except Exception as e:
                        log.write(f"\tError reading postalAddresses: {e}\n")

                    phones = []
                    try:
                        if contact.areKeysAvailable_(["phoneNumbers"]):
                            for labeled_value in contact.phoneNumbers():
                                phone_value = labeled_value.value()
                                phone_string = phone_value.stringValue()
                                if phone_string:
                                    digits_only = ''.join(filter(str.isdigit, phone_string))
                                    if len(digits_only) >= 10:
                                        normalized = "+1" + digits_only[-10:]
                                        phones.append(normalized)
                    except Exception as e:
                        log.write(f"\tError reading phoneNumbers: {e}\n")

                    log.write(f"Processing: {full_name}, Phones: {phones}, Email: {email}, Address: {address}, Business: {business}\n")

                    # Current design assumes only one phone number per contact is stored.
                    # Future enhancement may involve a 'phones' table for normalization.
                    for phone in phones:
                        match = None
                        if apple_contact_id:
                            cursor.execute("SELECT * FROM contacts WHERE apple_contact_id = ?", (apple_contact_id,))
                            match = cursor.fetchone()
                        if not match:
                            cursor.execute("SELECT * FROM contacts WHERE phone = ?", (phone,))
                            match = cursor.fetchone()
                        
                        if match:
                            contact_id = match[0]
                            db_values = dict(zip([desc[0] for desc in cursor.description], match))

                            log.write(f"\tMatch found in DB: id={contact_id}, phone={db_values.get('phone')}\n")

                            # Sync logic: prefer macOS data, only add missing data, never delete
                            updates = {}
                            
                            # Always update with macOS data if it exists (prefer macOS as source of truth)
                            if full_name: updates["name"] = full_name
                            if first_name: updates["first_name"] = first_name
                            if last_name: updates["last_name"] = last_name
                            if email: updates["email"] = email
                            if address: updates["address"] = address
                            if notes: updates["notes"] = notes
                            if birthday_str: updates["birthday"] = birthday_str
                            if business: updates["business"] = business
                            if apple_contact_id: updates["apple_contact_id"] = apple_contact_id
                            if profile_photo_data: updates["profile_photo"] = profile_photo_data

                            # Only add missing data (don't overwrite existing data if macOS doesn't have it)
                            if not db_values.get("phone"): updates["phone"] = phone

                            if updates:
                                set_clause = ", ".join([f"{k} = ?" for k in updates])
                                values = list(updates.values()) + [contact_id]
                                cursor.execute(f"UPDATE contacts SET {set_clause} WHERE id = ?", values)
                                log.write(f"\tUpdated fields: {list(updates.keys())}\n")
                            else:
                                log.write("\tNo updates needed.\n")
                        else:
                            # Insert new contact
                            log.write(f"\tInserting new contact for phone {phone}\n")
                            cursor.execute("""
                                INSERT INTO contacts 
                                (phone, name, email, first_name, last_name, address, notes, 
                                 birthday, business, apple_contact_id, profile_photo, creation_date)
                                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """, (
                                phone, full_name, email, first_name, last_name, address, notes,
                                birthday_str, business, apple_contact_id, profile_photo_data,
                                datetime.datetime.now().isoformat()
                            ))

                except Exception as e:
                    log.write(f"❌ Error processing contact: {e}\n")

    conn.commit()
    conn.close()

if __name__ == "__main__":
    current_dir = os.path.dirname(os.path.abspath(__file__))

    # Prefer env-provided DB path (set by Start.py); fall back to User_Settings.json if present
    db_path = os.environ.get("MYCRM_DB")
    if not db_path:
        # Try Application Support first, then fall back to Resources directory
        APP_SUPPORT_DIR = os.path.expanduser("~/Library/Application Support/My_CRM")
        APP_SUPPORT_PREFS = os.path.join(APP_SUPPORT_DIR, "User_Settings.json")
        RESOURCES_PREFS = os.path.join(current_dir, "User_Settings.json")
        
        if os.path.exists(APP_SUPPORT_PREFS):
            pref_path = APP_SUPPORT_PREFS
        elif os.path.exists(RESOURCES_PREFS):
            pref_path = RESOURCES_PREFS
        else:
            default_state = os.path.expanduser("~/Library/Application Support/My_CRM")
            os.makedirs(default_state, exist_ok=True)
            db_path = os.path.join(default_state, "my_crm.db")
            mac_contacts = fetch_mac_contacts()
            update_crm_database(db_path, mac_contacts)
            exit(0)
        
        with open(pref_path, "r", encoding="utf-8") as f:
            prefs = json.load(f)
        db_path = os.path.abspath(os.path.expanduser(prefs["database"]["path"]))

    mac_contacts = fetch_mac_contacts()
    update_crm_database(db_path, mac_contacts)