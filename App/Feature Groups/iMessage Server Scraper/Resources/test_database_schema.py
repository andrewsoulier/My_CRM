#!/usr/bin/env python3
"""
Database Schema Test Script

This script tests the database schema to ensure all tables and columns
are properly created and functional.
"""

import sys
import os
import json
from database_utils import DatabaseManager

def test_database_schema():
    """Test the database schema and basic operations"""
    print("Testing database schema...")
    
    # Initialize database manager
    db = DatabaseManager()
    
    if not db.connect():
        print("❌ Failed to connect to database")
        return False
    
    try:
        # Test contacts table
        print("  Testing contacts table...")
        db.cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='contacts'")
        if not db.cursor.fetchone():
            print("    ❌ Contacts table not found")
            return False
        print("    ✅ Contacts table exists")
        
        # Test groups table
        print("  Testing groups table...")
        db.cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='groups'")
        if not db.cursor.fetchone():
            print("    ❌ Groups table not found")
            return False
        print("    ✅ Groups table exists")
        
        # Test canvases table
        print("  Testing canvases table...")
        db.cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='canvases'")
        if not db.cursor.fetchone():
            print("    ❌ Canvases table not found")
            return False
        print("    ✅ Canvases table exists")
        
        # Test canvas table structure
        print("  Testing canvas table structure...")
        db.cursor.execute("PRAGMA table_info(canvases)")
        columns = {row[1] for row in db.cursor.fetchall()}
        required_columns = {
            "canvas_id", "canvas_name", "canvas_elements", "element_counts",
            "date_created", "date_updated", "canvas_type", "canvas_state", "metadata"
        }
        
        missing_columns = required_columns - columns
        if missing_columns:
            print(f"    ❌ Missing columns: {missing_columns}")
            return False
        print("    ✅ All required canvas columns exist")
        
        # Test canvas indexes
        print("  Testing canvas indexes...")
        db.cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='canvases'")
        indexes = {row[0] for row in db.cursor.fetchall()}
        required_indexes = {
            "idx_canvases_id", "idx_canvases_name", "idx_canvases_type",
            "idx_canvases_created", "idx_canvases_updated", "idx_canvases_type_updated"
        }
        
        missing_indexes = required_indexes - indexes
        if missing_indexes:
            print(f"    ❌ Missing indexes: {missing_indexes}")
            return False
        print("    ✅ All required canvas indexes exist")
        
        # Test canvas CRUD operations
        print("  Testing canvas CRUD operations...")
        
        # Create a test canvas
        test_canvas_id = "test-canvas-123"
        test_elements = [
            {
                "element_id": "element-1",
                "element_type": "contact",
                "location": {"x": 100, "y": 100},
                "scale": 1.0,
                "width": 60,
                "height": 80,
                "rotation": 0,
                "color": "#007AFF"
            }
        ]
        
        success = db.create_canvas(
            canvas_id=test_canvas_id,
            canvas_name="Test Canvas",
            canvas_type="group_map",
            initial_elements=test_elements
        )
        
        if not success:
            print("    ❌ Failed to create test canvas")
            return False
        print("    ✅ Test canvas created")
        
        # Retrieve the canvas
        canvas = db.get_canvas(test_canvas_id)
        if not canvas:
            print("    ❌ Failed to retrieve test canvas")
            return False
        print("    ✅ Test canvas retrieved")
        
        # Verify canvas data
        if canvas["canvas_name"] != "Test Canvas":
            print("    ❌ Canvas name mismatch")
            return False
        
        if len(canvas["canvas_elements"]) != 1:
            print("    ❌ Canvas elements count mismatch")
            return False
        
        # Update the canvas
        success = db.update_canvas(test_canvas_id, {"canvas_name": "Updated Test Canvas"})
        if not success:
            print("    ❌ Failed to update test canvas")
            return False
        print("    ✅ Test canvas updated")
        
        # Verify update
        updated_canvas = db.get_canvas(test_canvas_id)
        if updated_canvas["canvas_name"] != "Updated Test Canvas":
            print("    ❌ Canvas update not persisted")
            return False
        
        # Test element operations
        print("  Testing canvas element operations...")
        
        # Add element
        new_element = {
            "element_id": "element-2",
            "element_type": "group",
            "location": {"x": 200, "y": 200},
            "scale": 1.5,
            "width": 100,
            "height": 100,
            "rotation": 45,
            "color": "#FF3B30"
        }
        
        success = db.add_canvas_element(test_canvas_id, new_element)
        if not success:
            print("    ❌ Failed to add element")
            return False
        print("    ✅ Element added")
        
        # Update element
        success = db.update_canvas_element(test_canvas_id, "element-2", {"scale": 2.0})
        if not success:
            print("    ❌ Failed to update element")
            return False
        print("    ✅ Element updated")
        
        # Remove element
        success = db.remove_canvas_element(test_canvas_id, "element-2")
        if not success:
            print("    ❌ Failed to remove element")
            return False
        print("    ✅ Element removed")
        
        # Test search
        print("  Testing canvas search...")
        canvases = db.search_canvases("Test")
        if not canvases:
            print("    ❌ Canvas search failed")
            return False
        print("    ✅ Canvas search works")
        
        # Clean up
        success = db.delete_canvas(test_canvas_id)
        if not success:
            print("    ❌ Failed to delete test canvas")
            return False
        print("    ✅ Test canvas deleted")
        
        print("  ✅ All canvas CRUD operations passed")
        
        # Test basic data operations
        print("  Testing basic data operations...")
        
        # Test contact insertion
        db.cursor.execute("""
            INSERT OR REPLACE INTO contacts (phone, name, email, first_name, last_name, business)
            VALUES (?, ?, ?, ?, ?, ?)
        """, ("+1234567890", "Test Contact", "test@example.com", "Test", "Contact", "Test Company"))
        
        # Test contact retrieval
        db.cursor.execute("SELECT name FROM contacts WHERE phone = ?", ("+1234567890",))
        result = db.cursor.fetchone()
        if not result or result[0] != "Test Contact":
            print("    ❌ Contact operations failed")
            return False
        
        # Test group insertion
        db.cursor.execute("""
            INSERT OR REPLACE INTO groups (name, participants, size, favorite_status, priority, tags)
            VALUES (?, ?, ?, ?, ?, ?)
        """, ("Test Group", "[]", 0, 0, 0, "[]"))
        
        # Test group retrieval
        db.cursor.execute("SELECT name FROM groups WHERE name = ?", ("Test Group",))
        result = db.cursor.fetchone()
        if not result or result[0] != "Test Group":
            print("    ❌ Group operations failed")
            return False
        
        print("    ✅ Basic data operations passed")
        
        db.conn.commit()
        db.disconnect()
        
        return True
        
    except Exception as e:
        print(f"❌ Database schema test failed: {e}")
        db.disconnect()
        return False

def main():
    """Main function"""
    success = test_database_schema()
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
