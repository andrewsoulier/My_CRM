#!/usr/bin/env python3
"""
Import Stake Data from Numbers File to My CRM Database

This script imports contacts from a Numbers file or CSV export into the My CRM database
and adds them all to a "48th Ward" group.
"""

import os
import sys
import json
import csv
import re
import uuid
import sqlite3
import logging
import urllib.request
import urllib.error
import urllib.parse
import ssl
from datetime import datetime
from typing import List, Dict, Optional, Any
from pathlib import Path
from dotenv import load_dotenv
import requests
import urllib3

# Disable SSL warnings for requests library
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

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
        logging.FileHandler(os.path.join(script_dir, 'import_stake_data.log'))
    ]
)
logger = logging.getLogger(__name__)

# Load environment variables from .env file
# Look for .env in the stake-directory-exporter directory first, then current directory
env_paths = [
    "/Users/andrewsoulier/Downloads/stake-directory-exporter (from backup)/.env",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
]
for env_path in env_paths:
    if os.path.exists(env_path):
        load_dotenv(env_path)
        logger.info(f"Loaded environment variables from: {env_path}")
        break
else:
    logger.warning("No .env file found. Photo downloads will fail without authentication.")

# Database path
DB_PATH = "/Users/andrewsoulier/My_CRM Project/my_crm_bannanas.db"

# Numbers file path
NUMBERS_FILE = "/Users/andrewsoulier/Downloads/stake_data.numbers"

# Group name (set to None to skip group operations)
GROUP_NAME = None  # Set to None to skip group creation/assignment
GROUP_COLOR = "#007AFF"  # Default blue color

# Authentication settings
AUTH_BASE_URL = "https://www.holystats.com/api/v1"
PHOTO_BASE_URL = "https://directory.churchofjesuschrist.org/api/v4/photos"


def normalize_phone(phone: str) -> str:
    """
    Normalize phone number to format +###########
    Removes spaces, parentheses, dashes, and ensures it starts with +
    Based on ContactsImporter.swift logic
    """
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


def parse_name(full_name: str) -> tuple:
    """Parse full name into first and last name"""
    if not full_name:
        return None, None
    
    parts = full_name.strip().split(maxsplit=1)
    if len(parts) == 1:
        return parts[0], None
    elif len(parts) == 2:
        return parts[0], parts[1]
    return None, None


def authenticate_church_directory(username: Optional[str] = None, password: Optional[str] = None) -> Optional[str]:
    """
    Authenticate with Church Directory API and return cookie string
    Returns None on failure
    """
    # Use environment variables if not provided
    username = username or os.getenv('USERNAME')
    password = password or os.getenv('PASSWORD')
    
    if not username or not password:
        logger.warning("USERNAME and PASSWORD not found in environment variables")
        return None
    
    try:
        login_url = f"{AUTH_BASE_URL}/login"
        payload = {
            "username": username,
            "password": password
        }
        
        response = requests.post(
            login_url,
            json=payload,
            headers={"content-type": "application/json"},
            timeout=10
        )
        
        if response.status_code != 200:
            logger.error(f"Authentication failed with status {response.status_code}: {response.text}")
            return None
        
        data = response.json()
        if 'cookie' not in data:
            logger.error(f"Authentication response missing cookie: {data}")
            return None
        
        logger.info("Successfully authenticated with Church Directory API")
        return data['cookie']
        
    except Exception as e:
        logger.error(f"Error authenticating with Church Directory: {e}")
        return None


