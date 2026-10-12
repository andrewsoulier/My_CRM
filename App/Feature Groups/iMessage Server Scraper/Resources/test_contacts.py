#!/usr/bin/env python3
"""
Test script to list contacts in the database
"""

import sqlite3
import os

def main():
    # Get the database path using the same logic as database_utils.py
    script_dir = os.path.dirname(os.path.abspath(__file__))
    app_support_dir = os.path.expanduser("~/Library/Application Support/My_CRM")
    
    # Try Application Support first, then fall back to Resources
    pref_paths = [
        os.path.join(app_support_dir, "User_Settings.json"),
        os.path.join(script_dir, "User_Settings.json")
    ]
    
    db_path = None
    for pref_path in pref_paths:
        if os.path.exists(pref_path):
            try:
                import json
                with open(pref_path, "r", encoding="utf-8") as f:
                    prefs = json.load(f)
                    db_path = os.path.expanduser(prefs["database"]["path"])
                    db_path = os.path.abspath(db_path)
                    break
            except (json.JSONDecodeError, KeyError, FileNotFoundError) as e:
                print(f"Failed to read preferences from {pref_path}: {e}")
                continue
    
    # Fallback to default path
    if not db_path:
        db_path = os.path.join(script_dir, "my_crm.db")
        print(f"Using fallback database path: {db_path}")
    
    if not os.path.exists(db_path):
        print(f"Database not found at: {db_path}")
        return
    
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Get all contacts
        cursor.execute("SELECT id, name, phone, business, contact_group FROM contacts LIMIT 10")
        contacts = cursor.fetchall()
        
        print(f"Found {len(contacts)} contacts in database:")
        print("-" * 80)
        
        for contact in contacts:
            contact_id, name, phone, business, contact_group = contact
            print(f"ID: {contact_id}")
            print(f"Name: {name}")
            print(f"Phone: {phone}")
            print(f"Business: {business}")
            print(f"Group: {contact_group}")
            print("-" * 40)
        
        conn.close()
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
