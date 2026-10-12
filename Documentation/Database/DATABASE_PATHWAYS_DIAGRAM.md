# Database Pathways Diagram

## User Input to Database Change Pathways

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                USER INTERFACE LAYER                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐             │
│  │   Canvas Views  │    │  Contacts Bar   │    │  Settings UI    │             │
│  │                 │    │                 │    │                 │             │
│  │ • Drag & Drop   │    │ • Add/Edit      │    │ • Preferences   │             │
│  │ • Pan/Zoom      │    │ • Search/Filter │    │ • Database Path │             │
│  │ • Element Move  │    │ • Selection     │    │ • UI Settings   │             │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘             │
│           │                       │                       │                    │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐             │
│  │  Group Dialogs  │    │ Quick Send UI   │    │  Canvas Editor  │             │
│  │                 │    │                 │    │                 │             │
│  │ • Create Group  │    │ • Batch Message │    │ • Canvas Layout │             │
│  │ • Edit Group    │    │ • Schedule Send │    │ • Element Mgmt  │             │
│  │ • Delete Group  │    │ • Template Edit │    │ • Canvas State  │             │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘             │
│           │                       │                       │                    │
│  ┌─────────────────┐    ┌─────────────────┐                                     │
│  │   Invite UI     │    │ Drag & Drop UI  │                                     │
│  │                 │    │                 │                                     │
│  │ • Create Invite │    │ • Contact Drag  │                                     │
│  │ • Update Status │    │ • Group Drag    │                                     │
│  │ • Mark Complete │    │ • Cross-Group   │                                     │
│  └─────────────────┘    └─────────────────┘                                     │
│           │                       │                                             │
└───────────┼───────────────────────┼─────────────────────────────────────────────┘
            │                       │
            ▼                       ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              SERVICE LAYER                                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐             │
│  │GroupsMapViewModel│    │DragDropManager  │    │BatchMessageService│           │
│  │                 │    │                 │    │                 │             │
│  │ • moveContact() │    │ • performDrop() │    │ • processBatch() │             │
│  │ • saveCanvas()  │    │ • addToGroup()  │    │ • sendMessage()  │             │
│  │ • saveImmediately│   │ • moveBetween() │    │ • scheduleMsg()  │             │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘             │
│           │                       │                       │                    │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐             │
│  │CanvasRepository │    │GroupEditingService│   │InviteOperations │             │
│  │                 │    │                 │    │                 │             │
│  │ • updateCanvas()│    │ • createGroup() │    │ • createInvite()│             │
│  │ • addElement()  │    │ • updateGroup() │    │ • updateInvite()│             │
│  │ • deleteCanvas()│    │ • deleteGroup() │    │ • markComplete()│             │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘             │
│           │                       │                       │                    │
└───────────┼───────────────────────┼───────────────────────┼────────────────────┘
            │                       │                       │
            ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            DATA PROVIDER LAYER                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────────┐│
