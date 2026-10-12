#!/usr/bin/env python3
"""
One-time script to clean up phone numbers and emails in the contacts table.

This script:
- Fixes concatenated phone numbers (e.g., +8017023408164+18017023408251 -> +18017023408251)
- Extracts emails from JSON format (e.g., {"email":"ryleewiddison@gmail.com"} -> ryleewiddison@gmail.com)
"""

import os
import json
import sqlite3
import re
from datetime import datetime
from typing import Optional, Tuple, List


def get_database_path() -> str:
    """Get database path from User_Settings.json using the same logic as database_utils.py"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    app_support_dir = os.path.expanduser("~/Library/Application Support/My_CRM")
    
    # Try Application Support first, then fall back to script directory
    pref_paths = [
        os.path.join(app_support_dir, "User_Settings.json"),
        os.path.join(script_dir, "User_Settings.json")
    ]
    
    for pref_path in pref_paths:
        if os.path.exists(pref_path):
            try:
                with open(pref_path, "r", encoding="utf-8") as f:
                    prefs = json.load(f)
                    db_path = os.path.expanduser(prefs["database"]["path"])
                    return os.path.abspath(db_path)
            except (json.JSONDecodeError, KeyError, FileNotFoundError) as e:
                print(f"⚠️ Failed to read settings from {pref_path}: {e}")
                continue
    
    # Fallback to default path in Application Support
    default_path = os.path.join(app_support_dir, "my_crm.db")
    print(f"⚠️ Using fallback database path: {default_path}")
    return default_path


def clean_phone_number(phone: Optional[str]) -> Tuple[Optional[str], bool]:
    """
    Clean concatenated phone numbers.
    Always prefers numbers starting with +1 (US format).
    
    Returns:
        Tuple of (cleaned_phone, was_changed)
    """
    if not phone:
        return phone, False
    
    # Check if phone contains multiple + signs (concatenated)
    plus_count = phone.count('+')
    if plus_count <= 1:
        return phone, False
    
    # Extract all phone numbers (split by + and reconstruct)
    # Pattern: find all sequences starting with + followed by digits
    phone_numbers = re.findall(r'\+[0-9]+', phone)
    
    if not phone_numbers:
        return phone, False
    
    # Always prefer numbers starting with +1 (US format)
    us_numbers = [p for p in phone_numbers if p.startswith('+1')]
    
    if us_numbers:
        # Take the first +1 number found
        cleaned = us_numbers[0]
        return cleaned, cleaned != phone
    
    # If no +1 number, keep original but log warning
    print(f"  ⚠️ Warning: No +1 number found in concatenated phone '{phone}', keeping original")
    return phone, False


def clean_email(email: Optional[str]) -> Tuple[Optional[str], bool]:
    """
    Extract email from JSON format.
    Handles format: {"email":"ryleewiddison@gmail.com"}
    
    Returns:
        Tuple of (cleaned_email, was_changed)
    """
    if not email:
        return email, False
    
    # Check if email is JSON format
    email = email.strip()
    if not email.startswith('{') or not email.endswith('}'):
        return email, False
    
    try:
        # Parse JSON
        email_data = json.loads(email)
        
        # Extract email value
        if isinstance(email_data, dict) and "email" in email_data:
            cleaned = email_data["email"]
            if isinstance(cleaned, str) and cleaned:
                return cleaned, True
        
        # If JSON is valid but doesn't have email key, return original
        print(f"  ⚠️ Warning: JSON email format missing 'email' key: {email}")
        return email, False
        
    except json.JSONDecodeError:
        # Not valid JSON, return original
        print(f"  ⚠️ Warning: Invalid JSON format for email: {email}")
        return email, False


def main():
    """Main cleanup function"""
    print("=" * 60)
    print("Contact Data Cleanup Script")
    print("=" * 60)
    print()
    
    # Get database path
    db_path = get_database_path()
    print(f"📁 Database path: {db_path}")
    
    if not os.path.exists(db_path):
        print(f"❌ Database file not found at: {db_path}")
        return 1
    
    # Connect to database
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        print("✅ Connected to database")
    except sqlite3.Error as e:
        print(f"❌ Failed to connect to database: {e}")
        return 1
    
    # Query all contacts
    try:
        cursor.execute("SELECT id, phone, email, name FROM contacts")
        contacts = cursor.fetchall()
        print(f"📊 Found {len(contacts)} contacts to process")
    except sqlite3.Error as e:
        print(f"❌ Failed to query contacts: {e}")
        conn.close()
        return 1
    
    # Process each contact
    phone_updates = []
    email_updates = []
    stats = {
        "total_contacts": len(contacts),
        "phone_cleaned": 0,
        "email_cleaned": 0,
        "no_changes": 0
    }
    
    print()
    print("Processing contacts...")
    print("-" * 60)
    
    for contact_id, phone, email, name in contacts:
        contact_name = name or f"ID {contact_id}"
        changes = []
        
        # Clean phone number
        cleaned_phone, phone_changed = clean_phone_number(phone)
        if phone_changed:
            phone_updates.append((cleaned_phone, contact_id))
            changes.append(f"phone: '{phone}' -> '{cleaned_phone}'")
            stats["phone_cleaned"] += 1
        
        # Clean email
        cleaned_email, email_changed = clean_email(email)
        if email_changed:
            email_updates.append((cleaned_email, contact_id))
            changes.append(f"email: '{email}' -> '{cleaned_email}'")
            stats["email_cleaned"] += 1
        
        # Log changes
        if changes:
            print(f"✅ {contact_name} (ID: {contact_id}):")
            for change in changes:
                print(f"   {change}")
        else:
            stats["no_changes"] += 1
    
    print("-" * 60)
    print()
    
    # Apply updates in transaction
    if phone_updates or email_updates:
        try:
            conn.execute("BEGIN TRANSACTION")
            
            # Update phone numbers
            if phone_updates:
                cursor.executemany(
                    "UPDATE contacts SET phone = ? WHERE id = ?",
                    phone_updates
                )
                print(f"✅ Updated {len(phone_updates)} phone numbers")
            
            # Update emails
            if email_updates:
                cursor.executemany(
                    "UPDATE contacts SET email = ? WHERE id = ?",
                    email_updates
                )
                print(f"✅ Updated {len(email_updates)} emails")
            
            # Commit transaction
            conn.commit()
            print("✅ All changes committed to database")
            
        except sqlite3.Error as e:
            conn.rollback()
            print(f"❌ Error updating database: {e}")
            print("❌ All changes rolled back")
            conn.close()
            return 1
    else:
        print("ℹ️ No changes needed")
    
    # Print summary
    print()
    print("=" * 60)
    print("Summary")
    print("=" * 60)
    print(f"Total contacts processed: {stats['total_contacts']}")
    print(f"Phone numbers cleaned: {stats['phone_cleaned']}")
    print(f"Emails cleaned: {stats['email_cleaned']}")
    print(f"Contacts with no changes: {stats['no_changes']}")
    print("=" * 60)
    
    # Close connection
    conn.close()
    print()
    print("✅ Cleanup complete!")
    
    return 0


if __name__ == "__main__":
    exit(main())


