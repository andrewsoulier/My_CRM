# My CRM - Personal Contact Relationship Manager

A modern, SwiftUI-based macOS application for managing personal contacts and relationships with advanced drag-and-drop organization, visual mapping, and intelligent search capabilities.

## 🗄️ Database-Centric Architecture

**Core Principle**: All aspects of this application are reflected in the database such that any change to the data anywhere is always reflected in the database. The goal is to be able to take the database in any format and provide a usable UI for the user to interact with it.

- **Database as Single Source of Truth**: All application state, user interactions, and data modifications are persisted in the database
- **UI as Database View**: The user interface is a visual representation of database content
- **Real-time Synchronization**: All changes are immediately synchronized with the database
- **Database Portability**: The application works with any database containing the proper schema

## Features

### 🎯 Core Functionality
- **Visual Contact Organization**: Drag-and-drop contacts into groups, circles, and decks
- **Grid View**: Spreadsheet-style interface for contacts and groups with inline editing, smart chip rendering, auto-expanding custom columns for pasted data, aggregated Notification Center alerts, multi-column sorting/filtering, undo/redo, and an in-view contacts/groups toggle with a collapsible toolbar that supports creating new presets
- **Relationship Maps**: Interactive canvas for visual relationship mapping
- **Groups**: Create and manage contact groups with collapsible groups toolbar
- **Groups Toolbar**: Collapsible sidebar for managing groups and decks with drag & drop and right-click context menus
- **Advanced Search**: Fuzzy search with 2-edit Levenshtein distance
- **Multi-Select**: Range, additive, and command-click selection modes
- **Contacts Bar Selection**: Full keyboard navigation with arrow keys, shift+click, command+click, and range selection
- **SQLite Integration**: Direct connection to your existing CRM database

### 🎨 User Interface
- **Three-Column Layout**: Collapsible navigation and contacts bars
- **Zoom & Pan**: 0.5x to 3x zoom with smooth panning
- **Grid Snapping**: Optional grid alignment for precise positioning
- **Keyboard Shortcuts**: W (toggle nav), ,/. (collapse/expand), Cmd+Z (undo/redo)
- **Context Menus**: Right-click for quick actions on contacts
- **Multi-view Presets**: Save per-user Grid View presets with frozen columns, ordering, and visibility states
- **Chip Styling**: Phone, email, tags, groups, and relationships render as color-coded chips with tooltips for quick scanning

### 🔧 Technical Features
- **Drag & Drop**: Internal and external (VCF export) support with database persistence
- **Real-time Updates**: Live database synchronization for all UI changes
- **Performance Optimized**: 2,000+ contact cache with infinite scroll and database pagination
- **Error Handling**: Graceful fallbacks and user-friendly error messages with database recovery
- **Unit Tests**: Comprehensive test coverage for core functionality and database operations
- **Group Management**: Automatic database persistence for all group changes (name, color, participants)
- **Canvas Synchronization**: Canvas elements automatically update when group metadata changes
- **Database-First Design**: All UI state, user interactions, and data modifications are immediately persisted
- **Stateless UI Components**: UI components reflect database state without independent state management
- **AG Grid Integration**: Native SwiftUI bridge to an AG Grid bundle for high-performance virtualized tables, copy/paste, and smart chip editing
- **System Notifications**: Aggregated grid-edit errors surface through Notification Center via `SystemNotificationDispatcher`

## Recent Updates

### July 7, 2026 - Message & Contact Sync Reliability
- **Added**: `ImportSyncCoordinator` centralizes contact/message import, enrichment, UI refresh, and the `.importSyncCompleted` notification.
- **Added**: `ContactMessageEnrichmentService` (Swift port of the legacy Python enrichment) recomputes `last_message_date`, `total_messages`, and sent/received counts after each import.
- **Added**: `--import-messages` CLI flag for headless catch-up imports when the GUI lacks Full Disk Access.
- **Fixed**: Message import is now gated on **Full Disk Access only**, not Automation authorization, so it no longer gets skipped on startup.
- **Fixed**: `ChatDBMonitor` now triggers a debounced incremental import on `chat.db` changes; a 90s timer provides a fallback.
- **Fixed**: Startup imports refresh the UI on completion (empty→populated contacts now appear without a manual refresh).
- **Fixed**: `ContactsImporter` requests Contacts permission when undetermined and imports **all** phone numbers per contact.
- **Improved**: Contact list loads without profile-photo BLOBs (lazy-loaded), batched message upserts, and deferred macOS Contacts sync for faster startup.

