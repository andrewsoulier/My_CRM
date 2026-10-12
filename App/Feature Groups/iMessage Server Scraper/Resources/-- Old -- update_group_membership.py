#!/usr/bin/env python3
"""
Group Membership Update Script

This script is called from the Swift application to update group memberships
in the database when contacts are added to or removed from groups.
"""

import argparse
import sys
import os
import logging
from database_utils import get_database_manager, ensure_database_connection

# Configure logging
logging.basicConfig(level=logging.INFO)
LOGGER = logging.getLogger(__name__)

def main():
    parser = argparse.ArgumentParser(description='Update group membership in database')
    parser.add_argument('--contact-id', required=True, type=int, help='Contact ID')
    parser.add_argument('--group-id', required=True, type=int, help='Group ID')
    parser.add_argument('--operation', required=True, choices=['add', 'remove'], help='Operation to perform')
    
    args = parser.parse_args()
    
    try:
        # Get database manager and ensure connection
        db_manager = get_database_manager()
        if not ensure_database_connection():
            LOGGER.error("Failed to connect to database")
            sys.exit(1)
        
        # Update group membership
        db_manager.update_group_membership(
            contact_id=args.contact_id,
            group_id=args.group_id,
            operation=args.operation
        )
        
        LOGGER.info(f"Successfully {args.operation}ed contact {args.contact_id} to/from group {args.group_id}")
        
    except Exception as e:
        LOGGER.error(f"Failed to update group membership: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
