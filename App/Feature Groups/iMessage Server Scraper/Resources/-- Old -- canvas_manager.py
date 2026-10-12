#!/usr/bin/env python3
"""
Canvas Manager Script

This script provides a command-line interface for managing canvases in the My CRM database.
It integrates with the database_utils module to perform CRUD operations on canvases.

Usage:
    python3 canvas_manager.py <command> [options]

Commands:
    create_canvas     - Create a new canvas
    get_canvas        - Retrieve a canvas by ID
    get_all_canvases  - List all canvases
    update_canvas     - Update an existing canvas
    delete_canvas     - Delete a canvas
    add_element       - Add an element to a canvas
    update_element    - Update an element in a canvas
    remove_element    - Remove an element from a canvas
    search_canvases   - Search canvases by name
"""

import sys
import json
import argparse
from typing import Dict, Any, Optional
from database_utils import DatabaseManager

def create_canvas(args: argparse.Namespace) -> bool:
    """Create a new canvas"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        elements = json.loads(args.elements) if args.elements else []
        state = json.loads(args.state) if args.state else {}
        
        success = db.create_canvas(
            canvas_id=args.canvas_id,
            canvas_name=args.canvas_name,
            canvas_type=args.canvas_type,
            initial_elements=elements,
            initial_state=state
        )
        
        db.disconnect()
        return success
    except Exception as e:
        print(f"Error creating canvas: {e}", file=sys.stderr)
        return False

def get_canvas(args: argparse.Namespace) -> bool:
    """Retrieve a canvas by ID"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        canvas = db.get_canvas(args.canvas_id)
        db.disconnect()
        
        if canvas:
            print(json.dumps(canvas, indent=2))
            return True
        else:
            print(f"Canvas not found: {args.canvas_id}", file=sys.stderr)
            return False
    except Exception as e:
        print(f"Error retrieving canvas: {e}", file=sys.stderr)
        return False

def get_all_canvases(args: argparse.Namespace) -> bool:
    """List all canvases"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        canvases = db.get_all_canvases(canvas_type=args.canvas_type)
        db.disconnect()
        
        print(json.dumps(canvases, indent=2))
        return True
    except Exception as e:
        print(f"Error retrieving canvases: {e}", file=sys.stderr)
        return False

def update_canvas(args: argparse.Namespace) -> bool:
    """Update an existing canvas"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        updates = {}
        if args.canvas_name:
            updates["canvas_name"] = args.canvas_name
        if args.elements:
            updates["canvas_elements"] = json.loads(args.elements)
        if args.state:
            updates["canvas_state"] = json.loads(args.state)
        if args.canvas_type:
            updates["canvas_type"] = args.canvas_type
        
        success = db.update_canvas(args.canvas_id, updates)
        db.disconnect()
        return success
    except Exception as e:
        print(f"Error updating canvas: {e}", file=sys.stderr)
        return False

def delete_canvas(args: argparse.Namespace) -> bool:
    """Delete a canvas"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        success = db.delete_canvas(args.canvas_id)
        db.disconnect()
        return success
    except Exception as e:
        print(f"Error deleting canvas: {e}", file=sys.stderr)
        return False

def add_element(args: argparse.Namespace) -> bool:
    """Add an element to a canvas"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        element = json.loads(args.element)
        success = db.add_canvas_element(args.canvas_id, element)
        db.disconnect()
        return success
    except Exception as e:
        print(f"Error adding element: {e}", file=sys.stderr)
        return False

def update_element(args: argparse.Namespace) -> bool:
    """Update an element in a canvas"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        element = json.loads(args.element)
        success = db.update_canvas_element(args.canvas_id, args.element_id, element)
        db.disconnect()
        return success
    except Exception as e:
        print(f"Error updating element: {e}", file=sys.stderr)
        return False

def remove_element(args: argparse.Namespace) -> bool:
    """Remove an element from a canvas"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        success = db.remove_canvas_element(args.canvas_id, args.element_id)
        db.disconnect()
        return success
    except Exception as e:
        print(f"Error removing element: {e}", file=sys.stderr)
        return False