See [MESSAGE_AND_CONTACT_SYNC_RELIABILITY.md](Documentation/Features/Messaging/MESSAGE_AND_CONTACT_SYNC_RELIABILITY.md) for detailed implementation documentation.

### November 8, 2025 - Dock Icon Visibility Toggle
- **Dock Icon**: When the primary My CRM window is shown, the app now switches to a regular activation policy so the Dock displays the My CRM icon.
- **Agent Mode**: Closing the primary UI (via the main window close button or menu action) returns the app to accessory mode, hiding the Dock icon while keeping the menu bar extra available.
- **Window Management**: Main window lifecycle now registers for close notifications to keep Dock visibility in sync and avoid lingering activation state.

### November 8, 2025 - Database Location Hardening & Batch Messaging Schema
- **Relocated Default DB**: new installs now create `~/Library/Application Support/My_CRM/my_crm.db` to avoid iCloud-synced `Documents` folders.
- **Automatic Relocation**: `FirstRunSetup` moves existing databases out of cloud locations, preserves WAL/SHM files, and re-runs migrations with GRDB.
- **Batch Message Schema**: fresh databases include the `source_groups` column; repair utilities and migrations updated to keep legacy installs in sync.
- **Manual Lock Fix**: `fix_database_lock_manual.sh` now unloads Quick Send launch agents, kills helper AppleScripts, and clears trigger files before checkpointing.

### November 8, 2025 - Remote Diagnostics Toolkit
- **Added**: `diagnose_remote_live.sh` with version verification, WAL checkpoints, and integrity tests
- **Added**: `remote_diagnosis_and_fix.sh` to automate remote lock clearing and installer checks
- **Added**: `fix_database_lock_manual.sh` for quick on-device recovery when SSH isn’t available
- **Improved**: Remote playbook now ensures the running app matches the latest `/Applications` build before troubleshooting data issues
- **Reminder**: Always confirm `User_Settings.json` database path matches the expected location on remote machines

### October 26, 2025 - Database I/O Error Prevention and Diagnostics
- **Fixed**: Disk I/O errors on remote machines preventing group creation and database operations
- **Fixed**: "Authorization denied" errors when database lacks write permissions
- **Added**: WAL (Write-Ahead Logging) mode for better concurrency and crash recovery
- **Added**: Explicit SQLite connection flags (READWRITE, CREATE, FULLMUTEX) for better error handling
- **Added**: DatabasePermissionChecker service for write permission testing and cloud sync detection
- **Added**: AppInstanceManager to detect and quit multiple running instances
- **Added**: Comprehensive I/O error diagnostics with actionable recommendations
- **Added**: Permission alerts that guide users to grant Full Disk Access
- **Added**: Cloud sync warnings when database is in potentially problematic locations
- **Result**: Remote machines now detect and prevent I/O errors before they cause corruption

See [DATABASE_IO_ERROR_FIXES.md](Documentation/Database/DATABASE_IO_ERROR_FIXES.md) for detailed implementation documentation.

### October 26, 2025 - Database Repair and Integrity System
- **Fixed**: Missing groups table on remote deployments causing "no such table: groups" error
- **Fixed**: Disk I/O errors during group creation causing database corruption and data loss
- **Fixed**: Duplicate contact nodes created when drag-dropping (same contact, different UUIDs)
- **Fixed**: Quick Send contact list empty due to database corruption
- **Added**: Transaction-based group save operations with automatic rollback on errors
- **Added**: Startup integrity checks to detect missing tables and corruption
- **Added**: DatabaseRepairService for automatic table recreation
- **Added**: Duplicate contact detection using phone number as deduplication key
- **Result**: App now recovers gracefully from corrupted databases and prevents data loss

See [DATABASE_REPAIR_AND_INTEGRITY.md](Documentation/Database/DATABASE_REPAIR_AND_INTEGRITY.md) for detailed repair system documentation.

