#!/usr/bin/env python3
"""
Import Stake Data CSV and Assign to Gender-Based Groups

This script processes a CSV file containing stake member data, matches contacts
to existing database records by phone number, and assigns them to groups based on gender:
- Males (Gender = "M") → "48th Ward Elders Quorum"
- Females (Gender = "F") → "48th Ward Relief Society"
"""

import os
import sys
import csv
import re
import json
import logging
from datetime import datetime
from typing import List, Dict, Optional, Any

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
        logging.FileHandler(os.path.join(script_dir, 'import_stake_csv_to_groups.log'))
    ]
)
logger = logging.getLogger(__name__)

# Database path
DB_PATH = "/Users/andrewsoulier/My_CRM Project/my_crm_bannanas.db"

# CSV file path
CSV_FILE = "/Users/andrewsoulier/Downloads/Stake Data.csv"

# Group names and color
ELDERS_QUORUM_GROUP = "48th Ward Elders Quorum"
RELIEF_SOCIETY_GROUP = "48th Ward Relief Society"
GROUP_COLOR = "#007AFF"  # Default blue color


def normalize_phone(phone: str) -> str:
    """Normalize phone number to standard format (+###########)"""
    if not phone:
        return ""
    
    # Remove all non-digit characters except +
    digits_only = re.sub(r'[^\d+]', '', phone)
    
    # If it already starts with +, return as is
    if digits_only.startswith("+"):
        return digits_only
    
    # If it's 10 digits, assume US number and prepend +1
    if len(digits_only) == 10:
        return "+1" + digits_only
    
    # If it's 11 digits starting with 1, prepend +
    if len(digits_only) == 11 and digits_only.startswith("1"):
        return "+" + digits_only
    
    # Otherwise, just prepend + to whatever we have
    return "+" + digits_only if digits_only else ""


def get_phone_variants(phone_str: str) -> List[str]:
    """
    Generate multiple normalized variants of a phone number for matching.
    This helps match phone numbers in various formats.
    """
    variants = []
    if not phone_str:
        return variants
    
    # Remove all non-digit characters except +
    digits_only = re.sub(r'[^\d]', '', phone_str.replace('+', ''))
    
    if not digits_only:
        return variants
    
    # Extract last 10 digits (US phone number)
    if len(digits_only) >= 10:
        last_10 = digits_only[-10:]
        # Try +1XXXXXXXXXX format
        variant1 = '+1' + last_10
        variants.append(variant1)
        # Try just the 10 digits
        variants.append(last_10)
        # Try with leading 1
        if not last_10.startswith('1'):
            variant2 = '1' + last_10
            variants.append(variant2)
            variants.append('+' + variant2)
    
    # Also try with original normalization
    normalized = normalize_phone(phone_str)
    if normalized and normalized not in variants:
        variants.append(normalized)
    
    return variants


def parse_csv_contacts(csv_path: str) -> List[Dict[str, Any]]:
    """
    Parse CSV file and extract contact information.
    
    Args:
        csv_path: Path to CSV file
    
    Returns:
        List of contact dictionaries with phone, name, gender
    """
    contacts = []
    
    try:
        with open(csv_path, 'r', encoding='utf-8') as f:
            # Try to detect delimiter
            sample = f.read(1024)
            f.seek(0)
            sniffer = csv.Sniffer()
            delimiter = sniffer.sniff(sample).delimiter
            
            reader = csv.DictReader(f, delimiter=delimiter)
            
            # Normalize column names (case-insensitive, strip whitespace)
            fieldnames = {col.lower().strip(): col for col in reader.fieldnames or []}
            
            logger.info(f"Found CSV columns: {list(fieldnames.keys())}")
            
            for row_num, row in enumerate(reader, start=2):  # Start at 2 (header is row 1)
                try:
                    # Extract fields with case-insensitive matching
                    name = (row.get(fieldnames.get('name', '')) or "").strip()
                    gender = (row.get(fieldnames.get('gender', '')) or "").strip().upper()
                    phone = (row.get(fieldnames.get('phone number', '')) or 
                            row.get(fieldnames.get('phone', '')) or "").strip()
                    email = (row.get(fieldnames.get('email', '')) or "").strip()
                    
                    # Normalize phone number
                    phone = normalize_phone(phone)
                    
                    # Skip if no phone number (required for matching)
                    if not phone:
                        logger.warning(f"Row {row_num}: Skipping contact '{name}' - no phone number")
                        continue
                    
                    # Skip if no gender or invalid gender
                    if gender not in ['M', 'F']:
                        logger.warning(f"Row {row_num}: Skipping contact '{name}' - invalid gender: '{gender}'")
                        continue
                    
                    # Convert "Last, First" name format to "First Last" if needed
                    if ',' in name:
                        name_parts = name.split(',', 1)
                        if len(name_parts) == 2:
                            last_part = name_parts[0].strip()
                            first_part = name_parts[1].strip()
                            if first_part and last_part:
                                name = f"{first_part} {last_part}"
                    
                    contact = {
                        'phone': phone,
                        'name': name,
                        'gender': gender,
                        'email': email
                    }
                    
                    contacts.append(contact)
                    logger.debug(f"Row {row_num}: Parsed contact: {name} ({gender}) - {phone}")
                    
                except Exception as e:
                    logger.error(f"Row {row_num}: Error parsing row: {e}")
                    continue
        
        logger.info(f"Successfully parsed {len(contacts)} contacts from CSV")
        return contacts
        
    except Exception as e:
        logger.error(f"Error reading CSV file: {e}")
        raise


