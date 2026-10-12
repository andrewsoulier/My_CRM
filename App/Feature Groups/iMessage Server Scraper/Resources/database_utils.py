import os
import json
import sqlite3
import logging
from typing import Optional, Dict, List, Any
from datetime import datetime

# Configure logging
LOGGER = logging.getLogger(__name__)

class DatabaseManager:
    def __init__(self, db_path: Optional[str] = None):
        """Initialize database manager with optional custom path"""
        self.db_path = db_path or self._get_database_path()
        self.conn = None
        self.cursor = None
    
    def _get_database_path(self) -> str:
        """Get database path from User_Settings.json"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        app_support_dir = os.path.expanduser("~/Library/Application Support/My_CRM")
        
        # Try Application Support first, then fall back to Resources
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
                    LOGGER.warning(f"Failed to read settings from {pref_path}: {e}")
                    continue
        
        # Fallback to default path in Application Support
        default_path = os.path.join(app_support_dir, "my_crm.db")
        LOGGER.warning(f"Using fallback database path: {default_path}")
        return default_path
    
    def connect(self) -> bool:
        """Connect to the database and ensure schema is up to date"""
        try:
            self.conn = sqlite3.connect(self.db_path)
            self.cursor = self.conn.cursor()
            self._ensure_schema()
            return True
        except Exception as e:
            LOGGER.error(f"Failed to connect to database at {self.db_path}: {e}")
            self._show_database_error_dialog()
            return False
    
    def disconnect(self):
        """Close database connection"""
        if self.cursor:
            self.cursor.close()
        if self.conn:
            self.conn.close()
    
    def _ensure_schema(self):
        """Ensure all required tables and columns exist"""
        self._ensure_contacts_table()
        self._ensure_groups_table()
        self._ensure_canvases_table()
        self.conn.commit()
    
    def _ensure_contacts_table(self):
        """Ensure contacts table has all required columns"""
        # Create contacts table if it doesn't exist
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS contacts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                phone TEXT UNIQUE NOT NULL,
                name TEXT,
                email TEXT,
                first_name TEXT,
                last_name TEXT,
                address TEXT,
                notes TEXT,
                creation_date TEXT,
                business TEXT,
                contact_group TEXT,
                birthday TEXT,
                apple_contact_id TEXT,
                profile_photo BLOB,
                first_message_date TEXT,
                last_message_date TEXT,
                total_messages INTEGER DEFAULT 0,
                messages_sent INTEGER DEFAULT 0,
                messages_received INTEGER DEFAULT 0,
                is_primary_user INTEGER DEFAULT 0,
                sent_last_message INTEGER
            )
        """)
        

        

    
    def _ensure_groups_table(self):
        """Ensure groups table exists with all required columns"""
        # Create groups table if it doesn't exist
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS groups (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                color TEXT NOT NULL,
                created_at TEXT NOT NULL,
                parent_id TEXT,
                member_phones TEXT,
                linked_group_ids TEXT,
                metadata TEXT,
                is_deck INTEGER DEFAULT 0,
                participants TEXT DEFAULT '[]',
                canvases TEXT DEFAULT '[]'
            )
        """)
        
        # Check for missing columns and add them
        self.cursor.execute("PRAGMA table_info(groups)")
        existing_columns = {row[1] for row in self.cursor.fetchall()}
        
        required_columns = {
            "id": "TEXT PRIMARY KEY",
            "name": "TEXT NOT NULL",
            "color": "TEXT NOT NULL",
            "created_at": "TEXT NOT NULL",
            "parent_id": "TEXT",
            "member_phones": "TEXT",
            "linked_group_ids": "TEXT",
            "metadata": "TEXT",
            "is_deck": "INTEGER DEFAULT 0",
            "participants": "TEXT DEFAULT '[]'",
            "canvases": "TEXT DEFAULT '[]'"
        }
        
        for column_name, column_type in required_columns.items():
            if column_name not in existing_columns:
                try:
                    self.cursor.execute(f"ALTER TABLE groups ADD COLUMN {column_name} {column_type}")
                    LOGGER.info(f"Added missing '{column_name}' column to groups table")
                except sqlite3.OperationalError:
                    pass  # Column already exists
    
    def _ensure_canvases_table(self):
        """Ensure canvases table exists with all required columns"""
        # Create canvases table if it doesn't exist
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS canvases (
                canvas_id TEXT PRIMARY KEY,
                canvas_name TEXT NOT NULL,
                canvas_elements TEXT NOT NULL DEFAULT '[]',
                element_counts TEXT NOT NULL DEFAULT '{}',
                date_created TEXT NOT NULL,
                date_updated TEXT NOT NULL,
                last_saved TEXT,
                canvas_type TEXT NOT NULL DEFAULT 'group_map',
                canvas_state TEXT DEFAULT '{}',
                metadata TEXT DEFAULT '{}'
            )
        """)
        
        # Check for missing columns and add them
        self.cursor.execute("PRAGMA table_info(canvases)")
        existing_columns = {row[1] for row in self.cursor.fetchall()}
        
        required_columns = {
            "canvas_id": "TEXT PRIMARY KEY",
            "canvas_name": "TEXT NOT NULL",
            "canvas_elements": "TEXT NOT NULL DEFAULT '[]'",
            "element_counts": "TEXT NOT NULL DEFAULT '{}'",
            "date_created": "TEXT NOT NULL",
            "date_updated": "TEXT NOT NULL",
            "last_saved": "TEXT",
            "canvas_type": "TEXT NOT NULL DEFAULT 'group_map'",
            "canvas_state": "TEXT DEFAULT '{}'",
            "metadata": "TEXT DEFAULT '{}'"
        }
        
        for column_name, column_type in required_columns.items():
            if column_name not in existing_columns:
                try:
                    self.cursor.execute(f"ALTER TABLE canvases ADD COLUMN {column_name} {column_type}")
                    LOGGER.info(f"Added missing '{column_name}' column to canvases table")
                except sqlite3.OperationalError:
                    pass  # Column already exists
        
        # Create indexes for performance
        self._ensure_canvas_indexes()
    
    def _ensure_canvas_indexes(self):
        """Ensure all required indexes exist for the canvases table"""
        indexes = [
            ("idx_canvases_id", "canvas_id", "UNIQUE"),
            ("idx_canvases_name", "canvas_name", "INDEX"),
            ("idx_canvases_type", "canvas_type", "INDEX"),
            ("idx_canvases_created", "date_created", "INDEX"),
            ("idx_canvases_updated", "date_updated", "INDEX"),
            ("idx_canvases_type_updated", "canvas_type, date_updated", "INDEX")
        ]
        
        for index_name, columns, index_type in indexes:
            try:
                if index_type == "UNIQUE":
                    self.cursor.execute(f"CREATE UNIQUE INDEX IF NOT EXISTS {index_name} ON canvases ({columns})")
                else:
                    self.cursor.execute(f"CREATE INDEX IF NOT EXISTS {index_name} ON canvases ({columns})")
                LOGGER.info(f"Created index {index_name} on canvases table")
            except sqlite3.OperationalError:
                pass  # Index already exists
    
    # Canvas Management Methods
    
    def create_canvas(self, canvas_id: str, canvas_name: str, canvas_type: str = "group_map", 
                     initial_elements: List[Dict] = None, initial_state: Dict = None) -> bool:
        """Create a new canvas"""
        try:
            now = datetime.now().isoformat()
            elements = json.dumps(initial_elements or [])
            state = json.dumps(initial_state or {})
            counts = self._calculate_element_counts(initial_elements or [])
            
            self.cursor.execute("""
                INSERT INTO canvases (canvas_id, canvas_name, canvas_elements, element_counts, 
                                    date_created, date_updated, last_saved, canvas_type, canvas_state)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (canvas_id, canvas_name, elements, counts, now, now, None, canvas_type, state))
            
            self.conn.commit()
            LOGGER.info(f"Created canvas: {canvas_name} (ID: {canvas_id})")
            return True
        except Exception as e:
            LOGGER.error(f"Failed to create canvas: {e}")
            return False
    
    def get_canvas(self, canvas_id: str) -> Optional[Dict]:
        """Retrieve a canvas by ID"""
        try:
            self.cursor.execute("""
                SELECT canvas_id, canvas_name, canvas_elements, element_counts, 
                       date_created, date_updated, canvas_type, canvas_state, metadata
                FROM canvases WHERE canvas_id = ?
            """, (canvas_id,))
            
            row = self.cursor.fetchone()
            if row:
                return {
                    "canvas_id": row[0],
                    "canvas_name": row[1],
                    "canvas_elements": json.loads(row[2]) if row[2] else [],
                    "element_counts": json.loads(row[3]) if row[3] else {},
                    "date_created": row[4],
                    "date_updated": row[5],
                    "canvas_type": row[6],
                    "canvas_state": json.loads(row[7]) if row[7] else {},
                    "metadata": json.loads(row[8]) if row[8] else {}
                }
            return None
        except Exception as e:
            LOGGER.error(f"Failed to get canvas {canvas_id}: {e}")
            return None
    
    def get_all_canvases(self, canvas_type: Optional[str] = None) -> List[Dict]:
        """Retrieve all canvases, optionally filtered by type"""
        try:
            if canvas_type:
                self.cursor.execute("""
                    SELECT canvas_id, canvas_name, canvas_elements, element_counts, 
                           date_created, date_updated, canvas_type, canvas_state, metadata
                    FROM canvases WHERE canvas_type = ? ORDER BY date_updated DESC
                """, (canvas_type,))
            else:
                self.cursor.execute("""
                    SELECT canvas_id, canvas_name, canvas_elements, element_counts, 
                           date_created, date_updated, canvas_type, canvas_state, metadata
                    FROM canvases ORDER BY date_updated DESC
                """)
            
            canvases = []
            for row in self.cursor.fetchall():
                canvases.append({
                    "canvas_id": row[0],
                    "canvas_name": row[1],
                    "canvas_elements": json.loads(row[2]) if row[2] else [],
                    "element_counts": json.loads(row[3]) if row[3] else {},
                    "date_created": row[4],
                    "date_updated": row[5],
                    "canvas_type": row[6],
                    "canvas_state": json.loads(row[7]) if row[7] else {},
                    "metadata": json.loads(row[8]) if row[8] else {}
                })
            return canvases
        except Exception as e:
            LOGGER.error(f"Failed to get canvases: {e}")
            return []
    
    def update_canvas(self, canvas_id: str, updates: Dict) -> bool:
        """Update canvas properties"""
        try:
            now = datetime.now().isoformat()
            
            # Build dynamic update query
            set_clauses = []
            params = []
            
            if "canvas_name" in updates:
                set_clauses.append("canvas_name = ?")
                params.append(updates["canvas_name"])
            
            if "canvas_elements" in updates:
                set_clauses.append("canvas_elements = ?")
                params.append(json.dumps(updates["canvas_elements"]))
                # Recalculate element counts
                counts = self._calculate_element_counts(updates["canvas_elements"])
                set_clauses.append("element_counts = ?")
                params.append(counts)
            
            if "canvas_type" in updates:
                set_clauses.append("canvas_type = ?")
                params.append(updates["canvas_type"])
            
            if "canvas_state" in updates:
                set_clauses.append("canvas_state = ?")
                params.append(json.dumps(updates["canvas_state"]))
            
            if "metadata" in updates:
                set_clauses.append("metadata = ?")
                params.append(json.dumps(updates["metadata"]))
            
            # Always update the date_updated and last_saved
            set_clauses.append("date_updated = ?")
            params.append(now)
            set_clauses.append("last_saved = ?")
            params.append(now)
            
            if set_clauses:
                params.append(canvas_id)
                query = f"UPDATE canvases SET {', '.join(set_clauses)} WHERE canvas_id = ?"
                self.cursor.execute(query, params)
                self.conn.commit()
                LOGGER.info(f"Updated canvas: {canvas_id}")
                return True
            
            return False
        except Exception as e:
            LOGGER.error(f"Failed to update canvas {canvas_id}: {e}")
            return False
    
    def delete_canvas(self, canvas_id: str) -> bool:
        """Delete a canvas"""
        try:
            self.cursor.execute("DELETE FROM canvases WHERE canvas_id = ?", (canvas_id,))
            self.conn.commit()
            LOGGER.info(f"Deleted canvas: {canvas_id}")
            return True
        except Exception as e:
            LOGGER.error(f"Failed to delete canvas {canvas_id}: {e}")
            return False
    
    def add_canvas_element(self, canvas_id: str, element: Dict) -> bool:
        """Add a single element to a canvas"""
        try:
            canvas = self.get_canvas(canvas_id)
            if not canvas:
                return False
            
            elements = canvas["canvas_elements"]
            elements.append(element)
            
            return self.update_canvas(canvas_id, {"canvas_elements": elements})
        except Exception as e:
            LOGGER.error(f"Failed to add element to canvas {canvas_id}: {e}")
            return False
    
    def update_canvas_element(self, canvas_id: str, element_id: str, updates: Dict) -> bool:
        """Update a specific element in a canvas"""
        try:
            canvas = self.get_canvas(canvas_id)
            if not canvas:
                return False
            
            elements = canvas["canvas_elements"]
            for i, element in enumerate(elements):
                if element.get("element_id") == element_id:
                    elements[i].update(updates)
                    return self.update_canvas(canvas_id, {"canvas_elements": elements})
            
            return False
        except Exception as e:
            LOGGER.error(f"Failed to update element {element_id} in canvas {canvas_id}: {e}")
            return False
    
    def remove_canvas_element(self, canvas_id: str, element_id: str) -> bool:
        """Remove a specific element from a canvas"""
        try:
            canvas = self.get_canvas(canvas_id)
            if not canvas:
                return False
            
            elements = canvas["canvas_elements"]
            elements = [e for e in elements if e.get("element_id") != element_id]
            
            return self.update_canvas(canvas_id, {"canvas_elements": elements})
        except Exception as e:
            LOGGER.error(f"Failed to remove element {element_id} from canvas {canvas_id}: {e}")
            return False
    
    def _calculate_element_counts(self, elements: List[Dict]) -> str:
        """Calculate element counts by type"""
        counts = {"contacts": 0, "groups": 0, "decks": 0, "all": len(elements)}
        
        # Map element types to count keys
        type_mapping = {
            "contact": "contacts",
            "group": "groups", 
            "deck": "decks"
        }
        
        for element in elements:
            element_type = element.get("element_type", "unknown")
            if element_type in type_mapping:
                count_key = type_mapping[element_type]
                counts[count_key] += 1
        
        return json.dumps(counts)
    
    def search_canvases(self, query: str, canvas_type: Optional[str] = None) -> List[Dict]:
        """Search canvases by name"""
        try:
            search_pattern = f"%{query}%"
            
            if canvas_type:
                self.cursor.execute("""
                    SELECT canvas_id, canvas_name, canvas_elements, element_counts, 
                           date_created, date_updated, canvas_type, canvas_state, metadata
                    FROM canvases 
                    WHERE canvas_name LIKE ? AND canvas_type = ? 
                    ORDER BY date_updated DESC
                """, (search_pattern, canvas_type))
            else:
                self.cursor.execute("""
                    SELECT canvas_id, canvas_name, canvas_elements, element_counts, 
                           date_created, date_updated, canvas_type, canvas_state, metadata
                    FROM canvases 
                    WHERE canvas_name LIKE ? 
                    ORDER BY date_updated DESC
                """, (search_pattern,))
            
            canvases = []
            for row in self.cursor.fetchall():
                canvases.append({
                    "canvas_id": row[0],
                    "canvas_name": row[1],
                    "canvas_elements": json.loads(row[2]) if row[2] else [],
                    "element_counts": json.loads(row[3]) if row[3] else {},
                    "date_created": row[4],
                    "date_updated": row[5],
                    "canvas_type": row[6],
                    "canvas_state": json.loads(row[7]) if row[7] else {},
                    "metadata": json.loads(row[8]) if row[8] else {}
                })
            return canvases
        except Exception as e:
            LOGGER.error(f"Failed to search canvases: {e}")
            return []
    
    def _show_database_error_dialog(self):
        """Show database error dialog and open settings"""
        try:
            import subprocess
            import sys
            
            # Create AppleScript to show dialog and open settings
            script = f'''
            display dialog "Database error: No database found at {self.db_path}" buttons {{"Open Settings", "Cancel"}} default button "Open Settings"
            if button returned of result is "Open Settings" then
                tell application "System Events"
                    tell process "My CRM"
                        click menu item "Settings" of menu "My CRM" of menu bar 1
                    end tell
                end tell
            end if
            '''
            
            subprocess.run(["osascript", "-e", script], check=False)
        except Exception as e:
            LOGGER.error(f"Failed to show database error dialog: {e}")
    
    def update_group_membership(self, contact_id: int, group_id: int, operation: str):
        """
        Update group membership for a contact
        
        Args:
            contact_id: ID of the contact
            group_id: ID of the group
            operation: 'add' or 'remove'
        """
        try:
            # Update contact's groups field
            self.cursor.execute("SELECT groups FROM contacts WHERE id = ?", (contact_id,))
            result = self.cursor.fetchone()
            
            if result:
                contact_groups = json.loads(result[0] or '{}')
                
                if operation == "add":
                    contact_groups[str(group_id)] = group_id
                elif operation == "remove":
                    contact_groups.pop(str(group_id), None)
                
                self.cursor.execute(
                    "UPDATE contacts SET groups = ? WHERE id = ?",
                    (json.dumps(contact_groups), contact_id)
                )
            
            # Update group's participants field
            self.cursor.execute("SELECT participants FROM groups WHERE id = ?", (group_id,))
            result = self.cursor.fetchone()
            
            if result:
                # Parse participants as array of objects: [{"contact_id": "phone", "contact_uuid": "uuid"}, ...]
                try:
                    group_participants = json.loads(result[0] or '[]')
                    if not isinstance(group_participants, list):
                        # Handle legacy format - convert to new format
                        group_participants = []
                        LOGGER.warning(f"Converting legacy participants format for group {group_id}")
                except json.JSONDecodeError:
                    group_participants = []
                    LOGGER.warning(f"Invalid JSON in participants field for group {group_id}, resetting to empty array")
                
                # Get contact phone number for the participant object
                contact_phone = None
                self.cursor.execute("SELECT phone FROM contacts WHERE id = ?", (contact_id,))
                contact_result = self.cursor.fetchone()
                if contact_result:
                    contact_phone = contact_result[0]
                
                if operation == "add" and contact_phone:
                    # Check if contact is already in participants
                    existing_participant = next((p for p in group_participants if p.get("contact_id") == contact_phone), None)
                    if not existing_participant:
                        participant_obj = {
                            "contact_id": contact_phone,
                            "contact_uuid": ""  # We don't have contact UUIDs in this context
                        }
                        group_participants.append(participant_obj)
                elif operation == "remove" and contact_phone:
                    # Remove participant by contact_id (phone)
                    group_participants = [p for p in group_participants if p.get("contact_id") != contact_phone]
                
                # Update group size and timestamp
                new_size = len(group_participants)
                current_time = datetime.now().isoformat()
                
                self.cursor.execute(
                    "UPDATE groups SET participants = ?, size = ?, time_last_updated = ? WHERE id = ?",
                    (json.dumps(group_participants), new_size, current_time, group_id)
                )
            
            self.conn.commit()
            LOGGER.info(f"Successfully updated group membership: contact {contact_id} {operation}ed to group {group_id}")
            return True
            
        except Exception as e:
            LOGGER.error(f"Failed to update group membership: {e}")
            self.conn.rollback()
            return False
    
    def get_contact_groups(self, contact_id: int) -> List[int]:
        """Get list of group IDs that a contact belongs to"""
        try:
            self.cursor.execute("SELECT groups FROM contacts WHERE id = ?", (contact_id,))
            result = self.cursor.fetchone()
            
            if result and result[0]:
                groups_dict = json.loads(result[0])
                return list(groups_dict.values())
            return []
            
        except Exception as e:
            LOGGER.error(f"Failed to get contact groups: {e}")
            return []
    
    def get_group_participants(self, group_id: int) -> List[int]:
        """Get list of contact IDs that belong to a group"""
        try:
            self.cursor.execute("SELECT participants FROM groups WHERE id = ?", (group_id,))
            result = self.cursor.fetchone()
            
            if result and result[0]:
                participants_data = json.loads(result[0])
                
                # Handle new format: [{"contact_id": "phone", "contact_uuid": "uuid"}, ...]
                if isinstance(participants_data, list):
                    # Extract contact IDs from phone numbers
                    contact_ids = []
                    for participant in participants_data:
                        if isinstance(participant, dict) and "contact_id" in participant:
                            # Get contact ID from phone number
                            phone = participant["contact_id"]
                            self.cursor.execute("SELECT id FROM contacts WHERE phone = ?", (phone,))
                            contact_result = self.cursor.fetchone()
                            if contact_result:
                                contact_ids.append(contact_result[0])
                    return contact_ids
                # Handle legacy format: {"contact_id": contact_id, ...}
                elif isinstance(participants_data, dict):
                    LOGGER.warning(f"Legacy participants format detected for group {group_id}, converting...")
                    return list(participants_data.values())
            
            return []
            
        except Exception as e:
            LOGGER.error(f"Failed to get group participants: {e}")
            return []
    
    def update_group_participants(self, group_id: str, participants_data: List[Dict[str, str]]) -> bool:
        """Update group participants - MERGES new participants with existing ones using source-based tracking"""
        try:
            # First, get existing participants from the database
            group_id_int = int(group_id)
            self.cursor.execute("SELECT participants FROM groups WHERE id = ?", (group_id_int,))
            result = self.cursor.fetchone()
            
            existing_participants = []
            if result and result[0]:
                try:
                    existing_participants = json.loads(result[0])
                    LOGGER.info(f"Found {len(existing_participants)} existing participants in group {group_id}")
                except json.JSONDecodeError:
                    LOGGER.warning(f"Could not parse existing participants for group {group_id}, starting fresh")
                    existing_participants = []
            
            # Create a dictionary keyed by participant ID (phone) for easy lookup
            participants_dict = {}
            for participant in existing_participants:
                participant_id = participant.get("id")
                if participant_id:
                    participants_dict[participant_id] = participant
            
            # Merge new participants with existing ones
            for new_participant in participants_data:
                participant_id = new_participant.get("id")
                if not participant_id:
                    LOGGER.warning(f"Skipping participant with no ID: {new_participant}")
                    continue
                
                if participant_id in participants_dict:
                    # Participant exists - merge sources
                    existing_participant = participants_dict[participant_id]
                    existing_sources = existing_participant.get("Source", [])
                    new_sources = new_participant.get("Source", [])
                    
                    # Merge sources - avoid duplicates by checking Type+UUID combo
                    merged_sources = list(existing_sources)
                    for new_source in new_sources:
                        source_type = new_source.get("Type")
                        source_uuid = new_source.get("UUID")
                        
                        # Check if this source already exists
                        source_exists = any(
                            s.get("Type") == source_type and s.get("UUID") == source_uuid
                            for s in merged_sources
                        )
                        
                        if not source_exists:
                            merged_sources.append(new_source)
                            LOGGER.info(f"Added new source {source_type}:{source_uuid} to participant {participant_id}")
                        else:
                            LOGGER.info(f"Source {source_type}:{source_uuid} already exists for participant {participant_id}")
                    
                    # Update the participant with merged sources
                    participants_dict[participant_id]["Source"] = merged_sources
                    # Update name and UUID if they've changed
                    participants_dict[participant_id]["name"] = new_participant.get("name", existing_participant.get("name"))
                    participants_dict[participant_id]["UUID"] = new_participant.get("UUID", existing_participant.get("UUID"))
                else:
                    # New participant - add them
                    participants_dict[participant_id] = new_participant
                    LOGGER.info(f"Added new participant {participant_id} to group {group_id}")
            
            # Convert back to list
            updated_participants = list(participants_dict.values())
            new_size = len(updated_participants)
            current_time = datetime.now().isoformat()
            
            # Update the database
            self.cursor.execute(
                "UPDATE groups SET participants = ?, size = ?, time_last_updated = ? WHERE id = ?",
                (json.dumps(updated_participants), new_size, current_time, group_id_int)
            )
            
            self.conn.commit()
            LOGGER.info(f"Successfully updated group participants: group {group_id} now has {new_size} participants")
            return True
            
        except Exception as e:
            LOGGER.error(f"Failed to update group participants: {e}")
            self.conn.rollback()
            return False
    
    def remove_group_participant_source(self, group_id: str, participants_data: List[Dict[str, str]]) -> bool:
        """Remove specific sources from participants - removes participant if no sources remain"""
        try:
            # Get existing participants from the database
            group_id_int = int(group_id)
            self.cursor.execute("SELECT participants FROM groups WHERE id = ?", (group_id_int,))
            result = self.cursor.fetchone()
            
            existing_participants = []
            if result and result[0]:
                try:
                    existing_participants = json.loads(result[0])
                    LOGGER.info(f"Found {len(existing_participants)} existing participants in group {group_id}")
                except json.JSONDecodeError:
                    LOGGER.warning(f"Could not parse existing participants for group {group_id}")
                    return False
            
            # Create a dictionary keyed by participant ID (phone) for easy lookup
            participants_dict = {}
            for participant in existing_participants:
                participant_id = participant.get("id")
                if participant_id:
                    participants_dict[participant_id] = participant
            
            # Remove sources from participants
            for removal_data in participants_data:
                participant_id = removal_data.get("id")
                if not participant_id:
                    LOGGER.warning(f"Skipping removal data with no ID: {removal_data}")
                    continue
                
                if participant_id in participants_dict:
                    existing_participant = participants_dict[participant_id]
                    existing_sources = existing_participant.get("Source", [])
                    sources_to_remove = removal_data.get("Source", [])
                    
                    # Remove matching sources
                    updated_sources = []
                    for existing_source in existing_sources:
                        source_type = existing_source.get("Type")
                        source_uuid = existing_source.get("UUID")
                        
                        # Check if this source should be removed
                        should_remove = any(
                            s.get("Type") == source_type and s.get("UUID") == source_uuid
                            for s in sources_to_remove
                        )
                        
                        if not should_remove:
                            updated_sources.append(existing_source)
                        else:
                            LOGGER.info(f"Removed source {source_type}:{source_uuid} from participant {participant_id}")
                    
                    # If no sources remain, remove the participant entirely
                    if not updated_sources:
                        del participants_dict[participant_id]
                        LOGGER.info(f"Removed participant {participant_id} from group {group_id} (no sources remaining)")
                    else:
                        # Update the participant with remaining sources
                        participants_dict[participant_id]["Source"] = updated_sources
                        LOGGER.info(f"Updated participant {participant_id} with {len(updated_sources)} remaining sources")
                else:
                    LOGGER.warning(f"Participant {participant_id} not found in group {group_id}")
            
            # Convert back to list
            updated_participants = list(participants_dict.values())
            new_size = len(updated_participants)
            current_time = datetime.now().isoformat()
            
            # Update the database
            self.cursor.execute(
                "UPDATE groups SET participants = ?, size = ?, time_last_updated = ? WHERE id = ?",
                (json.dumps(updated_participants), new_size, current_time, group_id_int)
            )
            
            self.conn.commit()
            LOGGER.info(f"Successfully removed sources from group participants: group {group_id} now has {new_size} participants")
            return True
            
        except Exception as e:
            LOGGER.error(f"Failed to remove participant sources: {e}")
            self.conn.rollback()
            return False
    
    def get_contact_by_uid(self, uid: str) -> Optional[Dict[str, Any]]:
        """Get a contact by UID (phone number)"""
        try:
            self.cursor.execute("SELECT * FROM contacts WHERE phone = ?", (uid,))
            result = self.cursor.fetchone()
            
            if result:
                # Get column names
                columns = [description[0] for description in self.cursor.description]
                
                # Create dictionary from row data
                contact_data = dict(zip(columns, result))
                
                LOGGER.info(f"Successfully retrieved contact with phone: {uid}")
                return contact_data
            else:
                LOGGER.warning(f"Contact not found with phone: {uid}")
                return None
                
        except Exception as e:
            LOGGER.error(f"Failed to get contact by phone: {e}")
            return None
    
    def get_group_by_name(self, name: str) -> Optional[Dict[str, Any]]:
        """Get a group by name"""
        try:
            self.cursor.execute("""
                SELECT id, name, color, created_at, parent_id, member_phones, 
                       linked_group_ids, metadata, is_deck, participants, canvases
                FROM groups WHERE name = ?
            """, (name,))
            
            row = self.cursor.fetchone()
            if row:
                return {
                    "id": row[0],
                    "name": row[1],
                    "color": row[2],
                    "created_at": row[3],
                    "parent_id": row[4],
                    "member_phones": row[5],
                    "linked_group_ids": row[6],
                    "metadata": row[7],
                    "is_deck": row[8],
                    "participants": row[9],
                    "canvases": row[10]
                }
            else:
                LOGGER.warning(f"Group not found with name: {name}")
                return None
                
        except Exception as e:
            LOGGER.error(f"Failed to get group by name: {e}")
            return None
    
    def get_last_message_timestamp(self) -> Optional[int]:
        """Get the timestamp of the most recent message in the database"""
        try:
            # Check if messages table exists
            self.cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='messages'")
            if not self.cursor.fetchone():
                LOGGER.warning("Messages table does not exist")
                return None
            
            # Get the maximum timestamp from the messages table
            self.cursor.execute("""
                SELECT MAX(COALESCE(timestamp, 0))
                FROM messages
                WHERE timestamp IS NOT NULL AND timestamp > 0
            """)
            
            result = self.cursor.fetchone()
            if result and result[0]:
                return result[0]
            return None
            
        except Exception as e:
            LOGGER.error(f"Failed to get last message timestamp: {e}")
            return None

    # MARK: - Group Management Functions
    
    def create_group(self, group_id: str, name: str, color: str, participants: List[Dict[str, str]] = None, canvases: List[str] = None) -> Optional[int]:
        """Create a new group and return the ID"""
        try:
            # Ensure participants is in the correct format: [{"contact_id": "phone", "contact_uuid": "uuid"}, ...]
            if participants is None:
                participants = []
            elif isinstance(participants, list) and participants and isinstance(participants[0], str):
                # Convert legacy string format to object format
                participants = [{"contact_id": phone, "contact_uuid": ""} for phone in participants]
                LOGGER.warning(f"Converting legacy participants format for new group: {name}")
            
            canvases = canvases or []
            current_time = datetime.now().isoformat()
            
            # For auto-increment ID, we don't specify the id field
            self.cursor.execute("""
                INSERT INTO groups (name, color, created_at, participants, canvases)
                VALUES (?, ?, ?, ?, ?)
            """, (
                name,
                color,
                current_time,
                json.dumps(participants),
                json.dumps(canvases)
            ))
            
            # Get the ID of the created group
            group_id = self.cursor.lastrowid
            
            self.conn.commit()
            LOGGER.info(f"Successfully created group: {name} with ID: {group_id}")
            return group_id
            
        except Exception as e:
            LOGGER.error(f"Failed to create group: {e}")
            self.conn.rollback()
            return None
    
    def get_group(self, group_id: str) -> Optional[Dict[str, Any]]:
        """Get a group by ID"""
        try:
            self.cursor.execute("""
                SELECT id, name, color, created_at, parent_id, member_phones, 
                       linked_group_ids, metadata, is_deck, participants, canvases
                FROM groups WHERE id = ?
            """, (group_id,))
            
            row = self.cursor.fetchone()
            if row:
                return {
                    "id": row[0],
                    "name": row[1],
                    "color": row[2],
                    "created_at": row[3],
                    "parent_id": row[4],
                    "member_phones": json.loads(row[5]) if row[5] else [],
                    "linked_group_ids": json.loads(row[6]) if row[6] else [],
                    "metadata": json.loads(row[7]) if row[7] else {},
                    "is_deck": bool(row[8]),
                    "participants": json.loads(row[9]) if row[9] else [],
                    "canvases": json.loads(row[10]) if row[10] else []
                }
            return None
            
        except Exception as e:
            LOGGER.error(f"Failed to get group: {e}")
            return None
    
    def update_group(self, group_id: str, updates: Dict[str, Any]) -> bool:
        """Update a group"""
        try:
            if not updates:
                return True
            
            set_clauses = []
            values = []
            
            for key, value in updates.items():
                if key in ["participants", "canvases", "member_phones", "linked_group_ids", "metadata"]:
                    set_clauses.append(f"{key} = ?")
                    values.append(json.dumps(value))
                else:
                    set_clauses.append(f"{key} = ?")
                    values.append(value)
            
            values.append(group_id)
            
            query = f"UPDATE groups SET {', '.join(set_clauses)} WHERE id = ?"
            self.cursor.execute(query, values)
            
            self.conn.commit()
            LOGGER.info(f"Successfully updated group: {group_id}")
            return True
            
        except Exception as e:
            LOGGER.error(f"Failed to update group: {e}")
            self.conn.rollback()
            return False
    
    def delete_group(self, group_id: str) -> bool:
        """Delete a group"""
        try:
            self.cursor.execute("DELETE FROM groups WHERE id = ?", (group_id,))
            self.conn.commit()
            LOGGER.info(f"Successfully deleted group: {group_id}")
            return True
            
        except Exception as e:
            LOGGER.error(f"Failed to delete group: {e}")
            self.conn.rollback()
            return False
    
    def get_all_groups(self) -> List[Dict[str, Any]]:
        """Get all groups"""
        try:
            self.cursor.execute("""
                SELECT id, name, color, created_at, parent_id, member_phones, 
                       linked_group_ids, metadata, is_deck, participants, canvases
                FROM groups
                ORDER BY created_at DESC
            """)
            
            groups = []
            for row in self.cursor.fetchall():
                groups.append({
                    "id": row[0],
                    "name": row[1],
                    "color": row[2],
                    "created_at": row[3],
                    "parent_id": row[4],
                    "member_phones": json.loads(row[5]) if row[5] else [],
                    "linked_group_ids": json.loads(row[6]) if row[6] else [],
                    "metadata": json.loads(row[7]) if row[7] else {},
                    "is_deck": bool(row[8]),
                    "participants": json.loads(row[9]) if row[9] else [],
                    "canvases": json.loads(row[10]) if row[10] else []
                })
            
            return groups
            
        except Exception as e:
            LOGGER.error(f"Failed to get all groups: {e}")
            return []
    
    def add_group_to_canvas(self, group_id: str, canvas_id: str) -> bool:
        """Add a group to a canvas"""
        try:
            # Get current canvases for the group
            group = self.get_group(group_id)
            if not group:
                LOGGER.error(f"Group not found: {group_id}")
                return False
            
            canvases = group.get("canvases", [])
            if canvas_id not in canvases:
                canvases.append(canvas_id)
                
                self.cursor.execute(
                    "UPDATE groups SET canvases = ? WHERE id = ?",
                    (json.dumps(canvases), group_id)
                )
                self.conn.commit()
                LOGGER.info(f"Successfully added group {group_id} to canvas {canvas_id}")
            
            return True
            
        except Exception as e:
            LOGGER.error(f"Failed to add group to canvas: {e}")
            self.conn.rollback()
            return False
    
    def add_contact_to_canvas(self, contact_id: str, canvas_id: str) -> bool:
        """Add a contact to a canvas"""
        try:
            # For contacts, we use the phone number as the contact_id
            # This method ensures the contact is properly associated with the canvas
            # The actual canvas element will be created by the saveCanvasToDatabase method
            
            # Verify the contact exists in the database
            self.cursor.execute("SELECT id FROM contacts WHERE phone = ?", (contact_id,))
            contact = self.cursor.fetchone()
            
            if not contact:
                LOGGER.error(f"Contact not found with phone: {contact_id}")
                return False
            
            LOGGER.info(f"Successfully verified contact {contact_id} exists for canvas {canvas_id}")
            return True
            
        except Exception as e:
            LOGGER.error(f"Failed to add contact to canvas: {e}")
            self.conn.rollback()
            return False
    
    def remove_group_from_canvas(self, group_id: str, canvas_id: str) -> bool:
        """Remove a group from a canvas"""
        try:
            # Get current canvases for the group
            group = self.get_group(group_id)
            if not group:
                LOGGER.error(f"Group not found: {group_id}")
                return False
            
            canvases = group.get("canvases", [])
            if canvas_id in canvases:
                canvases.remove(canvas_id)
                
                self.cursor.execute(
                    "UPDATE groups SET canvases = ? WHERE id = ?",
                    (json.dumps(canvases), group_id)
                )
                self.conn.commit()
                LOGGER.info(f"Successfully removed group {group_id} from canvas {canvas_id}")
            
            return True
            
        except Exception as e:
            LOGGER.error(f"Failed to remove group from canvas: {e}")
            self.conn.rollback()
            return False
    
    def get_next_group_name(self) -> str:
        """Get the next available group name (Group 1, Group 2, etc.) - reuses missing numbers"""
        try:
            self.cursor.execute("SELECT name FROM groups WHERE name LIKE 'Group %' ORDER BY name")
            existing_names = [row[0] for row in self.cursor.fetchall()]
            
            # Extract numbers from existing names
            existing_numbers = []
            for name in existing_names:
                try:
                    number = int(name.split()[-1])
                    existing_numbers.append(number)
                except (ValueError, IndexError):
                    continue
            
            # Find the first missing number starting from 1
            if not existing_numbers:
                return "Group 1"
            
            # Sort existing numbers and find the first gap
            existing_numbers.sort()
            expected_number = 1
            
            for existing_number in existing_numbers:
                if existing_number == expected_number:
                    expected_number += 1
                elif existing_number > expected_number:
                    # Found a gap, use the expected number
                    break
            
            return f"Group {expected_number}"
            
        except Exception as e:
            LOGGER.error(f"Failed to get next group name: {e}")
            return "Group 1"

# Global database manager instance
_db_manager = None

def get_database_manager() -> DatabaseManager:
    """Get or create global database manager instance"""
    global _db_manager
    if _db_manager is None:
        _db_manager = DatabaseManager()
    return _db_manager

def ensure_database_connection() -> bool:
    """Ensure database connection is established"""
    manager = get_database_manager()
    if not manager.conn:
        return manager.connect()
    return True