def search_canvases(args: argparse.Namespace) -> bool:
    """Search canvases by name"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        canvases = db.search_canvases(args.query, canvas_type=args.canvas_type)
        db.disconnect()
        
        print(json.dumps(canvases, indent=2))
        return True
    except Exception as e:
        print(f"Error searching canvases: {e}", file=sys.stderr)
        return False

def create_group(args: argparse.Namespace) -> bool:
    """Create a new group"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        group_id = db.create_group(
            group_id=None,  # Auto-increment
            name=args.name,
            color=args.color,
            participants=json.loads(args.participants) if args.participants else [],
            canvases=json.loads(args.canvases) if args.canvases else []
        )
        
        db.disconnect()
        
        if group_id is not None:
            print(json.dumps({"id": group_id, "name": args.name}))
            return True
        else:
            return False
    except Exception as e:
        print(f"Error creating group: {e}", file=sys.stderr)
        return False

def get_group(args: argparse.Namespace) -> bool:
    """Retrieve a group by ID"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        group = db.get_group(args.group_id)
        db.disconnect()
        
        if group:
            print(json.dumps(group, indent=2))
            return True
        else:
            print(f"Group not found: {args.group_id}", file=sys.stderr)
            return False
    except Exception as e:
        print(f"Error retrieving group: {e}", file=sys.stderr)
        return False

def update_group(args: argparse.Namespace) -> bool:
    """Update an existing group"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        updates = {}
        if args.name:
            updates["name"] = args.name
        if args.color:
            updates["color"] = args.color
        if args.participants:
            updates["participants"] = json.loads(args.participants)
        if args.canvases:
            updates["canvases"] = json.loads(args.canvases)
        
        success = db.update_group(args.group_id, updates)
        db.disconnect()
        return success
    except Exception as e:
        print(f"Error updating group: {e}", file=sys.stderr)
        return False

def delete_group(args: argparse.Namespace) -> bool:
    """Delete a group"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        success = db.delete_group(args.group_id)
        db.disconnect()
        return success
    except Exception as e:
        print(f"Error deleting group: {e}", file=sys.stderr)
        return False

def get_all_groups(args: argparse.Namespace) -> bool:
    """List all groups"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        groups = db.get_all_groups()
        db.disconnect()
        
        print(json.dumps(groups, indent=2))
        return True
    except Exception as e:
        print(f"Error retrieving groups: {e}", file=sys.stderr)
        return False

def add_group_to_canvas(args: argparse.Namespace) -> bool:
    """Add a group to a canvas"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        success = db.add_group_to_canvas(args.group_id, args.canvas_id)
        db.disconnect()
        return success
    except Exception as e:
        print(f"Error adding group to canvas: {e}", file=sys.stderr)
        return False

def remove_group_from_canvas(args: argparse.Namespace) -> bool:
    """Remove a group from a canvas"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        success = db.remove_group_from_canvas(args.group_id, args.canvas_id)
        db.disconnect()
        return success
    except Exception as e:
        print(f"Error removing group from canvas: {e}", file=sys.stderr)
        return False

def get_next_group_name(args: argparse.Namespace) -> bool:
    """Get the next available group name (Group 1, Group 2, etc.)"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        next_name = db.get_next_group_name()
        db.disconnect()
        
        print(json.dumps({"next_name": next_name}, indent=2))
        return True
    except Exception as e:
        print(f"Error getting next group name: {e}", file=sys.stderr)
        return False

def update_group_membership(args: argparse.Namespace) -> bool:
    """Update group membership for a contact"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        success = db.update_group_membership(args.contact_id, args.group_id, args.operation)
        db.disconnect()
        return success
    except Exception as e:
        print(f"Error updating group membership: {e}", file=sys.stderr)
        return False