def match_contacts_in_database(db_manager: DatabaseManager, csv_contacts: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
    """
    Match CSV contacts to existing database contacts by phone number.
    Uses normalized phone numbers for matching to handle format differences.
    
    Args:
        db_manager: Database manager instance
        csv_contacts: List of contacts from CSV
    
    Returns:
        Dictionary with 'matched' and 'unmatched' lists
    """
    matched = []
    unmatched = []
    
    db_manager.connect()
    
    try:
        # Fetch all contacts from database and normalize their phone numbers
        # This allows us to match against various phone number formats
        logger.info("Loading all contacts from database for matching...")
        db_manager.cursor.execute("""
            SELECT id, name, first_name, last_name, email, phone 
            FROM contacts
        """)
        
        all_db_contacts = db_manager.cursor.fetchall()
        
        # Create a mapping of normalized phone -> database contact
        # Handle multiple formats by trying different normalizations
        db_phone_map = {}
        
        def get_phone_variants(phone_str):
            """Generate multiple normalized variants of a phone number for matching"""
            variants = []
            if not phone_str:
                return variants
            
            # Remove all non-digit characters except +
            digits_only = re.sub(r'[^\d]', '', phone_str.replace('+', ''))
            
            if not digits_only:
                return variants
            
            # Extract last 10 digits (US phone number)
            if len(digits_only) >= 10:
                last_10 = digits_only[-10:]
                # Try +1XXXXXXXXXX format
                variant1 = '+1' + last_10
                variants.append(variant1)
                # Try just the 10 digits
                variants.append(last_10)
                # Try with leading 1
                if not last_10.startswith('1'):
                    variant2 = '1' + last_10
                    variants.append(variant2)
                    variants.append('+' + variant2)
            
            # Also try with original normalization
            normalized = normalize_phone(phone_str)
            if normalized and normalized not in variants:
                variants.append(normalized)
            
            return variants
        
        for db_id, db_name, db_first_name, db_last_name, db_email, db_phone in all_db_contacts:
            if not db_phone:
                continue
            
            # Generate all possible phone number variants for this contact
            variants = get_phone_variants(db_phone)
            contact_data = (db_id, db_name, db_first_name, db_last_name, db_email, db_phone)
            
            # Store all variants pointing to the same contact
            for variant in variants:
                if variant and variant not in db_phone_map:
                    db_phone_map[variant] = contact_data
        
        logger.info(f"Loaded {len(db_phone_map)} normalized phone numbers from database")
        
        # Now match CSV contacts
        for csv_contact in csv_contacts:
            phone = csv_contact.get('phone', '')
            if not phone:
                continue
            
            # Generate variants of the CSV phone number
            csv_variants = get_phone_variants(phone)
            
            # Extract digits from CSV phone for substring matching
            csv_digits = re.sub(r'[^\d]', '', phone.replace('+', ''))
            csv_last_10 = csv_digits[-10:] if len(csv_digits) >= 10 else csv_digits
            
            # Try to find a match with any variant
            db_contact = None
            for variant in csv_variants:
                if variant in db_phone_map:
                    db_contact = db_phone_map[variant]
                    break
            
            # If no exact match, try substring matching (database might have extra digits)
            if not db_contact:
                # Look for database phones that contain our phone number or vice versa
                for db_variant, contact_data in db_phone_map.items():
                    db_digits = re.sub(r'[^\d]', '', db_variant.replace('+', ''))
                    db_last_10 = db_digits[-10:] if len(db_digits) >= 10 else db_digits
                    
                    # Check if last 10 digits match
                    if csv_last_10 and db_last_10 and csv_last_10 == db_last_10:
                        db_contact = contact_data
                        break
                    # Check if one contains the other (for cases like +15038577051 vs +15038577051251)
                    elif csv_last_10 and db_last_10:
                        if csv_last_10 in db_last_10 or db_last_10 in csv_last_10:
                            db_contact = contact_data
                            break
            
            if db_contact:
                # Contact found - use database name if available, otherwise use CSV name
                db_id, db_name, db_first_name, db_last_name, db_email, db_original_phone = db_contact
                contact_name = db_name or csv_contact.get('name', '')
                
                # If database contact has email as phone, use CSV phone number instead
                # (we need valid phone numbers for group membership)
                use_phone = db_original_phone
                if db_original_phone and ('@' in db_original_phone or not re.search(r'\d', db_original_phone)):
                    # Database has email/identifier, use CSV phone number
                    use_phone = phone
                    logger.debug(f"Contact {contact_name} has email as phone in DB ({db_original_phone}), using CSV phone: {phone}")
                
                matched_contact = {
                    'phone': use_phone,  # Use valid phone number (prefer database, fallback to CSV)
                    'name': contact_name,
                    'gender': csv_contact.get('gender'),
                    'email': csv_contact.get('email', '')
                }
                matched.append(matched_contact)
                logger.debug(f"Matched: {contact_name} ({use_phone})")
            else:
                # Contact not found in database
                unmatched.append(csv_contact)
                if len(unmatched) <= 10:  # Only log first 10 unmatched to avoid spam
                    logger.warning(f"No match found for: {csv_contact.get('name', 'Unknown')} ({phone})")
        
        if len(unmatched) > 10:
            logger.warning(f"... and {len(unmatched) - 10} more unmatched contacts")
        
        logger.info(f"Matched {len(matched)} contacts, {len(unmatched)} unmatched")
        return {'matched': matched, 'unmatched': unmatched}
        
    except Exception as e:
        logger.error(f"Error matching contacts: {e}")
        import traceback
        logger.error(traceback.format_exc())
        raise


def separate_by_gender(contacts: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
    """
    Separate contacts by gender.
    
    Args:
        contacts: List of contact dictionaries
    
    Returns:
        Dictionary with 'male' and 'female' lists
    """
    male_contacts = []
    female_contacts = []
    
    for contact in contacts:
        gender = contact.get('gender', '').upper()
        if gender == 'M':
            male_contacts.append(contact)
        elif gender == 'F':
            female_contacts.append(contact)
        else:
            logger.warning(f"Contact {contact.get('name', 'Unknown')} has invalid gender: {gender}")
    
    logger.info(f"Separated contacts: {len(male_contacts)} male, {len(female_contacts)} female")
    return {'male': male_contacts, 'female': female_contacts}


def create_group(db_manager: DatabaseManager, group_name: str, color: str) -> Optional[str]:
    """
    Create a new group in the database or get existing group ID.
    
    Args:
        db_manager: Database manager instance
        group_name: Name of the group
        color: Hex color code for the group
    
    Returns:
        Group ID as string, or None on failure
    """
    db_manager.connect()
    
    try:
        # Check if group already exists
        db_manager.cursor.execute("SELECT id FROM groups WHERE name = ?", (group_name,))
        existing = db_manager.cursor.fetchone()
        
        if existing:
            group_id = str(existing[0])
            logger.info(f"Group '{group_name}' already exists with ID: {group_id}")
            return group_id
        
        # Create new group
        created_at = datetime.now().isoformat()
        
        db_manager.cursor.execute("""
            INSERT INTO groups (name, color, created_at, participants, canvases, 
                              member_phones, size, is_deck, tags, child_group_ids, parent_group_ids)
            VALUES (?, ?, ?, '[]', '[]', '[]', 0, 0, '[]', '[]', '[]')
        """, (group_name, color, created_at))
        
        group_id = str(db_manager.cursor.lastrowid)
        db_manager.conn.commit()
        
        logger.info(f"Created group '{group_name}' with ID: {group_id}")
        return group_id
        
    except Exception as e:
        db_manager.conn.rollback()
        logger.error(f"Error creating group: {e}")
        return None


def add_contacts_to_group(db_manager: DatabaseManager, group_id: str, contacts: List[Dict[str, Any]]) -> int:
    """
    Add all contacts to the specified group.
    
    Args:
        db_manager: Database manager instance
        group_id: Group ID to add contacts to
        contacts: List of contact dictionaries
    
    Returns:
        Number of contacts successfully added
    """
    db_manager.connect()
    
    try:
        # Get current group data
        db_manager.cursor.execute("""
            SELECT participants, member_phones, size FROM groups WHERE id = ?
        """, (group_id,))
        
        result = db_manager.cursor.fetchone()
        if not result:
            logger.error(f"Group {group_id} not found")
            return 0
        
        participants_json = result[0] or '[]'
        member_phones_json = result[1] or '[]'
        current_size = result[2] or 0
        
        # Parse existing data
        try:
            participants = json.loads(participants_json) if participants_json else []
            member_phones = json.loads(member_phones_json) if member_phones_json else []
        except json.JSONDecodeError:
            participants = []
            member_phones = []
        
        # Ensure participants is a list
        if not isinstance(participants, list):
            participants = []
        
        # Ensure member_phones is a list
        if not isinstance(member_phones, list):
            member_phones = []
        
        # Create sets for easy lookup (normalized phone numbers)
        existing_phones = set(member_phones)
        
        # Also create a set of normalized variants for matching
        existing_phone_variants = set()
        for existing_phone in member_phones:
            existing_phone_variants.add(existing_phone)
            variants = get_phone_variants(existing_phone)
            existing_phone_variants.update(variants)
            # Also add last 10 digits for substring matching
            existing_digits = re.sub(r'[^\d]', '', existing_phone.replace('+', ''))
            if len(existing_digits) >= 10:
                existing_phone_variants.add(existing_digits[-10:])
        
        added_count = 0
        
        # Add each contact
        for contact in contacts:
            phone = contact.get('phone', '')
            if not phone:
                continue
            
            # Check if already in group (using exact match and last 10 digits)
            phone_digits = re.sub(r'[^\d]', '', phone.replace('+', ''))
            phone_last_10 = phone_digits[-10:] if len(phone_digits) >= 10 else phone_digits
            
            already_in_group = False
            # First check exact match
            if phone in existing_phones:
                already_in_group = True
            else:
                # Check last 10 digits match (handles format differences)
                if phone_last_10:
                    for existing_phone in existing_phones:
                        existing_digits = re.sub(r'[^\d]', '', existing_phone.replace('+', ''))
                        existing_last_10 = existing_digits[-10:] if len(existing_digits) >= 10 else existing_digits
                        if phone_last_10 == existing_last_10 and existing_last_10:  # Make sure we have valid 10 digits
                            already_in_group = True
                            break
            
            if already_in_group:
                logger.debug(f"Contact {contact.get('name', 'Unknown')} ({phone}) already in group")
                continue
            
            # Add to member_phones
            member_phones.append(phone)
            existing_phones.add(phone)
            
            # Add to participants with contact details
            participant = {
                'id': phone,
                'name': contact.get('name', ''),
                'UUID': ''  # Will be populated by other systems
            }
            participants.append(participant)
            added_count += 1
            
            # Update contact's groups field
            try:
                db_manager.cursor.execute("SELECT groups FROM contacts WHERE phone = ?", (phone,))
                contact_result = db_manager.cursor.fetchone()
                contact_groups = []
                
                if contact_result and contact_result[0]:
                    try:
                        contact_groups = json.loads(contact_result[0])
                        if not isinstance(contact_groups, list):
                            contact_groups = []
                    except json.JSONDecodeError:
                        contact_groups = []
                
                # Add group ID to contact's groups if not already there
                if group_id not in contact_groups:
                    contact_groups.append(group_id)
                
                db_manager.cursor.execute(
                    "UPDATE contacts SET groups = ? WHERE phone = ?",
                    (json.dumps(contact_groups), phone)
                )
            except Exception as e:
                logger.warning(f"Error updating contact groups for {phone}: {e}")
        
        # Update group with new participants and member phones
        new_size = len(member_phones)
        db_manager.cursor.execute("""
            UPDATE groups SET
                participants = ?,
                member_phones = ?,
                size = ?
            WHERE id = ?
        """, (
            json.dumps(participants),
            json.dumps(member_phones),
            new_size,
            group_id
        ))
        
        db_manager.conn.commit()
        logger.info(f"Added {added_count} contacts to group '{group_id}' (total: {new_size})")
        return added_count
        
    except Exception as e:
        db_manager.conn.rollback()
        logger.error(f"Error adding contacts to group: {e}")
        raise


def main():
    """Main import function"""
    logger.info("=" * 60)
    logger.info("Starting Stake Data CSV Import to Groups")
    logger.info("=" * 60)
    
    # Check if CSV file exists
    if not os.path.exists(CSV_FILE):
        logger.error(f"CSV file not found: {CSV_FILE}")
        return 1
    
    # Initialize database manager
    db_manager = DatabaseManager(DB_PATH)
    
    if not db_manager.connect():
        logger.error(f"Failed to connect to database at {DB_PATH}")
        return 1
    
    logger.info(f"Connected to database: {DB_PATH}")
    logger.info(f"Reading CSV file: {CSV_FILE}")
    
    try:
        # Parse CSV file
        csv_contacts = parse_csv_contacts(CSV_FILE)
        
        if not csv_contacts:
            logger.warning("No contacts found in CSV file")
            return 0
        
        logger.info(f"Found {len(csv_contacts)} contacts in CSV")
        
        # Match contacts to database
        logger.info("Matching contacts to database records...")
        matching_results = match_contacts_in_database(db_manager, csv_contacts)
        
        matched_contacts = matching_results['matched']
        unmatched_contacts = matching_results['unmatched']
        
        if not matched_contacts:
            logger.warning("No contacts matched in database. Exiting.")
            return 0
        
        logger.info(f"Successfully matched {len(matched_contacts)} contacts")
        
        if unmatched_contacts:
            logger.warning(f"{len(unmatched_contacts)} contacts could not be matched to database records")
        
        # Separate by gender
        logger.info("Separating contacts by gender...")
        gender_separation = separate_by_gender(matched_contacts)
        
        male_contacts = gender_separation['male']
        female_contacts = gender_separation['female']
        
        # Create or get groups
        logger.info(f"Creating/getting group: {ELDERS_QUORUM_GROUP}")
        elders_quorum_id = create_group(db_manager, ELDERS_QUORUM_GROUP, GROUP_COLOR)
        
        if not elders_quorum_id:
            logger.error(f"Failed to create/get group: {ELDERS_QUORUM_GROUP}")
            return 1
        
        logger.info(f"Creating/getting group: {RELIEF_SOCIETY_GROUP}")
        relief_society_id = create_group(db_manager, RELIEF_SOCIETY_GROUP, GROUP_COLOR)
        
        if not relief_society_id:
            logger.error(f"Failed to create/get group: {RELIEF_SOCIETY_GROUP}")
            return 1
        
        # Add contacts to groups
        elders_quorum_added = 0
        relief_society_added = 0
        
        if male_contacts:
            logger.info(f"Adding {len(male_contacts)} male contacts to {ELDERS_QUORUM_GROUP}...")
            elders_quorum_added = add_contacts_to_group(db_manager, elders_quorum_id, male_contacts)
        
        if female_contacts:
            logger.info(f"Adding {len(female_contacts)} female contacts to {RELIEF_SOCIETY_GROUP}...")
            relief_society_added = add_contacts_to_group(db_manager, relief_society_id, female_contacts)
        
        # Report results
        logger.info("=" * 60)
        logger.info("Import Complete!")
        logger.info("=" * 60)
        logger.info(f"  - Total contacts in CSV: {len(csv_contacts)}")
        logger.info(f"  - Contacts matched in database: {len(matched_contacts)}")
        logger.info(f"  - Contacts not matched: {len(unmatched_contacts)}")
        logger.info(f"  - Male contacts: {len(male_contacts)}")
        logger.info(f"  - Female contacts: {len(female_contacts)}")
        logger.info(f"  - Added to {ELDERS_QUORUM_GROUP}: {elders_quorum_added}")
        logger.info(f"  - Added to {RELIEF_SOCIETY_GROUP}: {relief_society_added}")
        logger.info("=" * 60)
        
        return 0
        
    except Exception as e:
        logger.error(f"Error during import: {e}")
        import traceback
        logger.error(traceback.format_exc())
        return 1
    
    finally:
        db_manager.disconnect()


if __name__ == "__main__":
    sys.exit(main())