### October 14, 2025 - Canvas Group Metadata Synchronization
- **Fixed**: Canvas not updating when group name or color is changed via edit group window
- **Improved**: `refreshGroupDataFromDatabase()` now saves canvas to database after updating group metadata
- **Improved**: Canvas element loading now matches groups by database ID instead of creation order
- **Added**: Automatic UI refresh trigger after group metadata updates
- **Result**: Changes to group name/color are now immediately visible in all canvases containing the group

See [GROUP_MANAGEMENT_IMPROVEMENTS.md](Documentation/Features/Groups/GROUP_MANAGEMENT_IMPROVEMENTS.md) for detailed implementation information.

### Pure Swift Implementation (October 2025)
- ✅ **100% Portable:** App now runs on any macOS 14+ without Python installed
- ✅ **Complete Swift Migration:** All Python dependencies eliminated from app bundle
- ✅ **Zero Python scripts in bundle:** Verified - no .py files included
- New Swift services: `CanvasManager.swift`, `GroupManager.swift`, enhanced `MessagesDAO.swift`
- ChatGPT integration now uses `OpenAIProvider` with native Swift API calls
- Contact and message import fully operational in Swift
- **Performance:** 10-50x faster operations with no subprocess overhead
- **Distribution:** Simple .app bundle with no external dependencies
- See `Documentation/Development/SWIFT_MIGRATION_COMPLETE.md` for detailed migration information

### Portability Features
- ✅ **No Python runtime required** - App is pure Swift
- ✅ **No external dependencies** - All functionality built-in
- ✅ **Cross-macOS compatible** - Works on macOS 14.0+
- ✅ **Single file distribution** - Just copy the .app bundle
- ✅ **No setup required** - Instant launch (except Full Disk Access for messages)

### Distribution Ready
- ✅ **Auto-setup** - Database and settings created automatically
- ✅ **Default configuration** - Works out of the box with sensible defaults
- ✅ **Clear error messages** - Helpful guidance when issues occur
- ✅ **Reset to defaults** - Easy recovery from configuration problems
- ✅ **Version tracking** - Track which version you're using
- ✅ **Professional DMG installer** - Easy distribution to other Macs

See `Documentation/User/GETTING_STARTED.md` for setup instructions.
See `Documentation/Build/DMG_USAGE.md` for distribution instructions.

### Verification Checkpoints
- DB snapshot metrics: `Core/Verification/IntegritySnapshot.swift`.
- DB integrity checks: `Core/Verification/DBIntegrityChecks.swift` (FKs, required tables).
- Log scan since checkpoint: `Core/Verification/LogScanService.swift`.
- These run before/after orchestrated tasks to validate swaps as they occur.

## Documentation Hub

- Browse the documentation index at `Documentation/README.md`
- File every new or updated guide inside the appropriate `Documentation/` subfolder so the index stays accurate
- Update the index whenever you add or relocate documentation

### Database Utilities
- `Core/Database/CRMDatabase.swift`: central DB open/pragma utilities; schema/migrations to be added in next phases.

## Architecture

### Project Structure
```
My CRM/
├── App/
│   ├── CRMApp.swift              # Main app entry point
│   └── ContentView.swift         # Root view with three-column layout
├── Core/
│   ├── Models/                   # Data models (Contact, Group, Deck)
│   ├── Protocols/                # DataProvider, ImageProvider interfaces
│   ├── Mock/                     # MockDataProvider with synthetic data
│   └── Services/                 # Core services (DragDrop, Selection, etc.)
├── State/
│   └── AppState.swift            # Global application state
├── UI/
│   ├── Shell/                    # Main UI components
│   ├── Pages/                    # Page-specific views
│   ├── Components/               # Reusable UI components
│   └── Modals/                   # Settings and dialogs
└── Tests/                        # Unit tests
```

### Key Components

#### Data Layer
- **Contact**: Primary data model with SQLite integration and immediate persistence
- **Group**: Visual circles for contact organization with database state management
- **Deck**: Ordered collections for specific purposes with database persistence
- **DataProvider**: Protocol for database abstraction and real-time synchronization
- **DatabaseService**: Core service for all database operations and state management
- **UIStateManager**: Service for persisting UI state and user interactions