def update_group_participants(args: argparse.Namespace) -> bool:
    """Update group participants based on contacts found inside the circle"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        # Parse participants from JSON string containing element_id and contact_uuid
        participant_data = json.loads(args.participants) if args.participants else []
        
        # Convert to the format expected by the database
        participants_data = []
        for participant in participant_data:
            if isinstance(participant, dict):
                # New format: {"id": "phone", "name": "name", "UUID": "uuid"}
                contact_id = participant.get("id")
                contact_name = participant.get("name")
                contact_uuid = participant.get("UUID")
                
                # Create participant object with id, name, and UUID
                participant_obj = {
                    "id": contact_id,
                    "name": contact_name,
                    "UUID": contact_uuid
                }
                participants_data.append(participant_obj)
                print(f"Added participant: id={contact_id}, name={contact_name}, UUID={contact_uuid}")
            else:
                # Legacy format: just phone number
                print(f"Legacy format participant: {participant}")
        
        # Update group participants in database
        success = db.update_group_participants(args.group_id, participants_data)
        db.disconnect()
        return success
    except Exception as e:
        print(f"Error updating group participants: {e}", file=sys.stderr)
        return False

def get_contact_by_uid(args: argparse.Namespace) -> bool:
    """Get a contact by UID"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        contact = db.get_contact_by_uid(args.uid)
        db.disconnect()
        
        if contact:
            print(json.dumps(contact, indent=2))
            return True
        else:
            print(f"Contact not found with UID: {args.uid}", file=sys.stderr)
            return False
    except Exception as e:
        print(f"Error retrieving contact: {e}", file=sys.stderr)
        return False

def get_group_by_name(args: argparse.Namespace) -> bool:
    """Get a group by name"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        group = db.get_group_by_name(args.name)
        db.disconnect()
        
        if group:
            print(json.dumps(group, indent=2))
            return True
        else:
            print(f"Group not found with name: {args.name}", file=sys.stderr)
            return False
    except Exception as e:
        print(f"Error retrieving group: {e}", file=sys.stderr)
        return False



def add_contact_to_canvas(args: argparse.Namespace) -> bool:
    """Add a contact to a canvas"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        success = db.add_contact_to_canvas(
            contact_id=args.contact_id,
            canvas_id=args.canvas_id
        )
        db.disconnect()
        
        return success
    except Exception as e:
        print(f"Error adding contact to canvas: {e}", file=sys.stderr)
        return False

def remove_group_participant_source(args: argparse.Namespace) -> bool:
    """Remove specific sources from group participants"""
    try:
        db = DatabaseManager()
        if not db.connect():
            return False
        
        # Parse participants from JSON string
        participant_data = json.loads(args.participants) if args.participants else []
        
        # Convert to the format expected by the database
        participants_data = []
        for participant in participant_data:
            if isinstance(participant, dict):
                contact_id = participant.get("id")
                contact_name = participant.get("name")
                contact_uuid = participant.get("UUID")
                sources = participant.get("Source", [])
                
                # Create participant object with id, name, UUID, and Sources
                participant_obj = {
                    "id": contact_id,
                    "name": contact_name,
                    "UUID": contact_uuid,
                    "Source": sources
                }
                participants_data.append(participant_obj)
                print(f"Removing sources from participant: id={contact_id}, name={contact_name}")
        
        # Remove sources from group participants in database
        success = db.remove_group_participant_source(args.group_id, participants_data)
        db.disconnect()
        return success
    except Exception as e:
        print(f"Error removing participant sources: {e}", file=sys.stderr)
        return False