def download_profile_photo(uuid: str, cookie: Optional[str] = None, use_thumbnail: bool = False, timeout: int = 10, max_size: int = 10 * 1024 * 1024) -> Optional[bytes]:
    """
    Download profile photo using UUID and optional authentication cookie
    Returns None on failure
    
    Args:
        uuid: Member UUID from Numbers file
        cookie: Authentication cookie from authenticate_church_directory()
        use_thumbnail: If True, download thumbnail; if False, download full resolution
        timeout: Request timeout in seconds
        max_size: Maximum image size in bytes
    """
    if not uuid:
        return None
    
    try:
        # Construct photo URL in the format used by Church Directory API
        thumbnail_param = "true" if use_thumbnail else "false"
        photo_url = f"{PHOTO_BASE_URL}/members/{uuid}?thumbnail={thumbnail_param}"
        
        headers = {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
        }
        
        # Add authentication cookie if provided
        if cookie:
            headers['Cookie'] = cookie
        
        response = requests.get(
            photo_url,
            headers=headers,
            timeout=timeout,
            stream=True,
            verify=False  # Disable SSL verification for now
        )
        
        if response.status_code != 200:
            logger.debug(f"HTTP {response.status_code} downloading photo for UUID {uuid}")
            return None
        
        # Check content type
        content_type = response.headers.get('Content-Type', '').lower()
        if not any(ct in content_type for ct in ['image', 'jpeg', 'jpg', 'png', 'gif']):
            logger.debug(f"URL does not appear to be an image: {photo_url} (Content-Type: {content_type})")
            return None
        
        # Read with size limit
        data = b''
        for chunk in response.iter_content(chunk_size=8192):
            data += chunk
            if len(data) > max_size:
                logger.warning(f"Image too large ({len(data)} bytes), skipping: {uuid}")
                return None
        
        if not data:
            logger.debug(f"Empty response for photo UUID {uuid}")
            return None
        
        logger.debug(f"Successfully downloaded photo for UUID {uuid} ({len(data)} bytes)")
        return data
        
    except requests.exceptions.RequestException as e:
        logger.debug(f"Request error downloading photo for UUID {uuid}: {e}")
        return None
    except Exception as e:
        logger.warning(f"Error downloading photo for UUID {uuid}: {e}")
        return None