#### Services
- **DragDropManager**: Handles drag-and-drop operations with NSItemProvider and database persistence
- **SelectionManager**: Multi-select logic and state management with database synchronization
- **FuzzyMatcher**: Intelligent search with edit distance scoring and search history persistence
- **HotkeyManager**: Keyboard shortcut registration and handling with preference persistence
- **DatabaseSyncService**: Real-time synchronization between UI and database
- **UIStatePersistenceService**: Persists all UI state changes to database

#### UI Components
- **PageNavBarView**: Collapsible navigation with nested folders
- **ContactsBarView**: Infinite scroll contact list with search
- **GroupsToolbarView**: Collapsible groups and decks management toolbar
- **SimplifiedCanvasView**: Interactive canvas for visual organization
- **GroupsMapViewModel**: Card-based group management with groups toolbar

## Getting Started

### Prerequisites
- macOS 14.0 or later
- Xcode 15.0 or later
- Swift 5.10 or later

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd "My CRM"
   ```

2. **Build and Install**
   ```bash
   ./build_app.sh "Initial build"
   ```

3. **Set Up Full Disk Access**
   ```bash
   ./setup_permissions.sh setup
   ```
   
   Or use the enhanced build script:
   ```bash
   ./build_and_setup.sh "Initial build" --auto-permissions
   ```

4. **Launch**: Open from Applications or Spotlight

## 📦 Distribution

### Automated Build + Distribution

The build process now automatically creates a versioned DMG installer and places it in multiple locations:

```bash
# One command to build and create distributable DMG
./build_app.sh "Release v1.0"
```

This automatically:
- ✅ Builds the app
- ✅ Creates DMG installer named `My CRM Installer_v<version>.dmg` in the build directory
- ✅ Copies the same versioned DMG to the project root
- ✅ **Copies a timestamped + versioned DMG (e.g., `My CRM Installer_2025_11_08_12_45_10_v1.2.0.dmg`) to Google Drive for easy sharing**

The DMG includes:
- The My CRM.app bundle
- Applications folder shortcut
- Helper script to remove macOS quarantine
- Installation instructions
- User documentation

Recipients can then:
1. Download DMG from Google Drive
2. Open the DMG
3. Drag My CRM to Applications
4. Run the included helper script
5. Launch the app!

**See [BUILD_AND_DISTRIBUTE.md](Documentation/Build/BUILD_AND_DISTRIBUTE.md) for automated workflow.**  
**See [DMG_USAGE.md](Documentation/Build/DMG_USAGE.md) for manual DMG creation.**

## 🔐 Full Disk Access Automation

My CRM includes automated permission setup to streamline the Full Disk Access process:

- **Permission Setup Script**: `./setup_permissions.sh` - Guides you through granting Full Disk Access
- **Enhanced Build**: `./build_and_setup.sh` - Builds the app and sets up permissions in one step
- **Desktop Shortcut**: Automatically created for easy future access
- **Verification**: Tests that Full Disk Access is working correctly

See [FULL_DISK_ACCESS_AUTOMATION.md](Documentation/Operations/FULL_DISK_ACCESS_AUTOMATION.md) for detailed information.

### Database Setup

**Automatic Database Configuration**: On first launch or if the configured database path doesn't exist, the app automatically:
1. Creates a database directory at `~/Library/Application Support/My_CRM/`
2. Initializes a new database at `~/Library/Application Support/My_CRM/my_crm.db`
3. Relocates databases out of cloud-synced folders (iCloud/Dropbox/etc.) and updates the settings file with the new path

You can change the database location at any time through the Settings view.

**Default Location**: `~/Library/Application Support/My_CRM/my_crm.db` (settings stored alongside in `User_Settings.json`)

**Important**: This application follows a database-centric architecture where all UI state, user interactions, and data modifications are immediately persisted to the database. The database serves as the single source of truth for all application data.

#### Database Schema
```sql
CREATE TABLE contacts (
    id TEXT PRIMARY KEY,
    phone TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    first_name TEXT,
    last_name TEXT,
    email TEXT,
    address TEXT,
    notes TEXT,
    creation_date DATETIME,
    business TEXT,
    contact_group TEXT,
    birthday DATETIME,
    apple_contact_id TEXT
);
```

## Usage

### Basic Navigation
- **W**: Toggle Page Navigation Bar
- **Contacts Bar**: Toggle with button in header
- **Mouse**: Click and drag to pan canvas
- **Trackpad**: Pinch to zoom, two-finger drag to pan

### Contact Management
1. **Search**: Type in the search bar for fuzzy matching
2. **Select**: 
   - **Click**: Single selection
   - **Cmd+Click**: Toggle selection (add/remove from selection)
   - **Shift+Click**: Range selection from last selected contact
   - **Arrow Keys**: Navigate and select contacts
   - **Shift+Arrow**: Extend selection range
   - **Cmd+Shift+Arrow**: Extend selection to top/bottom
3. **Drag**: Drag contacts from the list to the canvas
4. **Organize**: Drop contacts into groups or create new ones

### Visual Organization
1. **Relationship Maps**: Drag contacts to create relationship circles
2. **Groups**: Create card stacks for different purposes with groups toolbar
3. **Groups Toolbar**: Manage groups and decks with drag & drop functionality and right-click context menus
4. **Groups**: Visual circles with member counts and metadata
5. **Zoom**: Use +/- buttons or trackpad gestures
6. **Group Management**: Right-click on groups in the toolbar to delete them with database cleanup

### Keyboard Shortcuts
- **W**: Toggle navigation bar
- **,**: Collapse all sibling folders
- **.**: Expand all sibling folders
- **Cmd+Z**: Undo
- **Shift+Cmd+Z**: Redo
- **Escape**: Clear selection
- **Cmd+A**: Select all contacts
- **Cmd+F**: Focus search

#### Contacts Bar Navigation
- **↑/↓**: Navigate through contacts
- **Shift+↑/↓**: Extend selection range
- **Cmd+↑/↓**: Jump to first/last contact
- **Cmd+Shift+↑/↓**: Extend selection to top/bottom
- **Escape**: Clear all selections
- **Cmd+A**: Select all visible contacts

## Development

### Adding New Features

1. **Database Schema**: Update database schema first in `database_requirements.json`
2. **Data Models**: Add to `Core/Models/` with database persistence
3. **Services**: Implement in `Core/Services/` with database-first patterns
4. **UI Components**: Create in `UI/Components/` as stateless database views
5. **Pages**: Add to `UI/Pages/` with database synchronization
6. **Tests**: Write unit tests in `Tests/` including database integration tests

**Database-First Development**: Always design database schema first, then implement services, and finally create UI components that reflect database state.

For detailed information about the database-centric architecture, see [DATABASE_CENTRIC_ARCHITECTURE.md](Documentation/Architecture/DATABASE_CENTRIC_ARCHITECTURE.md).

### Testing

Run the test suite:
```bash
# Run all tests
xcodebuild test -scheme "My CRM" -destination 'platform=macOS'

