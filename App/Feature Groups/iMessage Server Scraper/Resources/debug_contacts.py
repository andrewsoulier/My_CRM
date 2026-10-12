#!/usr/bin/env python3

import os
import sys
import json
import datetime
import objc
from Foundation import NSObject
from Contacts import CNContactStore, CNContactFetchRequest

def fetch_mac_contacts():
    """Fetch contacts from macOS Contacts app"""
    store = CNContactStore.alloc().init()
    
    # Create fetch request
    request = CNContactFetchRequest.alloc().initWithKeysToFetch_([
        "givenName", "familyName", "emailAddresses", "phoneNumbers", 
        "postalAddresses", "note", "birthday", "organizationName", 
        "identifier", "imageData", "thumbnailImageData"
    ])
    
    mac_contacts = []
    
    def handler(contact, stop):
        mac_contacts.append(contact)
    
    # Wrap ObjC-heavy enumeration in an autorelease pool
    with objc.autorelease_pool():
        try:
            ok = store.enumerateContactsWithFetchRequest_error_usingBlock_(request, None, handler)
            print(f"Successfully fetched {len(mac_contacts)} contacts")
        except Exception as e:
            print(f"Error fetching contacts: {e}")
            return []
    
    return mac_contacts

def get_contact_photo_data(contact):
    """Extract profile photo data from contact, preferring full image over thumbnail"""
    try:
        if contact.areKeysAvailable_(["imageData"]):
            image_data = contact.imageData()
            if image_data:
                print(f"Found full image data: {len(image_data)} bytes")
                return image_data
        elif contact.areKeysAvailable_(["thumbnailImageData"]):
            thumbnail_data = contact.thumbnailImageData()
            if thumbnail_data:
                print(f"Found thumbnail image data: {len(thumbnail_data)} bytes")
                return thumbnail_data
    except Exception as e:
        print(f"Error reading profile photo: {e}")
    
    return None

def main():
    print("🔍 Debugging contact import...")
    
    # Fetch contacts
    mac_contacts = fetch_mac_contacts()
    
    if not mac_contacts:
        print("❌ No contacts found")
        return
    
    # Check first few contacts for photos
    photos_found = 0
    for i, contact in enumerate(mac_contacts[:10]):
        print(f"\nContact {i+1}:")
        
        first_name = str(contact.givenName())
        last_name = str(contact.familyName())
        full_name = f"{first_name} {last_name}".strip()
        print(f"  Name: {full_name}")
        
        # Check for photo
        photo_data = get_contact_photo_data(contact)
        if photo_data:
            photos_found += 1
            print(f"  ✅ Has photo")
        else:
            print(f"  ❌ No photo")
    
    print(f"\n📊 Summary: {photos_found} out of {min(10, len(mac_contacts))} contacts have photos")

if __name__ == "__main__":
    main()