def main():
    parser = argparse.ArgumentParser(description="Canvas Manager for My CRM")
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # Create canvas command
    create_parser = subparsers.add_parser("create_canvas", help="Create a new canvas")
    create_parser.add_argument("--canvas-id", required=True, help="Canvas ID")
    create_parser.add_argument("--canvas-name", required=True, help="Canvas name")
    create_parser.add_argument("--canvas-type", default="group_map", help="Canvas type")
    create_parser.add_argument("--elements", help="Initial elements as JSON")
    create_parser.add_argument("--state", help="Initial canvas state as JSON")
    
    # Get canvas command
    get_parser = subparsers.add_parser("get_canvas", help="Get a canvas by ID")
    get_parser.add_argument("--canvas-id", required=True, help="Canvas ID")
    
    # Get all canvases command
    get_all_parser = subparsers.add_parser("get_all_canvases", help="Get all canvases")
    get_all_parser.add_argument("--canvas-type", help="Filter by canvas type")
    
    # Update canvas command
    update_parser = subparsers.add_parser("update_canvas", help="Update a canvas")
    update_parser.add_argument("--canvas-id", required=True, help="Canvas ID")
    update_parser.add_argument("--canvas-name", help="New canvas name")
    update_parser.add_argument("--elements", help="Canvas elements as JSON")
    update_parser.add_argument("--state", help="Canvas state as JSON")
    update_parser.add_argument("--canvas-type", help="Canvas type")
    
    # Delete canvas command
    delete_parser = subparsers.add_parser("delete_canvas", help="Delete a canvas")
    delete_parser.add_argument("--canvas-id", required=True, help="Canvas ID")
    
    # Add element command
    add_element_parser = subparsers.add_parser("add_element", help="Add element to canvas")
    add_element_parser.add_argument("--canvas-id", required=True, help="Canvas ID")
    add_element_parser.add_argument("--element", required=True, help="Element as JSON")
    
    # Update element command
    update_element_parser = subparsers.add_parser("update_element", help="Update element in canvas")
    update_element_parser.add_argument("--canvas-id", required=True, help="Canvas ID")
    update_element_parser.add_argument("--element-id", required=True, help="Element ID")
    update_element_parser.add_argument("--element", required=True, help="Updated element as JSON")
    
    # Remove element command
    remove_element_parser = subparsers.add_parser("remove_element", help="Remove element from canvas")
    remove_element_parser.add_argument("--canvas-id", required=True, help="Canvas ID")
    remove_element_parser.add_argument("--element-id", required=True, help="Element ID")
    
    # Search canvases command
    search_parser = subparsers.add_parser("search_canvases", help="Search canvases")
    search_parser.add_argument("--query", required=True, help="Search query")
    search_parser.add_argument("--canvas-type", help="Filter by canvas type")
    
    # Create group command
    create_group_parser = subparsers.add_parser("create_group", help="Create a new group")
    create_group_parser.add_argument("--name", required=True, help="Group name")
    create_group_parser.add_argument("--color", required=True, help="Group color (hex)")
    create_group_parser.add_argument("--participants", help="Participants as JSON array")
    create_group_parser.add_argument("--canvases", help="Canvases as JSON array")
    
    # Get group command
    get_group_parser = subparsers.add_parser("get_group", help="Get a group by ID")
    get_group_parser.add_argument("--group-id", required=True, help="Group ID")
    
    # Get group by name command
    get_group_by_name_parser = subparsers.add_parser("get_group_by_name", help="Get a group by name")
    get_group_by_name_parser.add_argument("--name", required=True, help="Group name")
    
    # Update group command
    update_group_parser = subparsers.add_parser("update_group", help="Update a group")
    update_group_parser.add_argument("--group-id", required=True, help="Group ID")
    update_group_parser.add_argument("--name", help="New group name")
    update_group_parser.add_argument("--color", help="New group color")
    update_group_parser.add_argument("--participants", help="Participants as JSON array")
    update_group_parser.add_argument("--canvases", help="Canvases as JSON array")
    
    # Delete group command
    delete_group_parser = subparsers.add_parser("delete_group", help="Delete a group")
    delete_group_parser.add_argument("--group-id", required=True, help="Group ID")
    
    # Get all groups command
    get_all_groups_parser = subparsers.add_parser("get_all_groups", help="Get all groups")
    
    # Add group to canvas command
    add_group_to_canvas_parser = subparsers.add_parser("add_group_to_canvas", help="Add group to canvas")
    add_group_to_canvas_parser.add_argument("--group-id", required=True, help="Group ID")
    add_group_to_canvas_parser.add_argument("--canvas-id", required=True, help="Canvas ID")
    
    # Remove group from canvas command
    remove_group_from_canvas_parser = subparsers.add_parser("remove_group_from_canvas", help="Remove group from canvas")
    remove_group_from_canvas_parser.add_argument("--group-id", required=True, help="Group ID")
    remove_group_from_canvas_parser.add_argument("--canvas-id", required=True, help="Canvas ID")
    
    # Get next group name command
    get_next_group_name_parser = subparsers.add_parser("get_next_group_name", help="Get next available group name")
    
    # Update group membership command
    update_group_membership_parser = subparsers.add_parser("update_group_membership", help="Update group membership for a contact")
    update_group_membership_parser.add_argument("--contact-id", required=True, type=int, help="Contact ID")
    update_group_membership_parser.add_argument("--group-id", required=True, type=int, help="Group ID")
    update_group_membership_parser.add_argument("--operation", required=True, choices=["add", "remove"], help="Operation: add or remove")
    
    # Get contact by UID command
    get_contact_by_uid_parser = subparsers.add_parser("get_contact_by_uid", help="Get a contact by UID")
    get_contact_by_uid_parser.add_argument("--uid", required=True, help="Contact UID")
    

    
    # Add contact to canvas command
    add_contact_to_canvas_parser = subparsers.add_parser("add_contact_to_canvas", help="Add contact to canvas")
    add_contact_to_canvas_parser.add_argument("--contact-id", required=True, help="Contact ID")
    add_contact_to_canvas_parser.add_argument("--canvas-id", required=True, help="Canvas ID")
    
    # Update group participants command
    update_group_participants_parser = subparsers.add_parser("update_group_participants", help="Update group participants")
    update_group_participants_parser.add_argument("--group-id", required=True, help="Group ID")
    update_group_participants_parser.add_argument("--participants", required=True, help="JSON array of participant objects with contact_id and contact_uuid")
    
    # Remove group participant source command
    remove_group_participant_source_parser = subparsers.add_parser("remove_group_participant_source", help="Remove specific sources from group participants")
    remove_group_participant_source_parser.add_argument("--group-id", required=True, help="Group ID")
    remove_group_participant_source_parser.add_argument("--participants", required=True, help="JSON array of participant objects with sources to remove")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 1
    
    # Execute the appropriate command
    command_functions = {
        "create_canvas": create_canvas,
        "get_canvas": get_canvas,
        "get_all_canvases": get_all_canvases,
        "update_canvas": update_canvas,
        "delete_canvas": delete_canvas,
        "add_element": add_element,
        "update_element": update_element,
        "remove_element": remove_element,
        "search_canvases": search_canvases,
        "create_group": create_group,
        "get_group": get_group,
        "get_group_by_name": get_group_by_name,
        "update_group": update_group,
        "delete_group": delete_group,
        "get_all_groups": get_all_groups,
        "add_group_to_canvas": add_group_to_canvas,
        "remove_group_from_canvas": remove_group_from_canvas,
        "get_next_group_name": get_next_group_name,
        "update_group_membership": update_group_membership,
        "get_contact_by_uid": get_contact_by_uid,
        "add_contact_to_canvas": add_contact_to_canvas,
        "update_group_participants": update_group_participants,
        "remove_group_participant_source": remove_group_participant_source
    }
    
    if args.command in command_functions:
        success = command_functions[args.command](args)
        return 0 if success else 1
    else:
        print(f"Unknown command: {args.command}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