# Run specific test class
xcodebuild test -scheme "My CRM" -only-testing:MyCRMTests/FuzzyMatcherTests
```

### Code Style

- Use SwiftUI for all UI components
- Follow Swift naming conventions
- Add documentation comments for public APIs
- Write unit tests for all business logic and database operations
- Use `@MainActor` for UI-related code
- Prefer `Observable` over `ObservableObject` where possible
- **Database-First**: All UI components must reflect database state
- **Immediate Persistence**: All user interactions must be immediately persisted to database
- **Stateless UI**: UI components should not maintain independent state
- **Error Handling**: Implement proper database error handling and recovery

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
1. Check the existing issues
2. Create a new issue with detailed information
3. Include system information and steps to reproduce

## Roadmap

### Phase 1 (Current)
- ✅ Basic UI shell and navigation
- ✅ Contact management and search
- ✅ Drag-and-drop functionality
- ✅ Visual organization tools

### Phase 2 (Planned)
- 🔄 Real-time collaboration
- 🔄 Advanced analytics and insights
- 🔄 Integration with external services
- 🔄 Mobile companion app

### Phase 3 (Future)
- 🔄 AI-powered relationship insights
- 🔄 Automated follow-up reminders
- 🔄 Advanced visualization options
- 🔄 Enterprise features

---

**My CRM** - Organize your relationships, one contact at a time.