│  │                        SQLiteDataProvider                                   ││
│  │                                                                             ││
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             ││
│  │  │ Contact Methods │  │  Group Methods  │  │ Invite Methods  │             ││
│  │  │                 │  │                 │  │                 │             ││
│  │  │ • updateContact │  │ • updateGroup   │  │ • createInvite  │             ││
│  │  │ • deleteContact │  │ • createGroup   │  │ • updateInvite  │             ││
│  │  │ • addContact    │  │ • deleteGroup   │  │ • deleteInvite  │             ││
│  │  │ • fetchContact  │  │ • addToGroup    │  │ • markComplete  │             ││
│  │  └─────────────────┘  │ • removeFromGrp │  └─────────────────┘             ││
│  │                       └─────────────────┘                                 ││
│  │                                                                             ││
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             ││
│  │  │ Canvas Methods  │  │ Batch Methods   │  │ Settings Methods│             ││
│  │  │                 │  │                 │  │                 │             ││
│  │  │ • saveCanvas    │  │ • saveBatchMsg  │  │ • saveSettings  │             ││
│  │  │ • loadCanvas    │  │ • processBatch  │  │ • loadSettings  │             ││
│  │  │ • deleteCanvas  │  │ • scheduleMsg   │  │ • updatePrefs   │             ││
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘             ││
│  └─────────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            DATABASE LAYER                                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────────┐│
│  │                           SQLite Database                                   ││
│  │                                                                             ││
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             ││
│  │  │   contacts      │  │     groups      │  │     invites     │             ││
│  │  │                 │  │                 │  │                 │             ││
│  │  │ • id (INTEGER)  │  │ • id (INTEGER)  │  │ • id (TEXT)     │             ││
│  │  │ • phone (TEXT)  │  │ • name (TEXT)   │  │ • title (TEXT)  │             ││
│  │  │ • name (TEXT)   │  │ • color (TEXT)  │  │ • status (TEXT) │             ││
│  │  │ • email (TEXT)  │  │ • members (TEXT)│  │ • priority (INT)│             ││
│  │  │ • address (TEXT)│  │ • canvases (TEXT)│ │ • due_date (TEXT)│             ││
│  │  │ • notes (TEXT)  │  │ • metadata (TEXT)│ │ • created (TEXT) │             ││
│  │  │ • photo (BLOB)  │  │ • is_deck (INT) │  │ • completed (INT)│             ││
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘             ││
│  │                                                                             ││
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             ││
│  │  │ batch_messages  │  │    canvases     │  │  user_settings  │             ││
│  │  │                 │  │                 │  │                 │             ││
│  │  │ • id (TEXT)     │  │ • id (TEXT)     │  │ • key (TEXT)    │             ││
│  │  │ • template (TEXT)│ │ • name (TEXT)   │  │ • value (TEXT)  │             ││
│  │  │ • recipients (TEXT)│ • elements (TEXT)│ │ • type (TEXT)   │             ││
│  │  │ • status (TEXT) │  │ • canvas_type (TEXT)│ • updated (TEXT)│             ││
│  │  │ • scheduled (TEXT)│ │ • state (TEXT) │  │ • user_id (TEXT)│             ││
│  │  │ • sent_count (INT)│ │ • created (TEXT)│ │ • metadata (TEXT)│             ││
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘             ││
│  └─────────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────────┘

## SQL Execution Methods

### 1. Direct SQLite Operations (Swift)
```swift
// Pattern used in SQLiteDataProvider.swift
var statement: OpaquePointer?
sqlite3_prepare_v2(database, query, -1, &statement, nil)
sqlite3_step(statement)
sqlite3_finalize(statement)
```

### 2. Python Script Integration
```swift
// Pattern used in CanvasRepository.swift
let process = ScriptPathResolver.createPythonProcess(
    scriptName: "canvas_manager.py", 
    arguments: ["update_canvas", "--canvas-id", canvasId, "--data", jsonData]
)
```

### 3. Transaction Management
```swift
// Pattern for complex operations
sqlite3_exec(database, "BEGIN TRANSACTION", nil, nil, nil)
// ... multiple operations ...
sqlite3_exec(database, "COMMIT", nil, nil, nil)
```

## Key Trigger Points

1. **Canvas Interactions**: Every drag, drop, pan, zoom triggers immediate database save
2. **Contact Operations**: Add, edit, delete contacts immediately persist to database
3. **Group Management**: All group changes immediately update database
4. **Message Operations**: Batch message creation/sending updates database
5. **Settings Changes**: All preference changes immediately save to database
6. **Invite Management**: All invite operations immediately persist changes

## Database-First Architecture Benefits

- **Single Source of Truth**: Database is authoritative for all application state
- **Real-time Sync**: UI always reflects current database state
- **Crash Recovery**: Application can rebuild UI from database after restart
- **Data Portability**: Database can be moved between systems
- **Audit Trail**: All changes are logged and tracked in database