def import_from_csv(csv_path: str, db_manager: DatabaseManager) -> List[Dict[str, Any]]:
    """
    Import contacts from CSV file
    Expects CSV with columns: name, phone, email, address, etc.
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
                    # Use givenname and surname directly if available (they are correctly separated)
                    given_name = (row.get(fieldnames.get('givenname', '')) or "").strip()
                    surname = (row.get(fieldnames.get('surname', '')) or "").strip()
                    
                    # Use name field as full name, or construct from givenname + surname
                    name = row.get(fieldnames.get('name', '')) or row.get(fieldnames.get('full name', '')) or ""
                    if not name and (given_name or surname):
                        # Construct full name from givenname and surname
                        name = f"{given_name} {surname}".strip()
                    
                    phone = row.get(fieldnames.get('phone', '')) or row.get(fieldnames.get('phone number', '')) or ""
                    email = row.get(fieldnames.get('email', '')) or row.get(fieldnames.get('email address', '')) or ""
                    address = row.get(fieldnames.get('address', '')) or ""
                    notes = row.get(fieldnames.get('notes', '')) or row.get(fieldnames.get('note', '')) or ""
                    business = row.get(fieldnames.get('business', '')) or row.get(fieldnames.get('company', '')) or ""
                    
                    # Extract UUID for photo downloads
                    member_uuid = row.get(fieldnames.get('uuid', '')) or ""
                    member_uuid = member_uuid.strip() if member_uuid else None
                    
                    # Extract photo URLs - check for various column name variations
                    photo_url = None
                    for photo_col in ['memberphotourl', 'memberphotothumbnailurl', 'photo_url', 'photourl', 'profile_photo_url']:
                        if fieldnames.get(photo_col):
                            url_val = row.get(fieldnames.get(photo_col)) or ""
                            if url_val and url_val.strip() and url_val.strip().startswith('http'):
                                photo_url = url_val.strip()
                                break
                    
                    # If UUID not in data but we have photo URL, try to extract UUID from URL
                    if not member_uuid and photo_url:
                        uuid_match = re.search(r'/members/([a-f0-9-]{36})', photo_url)
                        if uuid_match:
                            member_uuid = uuid_match.group(1)
                    
                    # Normalize phone
                    phone = normalize_phone(phone.strip()) if phone else ""
                    
                    # Skip if no name or phone/email
                    if not name and not phone and not email:
                        logger.warning(f"Row {row_num}: Skipping row with no name, phone, or email")
                        continue
                    
                    # Use email as identifier if no phone
                    identifier = phone if phone else email
                    if not identifier:
                        logger.warning(f"Row {row_num}: Skipping row with no phone or email identifier")
                        continue
                    
                    # Use givenname as first_name and surname as last_name (already correctly separated)
                    first_name = given_name if given_name else None
                    last_name = surname if surname else None
                    
                    # If we don't have separate first/last names, try to parse from name field
                    if not first_name and not last_name and name:
                        first_name, last_name = parse_name(name)
                    
                    contact = {
                        'phone': phone or identifier,  # Use email as phone if no phone
                        'name': name or identifier,
                        'first_name': first_name,
                        'last_name': last_name,
                        'email': email,
                        'address': address,
                        'notes': notes,
                        'business': business,
                        'uuid': member_uuid,  # UUID for authenticated photo downloads
                        'photo_url': photo_url
                    }
                    
                    contacts.append(contact)
                    logger.debug(f"Row {row_num}: Parsed contact: {contact['name']}")
                    
                except Exception as e:
                    logger.error(f"Row {row_num}: Error parsing row: {e}")
                    continue
            
            logger.info(f"Successfully parsed {len(contacts)} contacts from CSV")
            return contacts
            
    except Exception as e:
        logger.error(f"Error reading CSV file: {e}")
        raise


def try_parse_numbers_file(numbers_path: str) -> Optional[List[Dict[str, Any]]]:
    """
    Try to parse Numbers file directly
    Returns contacts if successful, None otherwise
    """
    # Try using numbers-parser library if available
    try:
        import numbers_parser
        logger.info("Attempting to parse Numbers file using numbers-parser library...")
        
        doc = numbers_parser.Document(numbers_path)
        sheets = doc.sheets
        
        if not sheets:
            logger.error("No sheets found in Numbers file")
            return None
        
        # Use first sheet
        sheet = sheets[0]
        tables = sheet.tables
        
        if not tables:
            logger.error("No tables found in Numbers sheet")
            return None
        
        # Use first table
        table = tables[0]
        
        # Get headers from first row
        headers = []
        if table.num_rows > 0:
            for col_idx in range(table.num_cols):
                cell = table.cell(0, col_idx)
                headers.append(str(cell.value).lower().strip() if cell.value else "")
        
        logger.info(f"Found columns: {headers}")
        
        # Parse rows
        contacts = []
        for row_idx in range(1, table.num_rows):
            try:
                row_data = {}
                for col_idx, header in enumerate(headers):
                    if col_idx < table.num_cols:
                        cell = table.cell(row_idx, col_idx)
                        row_data[header] = str(cell.value) if cell.value else ""
                
                # Map to contact structure
                # Use givenname and surname directly from Numbers file (they are correctly separated)
                given_name = row_data.get('givenname', '').strip() if row_data.get('givenname') else ''
                surname = row_data.get('surname', '').strip() if row_data.get('surname') else ''
                
                # Use name field as full name, or construct from givenname + surname
                full_name = row_data.get('name', '') or row_data.get('full name', '')
                if not full_name and (given_name or surname):
                    # Construct full name from givenname and surname
                    full_name = f"{given_name} {surname}".strip()
                elif not full_name:
                    # Fallback: use displayname if available
                    full_name = row_data.get('displayname', '') or row_data.get('officialname', '')
                
                phone = row_data.get('phone', '') or row_data.get('phone number', '')
                email = row_data.get('email', '') or row_data.get('email address', '')
                address = row_data.get('address', '')
                notes = row_data.get('notes', '') or row_data.get('note', '')
                business = row_data.get('business', '') or row_data.get('company', '')
                
                # Extract UUID for photo downloads
                member_uuid = row_data.get('uuid', '').strip() if row_data.get('uuid') else None
                
                # Extract photo URLs - prioritize full-size over thumbnail (for reference, but we'll use UUID)
                photo_url = None
                if row_data.get('memberphotourl'):
                    photo_url = str(row_data.get('memberphotourl')).strip()
                elif row_data.get('memberphotothumbnailurl'):
                    photo_url = str(row_data.get('memberphotothumbnailurl')).strip()
                elif row_data.get('photo_url'):
                    photo_url = str(row_data.get('photo_url')).strip()
                
                # If UUID not in data but we have photo URL, try to extract UUID from URL
                if not member_uuid and photo_url:
                    # Extract UUID from URL pattern: /api/v4/photos/members/{uuid}
                    uuid_match = re.search(r'/members/([a-f0-9-]{36})', photo_url)
                    if uuid_match:
                        member_uuid = uuid_match.group(1)
                
                phone = normalize_phone(phone.strip()) if phone else ""
                
                if not full_name and not phone and not email:
                    continue
                
                identifier = phone if phone else email
                if not identifier:
                    continue
                
                # Use givenname as first_name and surname as last_name (already correctly separated)
                first_name = given_name if given_name else None
                last_name = surname if surname else None
                
                contact = {
                    'phone': phone or identifier,
                    'name': full_name or identifier,
                    'first_name': first_name,
                    'last_name': last_name,
                    'email': email,
                    'address': address,
                    'notes': notes,
                    'business': business,
                    'uuid': member_uuid,  # UUID for authenticated photo downloads
                    'photo_url': photo_url if photo_url and photo_url.startswith('http') else None
                }
                
                contacts.append(contact)
                
            except Exception as e:
                logger.warning(f"Error parsing row {row_idx + 1}: {e}")
                continue
        
        logger.info(f"Successfully parsed {len(contacts)} contacts from Numbers file")
        return contacts
        
    except ImportError:
        logger.info("numbers-parser library not available, trying manual extraction...")
        return None
    except Exception as e:
        logger.error(f"Error parsing Numbers file: {e}")
        return None


def import_contacts(contacts: List[Dict[str, Any]], db_manager: DatabaseManager, auth_cookie: Optional[str] = None) -> Dict[str, int]:
    """
    Import contacts into database
    
    Duplicate Checking:
    - Uses phone number as primary key (phone column is UNIQUE NOT NULL in database)
    - If contact with same phone exists: UPDATE all fields including profile_photo
    - If contact does not exist: INSERT new contact
    
    Args:
        contacts: List of contact dictionaries
        db_manager: Database manager instance
        auth_cookie: Optional authentication cookie for downloading photos
    
    Returns dict with counts: {'inserted': X, 'updated': Y, 'skipped': Z, 'photos_downloaded': N, 'photos_failed': M}
    """
    stats = {'inserted': 0, 'updated': 0, 'skipped': 0, 'photos_downloaded': 0, 'photos_failed': 0}
    
    # Check if we should download high-res photos
    download_high_res = os.getenv('DOWNLOAD_HIGH_RES', 'FALSE').upper() == 'TRUE'
    use_thumbnail = not download_high_res
    
    db_manager.connect()
    
    try:
        total = len(contacts)
        for idx, contact in enumerate(contacts, 1):
            phone = contact.get('phone', '')
            name = contact.get('name', '')
            
            if not phone:
                logger.warning(f"Skipping contact '{name}' - no phone number")
                stats['skipped'] += 1
                continue
            
            # Download profile photo using UUID if available and authenticated
            photo_data = None
            member_uuid = contact.get('uuid')
            
            if member_uuid and auth_cookie:
                if idx % 10 == 0:  # Log progress every 10 contacts
                    logger.info(f"Processing contact {idx}/{total}: {name} ({phone})")
                logger.debug(f"Downloading photo for {name} using UUID: {member_uuid}")
                photo_data = download_profile_photo(
                    uuid=member_uuid,
                    cookie=auth_cookie,
                    use_thumbnail=use_thumbnail
                )
                if photo_data:
                    stats['photos_downloaded'] += 1
                else:
                    stats['photos_failed'] += 1
            elif member_uuid and not auth_cookie:
                logger.debug(f"Skipping photo download for {name} - no authentication cookie")
            elif not member_uuid:
                logger.debug(f"No UUID found for {name}, skipping photo download")
            
            try:
                # Check if contact exists - use phone as primary key (UNIQUE constraint)
                # Phone number is the unique identifier for contacts in the database
                db_manager.cursor.execute("SELECT id FROM contacts WHERE phone = ?", (phone,))
                existing = db_manager.cursor.fetchone()
                
                if existing:
                    # Update existing contact
                    contact_id = existing[0]
                    
                    # Build UPDATE query with optional photo
                    if photo_data:
                        db_manager.cursor.execute("""
                            UPDATE contacts SET
                                name = ?,
                                first_name = ?,
                                last_name = ?,
                                email = ?,
                                address = ?,
                                notes = ?,
                                business = ?,
                                profile_photo = ?
                            WHERE phone = ?
                        """, (
                            contact.get('name', ''),
                            contact.get('first_name'),
                            contact.get('last_name'),
                            contact.get('email'),
                            contact.get('address'),
                            contact.get('notes'),
                            contact.get('business'),
                            sqlite3.Binary(photo_data),
                            phone
                        ))
                    else:
                        db_manager.cursor.execute("""
                            UPDATE contacts SET
                                name = ?,
                                first_name = ?,
                                last_name = ?,
                                email = ?,
                                address = ?,
                                notes = ?,
                                business = ?
                            WHERE phone = ?
                        """, (
                            contact.get('name', ''),
                            contact.get('first_name'),
                            contact.get('last_name'),
                            contact.get('email'),
                            contact.get('address'),
                            contact.get('notes'),
                            contact.get('business'),
                            phone
                        ))
                    stats['updated'] += 1
                    logger.debug(f"Updated contact: {name} ({phone})" + (f" with photo" if photo_data else ""))
                else:
                    # Insert new contact
                    creation_date = datetime.now().isoformat()
                    
                    if photo_data:
                        db_manager.cursor.execute("""
                            INSERT INTO contacts (
                                phone, name, first_name, last_name, email, address,
                                notes, business, creation_date, groups, tag_ids, relationship_ids, profile_photo
                            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', '[]', '[]', ?)
                        """, (
                            phone,
                            contact.get('name', ''),
                            contact.get('first_name'),
                            contact.get('last_name'),
                            contact.get('email'),
                            contact.get('address'),
                            contact.get('notes'),
                            contact.get('business'),
                            creation_date,
                            sqlite3.Binary(photo_data)
                        ))
                    else:
                        db_manager.cursor.execute("""
                            INSERT INTO contacts (
                                phone, name, first_name, last_name, email, address,
                                notes, business, creation_date, groups, tag_ids, relationship_ids
                            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', '[]', '[]')
                        """, (
                            phone,
                            contact.get('name', ''),
                            contact.get('first_name'),
                            contact.get('last_name'),
                            contact.get('email'),
                            contact.get('address'),
                            contact.get('notes'),
                            contact.get('business'),
                            creation_date
                        ))
                    stats['inserted'] += 1
                    logger.debug(f"Inserted contact: {name} ({phone})" + (f" with photo" if photo_data else ""))
                
            except Exception as e:
                logger.error(f"Error importing contact '{name}': {e}")
                stats['skipped'] += 1
                continue
        
        db_manager.conn.commit()
        logger.info(f"Contact import complete: {stats['inserted']} inserted, {stats['updated']} updated, {stats['skipped']} skipped")
        logger.info(f"Photo download: {stats['photos_downloaded']} downloaded, {stats['photos_failed']} failed")
        return stats
        
    except Exception as e:
        db_manager.conn.rollback()
        logger.error(f"Error during contact import: {e}")
        raise


def create_group(db_manager: DatabaseManager, group_name: str, color: str) -> Optional[str]:
    """
    Create a new group in the database
    Returns group ID (as string) or None on failure
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
        # Note: The actual database uses INTEGER id, but we'll let it auto-increment
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
    Add all contacts to the specified group
    Returns number of contacts successfully added
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
        
        # Create sets for easy lookup
        existing_phones = set(member_phones)
        existing_participant_phones = {p.get('id') or p.get('contact_id') for p in participants if isinstance(p, dict)}
        
        added_count = 0
        
        # Add each contact
        for contact in contacts:
            phone = contact.get('phone', '')
            if not phone:
                continue
            
            # Skip if already in group
            if phone in existing_phones:
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
    logger.info("Starting Stake Data Import")
    logger.info("=" * 60)
    
    # Initialize database manager
    db_manager = DatabaseManager(DB_PATH)
    
    if not db_manager.connect():
        logger.error(f"Failed to connect to database at {DB_PATH}")
        return 1
    
    logger.info(f"Connected to database: {DB_PATH}")
    
    # Authenticate with Church Directory API for photo downloads
    auth_cookie = None
    logger.info("Authenticating with Church Directory API...")
    auth_cookie = authenticate_church_directory()
    if auth_cookie:
        logger.info("Authentication successful - photo downloads will be attempted")
    else:
        logger.warning("Authentication failed - photos will not be downloaded. Check .env file for USERNAME and PASSWORD.")
    
    # Try to parse Numbers file or CSV
    contacts = None
    
    # First, try parsing Numbers file directly
    if os.path.exists(NUMBERS_FILE):
        logger.info(f"Attempting to parse Numbers file: {NUMBERS_FILE}")
        contacts = try_parse_numbers_file(NUMBERS_FILE)
    
    # If Numbers parsing failed, check for CSV export
    if not contacts:
        csv_path = NUMBERS_FILE.replace('.numbers', '.csv')
        if os.path.exists(csv_path):
            logger.info(f"Parsing CSV file: {csv_path}")
            contacts = import_from_csv(csv_path, db_manager)
        else:
            logger.error("""
Could not parse Numbers file directly. Please export the Numbers file to CSV format:
1. Open the Numbers file
2. Go to File > Export To > CSV
3. Save it as 'stake_data.csv' in the Downloads folder
4. Run this script again
            """)
            return 1
    
    if not contacts:
        logger.error("No contacts found to import")
        return 1
    
    logger.info(f"Found {len(contacts)} contacts to import")
    
    # Import contacts (with authentication cookie for photo downloads)
    logger.info("Importing contacts into database...")
    stats = import_contacts(contacts, db_manager, auth_cookie=auth_cookie)
    logger.info(f"Import stats: {stats}")
    
    # Create or get group (only if GROUP_NAME is specified)
    added_count = 0
    if GROUP_NAME:
        logger.info(f"Creating/getting group '{GROUP_NAME}'...")
        group_id = create_group(db_manager, GROUP_NAME, GROUP_COLOR)
        
        if not group_id:
            logger.error("Failed to create group")
            return 1
        
        # Add contacts to group
        logger.info(f"Adding {len(contacts)} contacts to group '{GROUP_NAME}'...")
        added_count = add_contacts_to_group(db_manager, group_id, contacts)
        logger.info(f"Successfully added {added_count} contacts to group")
    else:
        logger.info("Skipping group operations (GROUP_NAME not set)")
    
    logger.info("=" * 60)
    logger.info("Import Complete!")
    logger.info(f"  - Contacts imported: {stats['inserted'] + stats['updated']}")
    logger.info(f"    • New contacts: {stats['inserted']}")
    logger.info(f"    • Updated contacts: {stats['updated']}")
    logger.info(f"    • Skipped: {stats['skipped']}")
    logger.info(f"  - Profile photos: {stats['photos_downloaded']} downloaded, {stats['photos_failed']} failed")
    if GROUP_NAME:
        logger.info(f"  - Contacts added to group: {added_count}")
    logger.info("=" * 60)
    
    return 0


if __name__ == "__main__":
    sys.exit(main())

