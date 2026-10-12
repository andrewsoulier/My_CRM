# Deprecated Code Documentation

This file tracks all code that has been moved, refactored, or removed during the My CRM reorganization process.

## Migration Status Legend
- 🔄 **In Progress**: Currently being migrated
- ✅ **Completed**: Successfully migrated and tested
- ❌ **Failed**: Migration failed, needs attention
- 🗑️ **Removed**: Code was removed (not migrated)
- 📝 **Documented**: Code documented but not yet migrated

## File Migration Log

### Application Layer

#### App/MyCRMApp.swift
**Status**: 🔄 In Progress
**Migration Date**: TBD
**New Location**: Application/App/AppModel.swift

**Moved Components**:
- `AppModel` class (lines 1-417)
  - **Properties**: isBackendConnected, dbURL, isRunning, lastUpdate, isMainWindowOpen, process, outputPipe, errorPipe, timer, updateTimer, dataCheckTimer
  - **Methods**: startBackend(), stopBackend(), loadLastRunTime(), saveLastRunTime(), startUpdateTimer(), stopUpdateTimer(), updateLastMessageTime(), runStartScript()
  - **Reason**: Moving to dedicated Application layer for better separation of concerns

#### App/PreferencesView.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Features/Settings/Views/PreferencesView.swift

**Moved Components**:
- `PreferencesView` struct (lines 1-328)
  - **Properties**: databasePath, databaseName, userName, userPhone, userEmail, theme, notifications, autoSync, runAtLogin, showingFilePicker, showingContactPicker, showingSaveAlert, saveMessage
  - **Methods**: selectDatabaseFile(), selectContact(), savePreferences()
  - **Reason**: Moving to Settings feature module for better organization

#### App/CRMApp.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Application/App/CRMApp.swift

**Moved Components**:
- `CRMApp` struct (lines 1-41)
  - **Properties**: appModel
  - **Reason**: Moving to Application layer for better organization

### Core Layer

#### Core/Models/Contact.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Data/Models/Domain/Contact.swift

**Moved Components**:
- `Contact` struct (lines 1-78)
  - **Properties**: id, phone, name, firstName, lastName, email, address, notes, creationDate, business, contactGroup, birthday, appleContactID
  - **Computed Properties**: displayName, initials
  - **Methods**: init(from sqliteRow:), init(phone:name:...), hash(into:), ==
  - **Reason**: Moving to Data layer for better separation of domain models

#### Core/Models/Group.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Data/Models/Domain/Group.swift

**Moved Components**:
- `ContactGroup` struct (lines 1-122)
  - **Properties**: id, name, color, createdAt, parentID, memberPhones, linkedGroupIDs, metadata
  - **Computed Properties**: members, memberCount, isRoot, hasChildren
  - **Methods**: init(id:name:color:parentID:)
- `GroupMetadata` struct (lines 44-72)
  - **Properties**: inviteCount, interconnectivityScore
  - **Methods**: init(), init(from decoder:), encode(to encoder:)
- `Color` extension (lines 74-122)
  - **Methods**: init(from decoder:), encode(to encoder:), init(hex:), toHex()
  - **Reason**: Moving to Data layer for better separation of domain models

#### Core/Models/Deck.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Data/Models/Domain/Deck.swift

**Moved Components**:
- `Deck` struct (lines 1-57)
  - **Properties**: id, name, memberPhones, createdAt, updatedAt, description
  - **Computed Properties**: members, memberCount, isEmpty
  - **Methods**: init(id:name:description:), addMember(), removeMember(), reorderMembers(), containsMember()
  - **Reason**: Moving to Data layer for better separation of domain models

#### Core/Models/CanvasModels.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Data/Models/Domain/CanvasModels.swift

**Moved Components**:
- `ContactNode` struct (lines 1-236)
- `GroupCircle` struct
- `CanvasState` struct
- `DragContext` struct
- `CanvasTransform` struct
- `DragType` enum
- `GroupOperation` enum
- **Reason**: Moving to Data layer for better separation of domain models

#### Core/Protocols/DataProvider.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Data/Repositories/Protocols/DataProvider.swift

**Moved Components**:
- `DataProvider` protocol
- `ImageProvider` protocol
- `Persistence` protocol
- `ContactFilter` struct
- `ContactSortOption` enum
- `DataProviderError` enum
- **Reason**: Moving to Data layer for better separation of repository interfaces

#### Core/Services/DragDropManager.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Services/Core/DragDropManager.swift

**Moved Components**:
- `DragDropManager` class (lines 1-313)
  - **Properties**: shared
  - **Methods**: makeItems(), transferable(), decodeProviders(), performDrop(), handleGroupDrop(), handleDeckDrop(), addContactsToGroup(), moveContactsBetweenGroups(), addContactsToDeck(), reorderContactsInDeck(), moveContactsBetweenDecks()
  - **Reason**: Moving to Services layer for better organization of business logic

#### Core/Services/CanvasRepository.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Services/Core/CanvasRepository.swift

**Moved Components**:
- `CanvasRepository` protocol
- `InMemoryCanvasRepository` class
- `FileCanvasRepository` class
- **Reason**: Moving to Services layer for better organization

#### Core/Services/FuzzyMatcher.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Services/Core/FuzzyMatcher.swift

**Moved Components**:
- `FuzzyMatcher` class
- **Methods**: match(), calculateScore()
- **Reason**: Moving to Services layer for better organization

#### Core/Services/HotkeyManager.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Services/Core/HotkeyManager.swift

**Moved Components**:
- `HotkeyManager` class
- **Methods**: register(), unregister(), handleKeyPress()
- **Reason**: Moving to Services layer for better organization

#### Core/Services/SelectionManager.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Services/Core/SelectionManager.swift

**Moved Components**:
- `SelectionManager` class
- **Properties**: selectedItems
- **Methods**: select(), deselect(), clear(), toggle()
- **Reason**: Moving to Services layer for better organization

#### Core/DragDrop/ContactTransferable.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Services/Core/DragDrop/ContactTransferable.swift

**Moved Components**:
- `ContactTransferable` struct
- `ContactDragItem` struct
- `DragOrigin` enum
- **Methods**: init(), encode(), decode()
- **Reason**: Moving to Services layer for better organization

#### Core/DragDrop/DragTypes.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Services/Core/DragDrop/DragTypes.swift

**Moved Components**:
- `DragType` enum
- `DropTarget` enum
- **Reason**: Moving to Services layer for better organization

#### Core/DragDrop/ProviderBridge.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Services/Core/DragDrop/ProviderBridge.swift

**Moved Components**:
- `ProviderBridge` struct
- **Methods**: encode(), decode()
- **Reason**: Moving to Services layer for better organization

#### Core/Mock/MockDataProvider.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Data/Repositories/Implementations/MockContactRepository.swift

**Moved Components**:
- `MockDataProvider` class (lines 1-313)
  - **Properties**: contacts, groups, decks, database, isConnectedToSQLite
  - **Methods**: connectToDatabase(), isConnected(), closeConnection(), loadContactsFromSQLite(), loadMockData(), generateMockContacts(), generateMockGroups(), generateMockDecks(), fetchContacts(), countContacts(), fetchContact(), getContact(), updateContact(), deleteContact(), fetchGroups(), createGroup(), updateGroup(), deleteGroup(), add(phones:to:), move(phones:from:to:), remove(phones:from:), getGroupMembers(), updateGroupMembers(), fetchDecks(), createDeck(), updateDeck(), deleteDeck(), getDeckMembers(), updateDeckMembers()
  - **Reason**: Moving to Data layer and renaming to MockContactRepository for better clarity

### UI Layer

#### UI/Components/ContactNodeView.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Presentation/Views/Common/ContactNodeView.swift

**Moved Components**:
- `ContactNodeView` struct
- **Properties**: contact, isSelected, position, size
- **Methods**: body
- **Reason**: Moving to Presentation layer for better organization

#### UI/Components/DragPreview.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Presentation/Views/Common/DragPreview.swift

**Moved Components**:
- `DragPreview` struct
- **Properties**: phones, origin
- **Methods**: body
- **Reason**: Moving to Presentation layer for better organization

#### UI/Components/GroupCircleView.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Presentation/Views/Common/GroupCircleView.swift

**Moved Components**:
- `GroupCircleView` struct
- **Properties**: group, isSelected, center, radius
- **Methods**: body
- **Reason**: Moving to Presentation layer for better organization

#### UI/Pages/PeopleMaps/SandboxView.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Features/VisualCanvas/Views/CanvasView.swift

**Moved Components**:
- `SandboxView` struct (lines 1-12)
- **Methods**: body
- **Reason**: Moving to VisualCanvas feature module

#### UI/Pages/PeopleMaps/GroupsMapCanvas.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Features/VisualCanvas/Views/CanvasView.swift

**Moved Components**:
- `GroupsMapCanvas` struct
- **Properties**: nodes, groups, state
- **Methods**: body, handleGesture, updateState
- **Reason**: Moving to VisualCanvas feature module

#### UI/Pages/PeopleMaps/GroupsMapViewModel.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Features/VisualCanvas/ViewModels/CanvasViewModel.swift

**Moved Components**:
- `GroupsMapViewModel` class
- **Properties**: nodes, groups, state
- **Methods**: loadData, saveData, updateNode, updateGroup
- **Reason**: Moving to VisualCanvas feature module

#### UI/Pages/PeopleMaps/CanvasGestures.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Features/VisualCanvas/Gestures/CanvasGestures.swift

**Moved Components**:
- `CanvasGestures` struct
- **Methods**: handleTap, handleDrag, handlePinch
- **Reason**: Moving to VisualCanvas feature module

#### UI/Pages/PeopleMaps/CanvasOverlay.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Features/VisualCanvas/Views/CanvasOverlay.swift

**Moved Components**:
- `CanvasOverlay` struct
- **Properties**: zoom, pan, gridEnabled
- **Methods**: body
- **Reason**: Moving to VisualCanvas feature module

#### UI/Pages/DeckBuilder/DeckBuilderView.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Features/DeckBuilder/Views/DeckBuilderView.swift

**Moved Components**:
- `DeckBuilderView` struct (lines 1-313)
- `DeckStackView` struct
- `ContactCardView` struct
- **Properties**: decks, deckPositions, isPanning, appState, dataProvider, dragDropManager, selectionManager
- **Methods**: body, loadDecks, setupInitialPositions, handleCanvasDrag, createNewDeck, handleDeckTap, handleContactTap
- **Reason**: Moving to DeckBuilder feature module

#### UI/Shell/ContactsBarView.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Presentation/Views/Layout/ContactsBarView.swift

**Moved Components**:
- `ContactsBarView` struct
- **Properties**: contacts, searchTerm, selectedContacts
- **Methods**: body, filterContacts, selectContact
- **Reason**: Moving to Presentation layer for better organization

#### UI/Shell/ContentView.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Presentation/Views/Layout/ContentView.swift

**Moved Components**:
- `ContentView` struct
- **Properties**: appModel
- **Methods**: body
- **Reason**: Moving to Presentation layer for better organization

#### UI/Shell/MainCRMView.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Presentation/Views/Layout/MainCRMView.swift

**Moved Components**:
- `MainCRMView` struct
- **Properties**: appState, dataProvider
- **Methods**: body
- **Reason**: Moving to Presentation layer for better organization

#### UI/Shell/PageNavBarView.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Presentation/Views/Layout/PageNavBarView.swift

**Moved Components**:
- `PageNavBarView` struct
- **Properties**: selectedPage, pages
- **Methods**: body, selectPage
- **Reason**: Moving to Presentation layer for better organization

#### UI/Shell/WorkspaceView.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Presentation/Views/Layout/WorkspaceView.swift

**Moved Components**:
- `WorkspaceView` struct
- **Properties**: appState, dataProvider
- **Methods**: body, handleNavigation
- **Reason**: Moving to Presentation layer for better organization

#### UI/Shared/AutoscrollController.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Presentation/Views/Common/AutoscrollController.swift

**Moved Components**:
- `AutoscrollController` class
- **Properties**: scrollView, timer
- **Methods**: startAutoscroll, stopAutoscroll, updateScroll
- **Reason**: Moving to Presentation layer for better organization

#### UI/Modals/SettingsView.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Features/Settings/Views/SettingsView.swift

**Moved Components**:
- `SettingsView` struct
- **Properties**: isPresented, settings
- **Methods**: body, saveSettings
- **Reason**: Moving to Settings feature module

### State Layer

#### State/AppState.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Architecture/Navigation/NavigationState.swift

**Moved Components**:
- `AppState` class (lines 1-173)
- `Page` enum
- **Properties**: selectedPage, isPageNavBarVisible, isContactsBarVisible, searchTerm, sortOption, selectedContacts, selectedGroup, selectedDeck, canvasZoom, canvasOffset, isGridSnappingEnabled, expandedFolders, showingSettings, showingGroupEditor, showingDeckEditor, lastError, showingError, userDefaults
- **Methods**: selectPage, togglePageNavBar, toggleContactsBar, collapseAllSiblings, expandAllSiblings, selectContact, deselectContact, selectContacts, clearSelection, toggleContactSelection, setZoom, resetZoom, toggleGridSnapping, showError, clearError, savePersistedState, loadPersistedState
- **Reason**: Moving to Architecture layer for better separation of navigation state

### Features Layer

#### Features/ContentView.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Features/ContactManagement/Views/ContactListView.swift

**Moved Components**:
- `ContentView` struct
- **Properties**: appModel
- **Methods**: body
- **Reason**: Moving to ContactManagement feature module

### Settings Layer

#### Settings/AppSettingsView.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Features/Settings/Views/AppSettingsView.swift

**Moved Components**:
- `AppSettingsView` struct (lines 1-40)
- **Properties**: appModel
- **Methods**: body, pickDB
- **Reason**: Moving to Settings feature module

### Tests Layer

#### Tests/DragDropTests.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Testing/UnitTests/Services/DragDropTests.swift

**Moved Components**:
- `DragDropTests` class
- **Methods**: testDragCreation, testDropHandling
- **Reason**: Moving to Testing layer for better organization

#### Tests/FuzzyMatcherTests.swift
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Testing/UnitTests/Services/FuzzyMatcherTests.swift

**Moved Components**:
- `FuzzyMatcherTests` class
- **Methods**: testMatching, testScoring
- **Reason**: Moving to Testing layer for better organization

### Backend Layer

#### App/Feature Groups/iMessage Server Scraper/Resources/import_contacts.py
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Backend/Python/services/contact_sync.py

**Moved Components**:
- `fetch_mac_contacts()` function
- `ensure_profile_photo_column()` function
- `get_contact_photo_data()` function
- `update_crm_database()` function
- **Reason**: Moving to Backend layer for better organization

#### App/Feature Groups/iMessage Server Scraper/Resources/import_imessages.py
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Backend/Python/services/imessage_service.py

**Moved Components**:
- `apple_epoch_to_dt()` function
- `_normalize_message()` function
- `main()` function
- **Reason**: Moving to Backend layer for better organization

#### App/Feature Groups/iMessage Server Scraper/Resources/start.py
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Backend/Python/main.py

**Moved Components**:
- `main()` function
- `setup_logging()` function
- `ensure_venv()` function
- `pip_install_if_needed()` function
- `reexec_inside_venv()` function
- `prompt_for_full_disk_access()` function
- `preflight_messages_access()` function
- `run_ordered_scripts()` function
- **Reason**: Moving to Backend layer for better organization

#### App/Feature Groups/iMessage Server Scraper/Resources/Modules/imessage_tools.py
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Backend/Python/services/imessage_tools.py

**Moved Components**:
- `get_chat_mapping()` function
- `read_messages()` function
- `send_message()` function
- **Reason**: Moving to Backend layer for better organization

#### App/Feature Groups/iMessage Server Scraper/MacOS/Launch_Server.sh
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Backend/Scripts/start_backend.sh

**Moved Components**:
- Shell script for launching backend
- **Reason**: Moving to Backend layer for better organization

#### App/Feature Groups/iMessage Server Scraper/MacOS/install_cron.sh
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Backend/Scripts/install.sh

**Moved Components**:
- Shell script for installing cron jobs
- **Reason**: Moving to Backend layer for better organization

#### App/Feature Groups/iMessage Server Scraper/MacOS/uninstall_cron.sh
**Status**: 📝 Documented
**Migration Date**: TBD
**New Location**: Backend/Scripts/uninstall.sh

**Moved Components**:
- Shell script for uninstalling cron jobs
- **Reason**: Moving to Backend layer for better organization

## Removed Code

### 2024-10-25: UI Data Loading Refactoring (✅ Completed)

**Purpose**: Fix UI not displaying database data by implementing proper observer pattern without infinite loops

#### Removed: Redundant Database Reload in ContactsViewModel
**File**: `Core/Services/ContactsViewModel.swift`
**Lines Removed**: 34-39 (else block)
```swift
} else {
    // If already connected, ensure contacts are loaded
    logger.info("🔌 ContactsViewModel: Database already connected, ensuring contacts are loaded...")
    print("🔍 DEBUG: ContactsViewModel.loadContacts() calling loadDataFromDatabase()")
    await dataProvider.loadDataFromDatabase()
}
```
**Reason**: This was causing unnecessary database reloads. The new observer pattern automatically syncs data when dataProvider.contacts changes, eliminating the need for manual reloads.

#### Removed: Redundant Database Reload in GroupsViewModel
**File**: `Core/Services/GroupsViewModel.swift`
**Lines Removed**: 34-39 (else block)
```swift
} else {
    // If already connected, ensure groups are loaded
    logger.info("🔌 GroupsViewModel: Database already connected, ensuring groups are loaded...")
    print("🔍 DEBUG: GroupsViewModel.loadGroups() calling loadDataFromDatabase()")
    await dataProvider.loadDataFromDatabase()
}
```
**Reason**: Same as ContactsViewModel - replaced by observer pattern for automatic synchronization.

#### Removed: Commented-Out Observer Code in GroupsToolbarView
**File**: `UI/Components/GroupsToolbarView.swift`
**Lines Removed**: 248-264 (commented block)
```swift
// DISABLED: This was causing infinite loops by continuously updating view models
// .onReceive(dataProvider.$groups) { newGroups in
//     // Only refresh if the view model is already loaded and we're not already refreshing
//     logger.info("🔄 GroupsToolbarView: Groups data changed in dataProvider - count: \(newGroups.count)")
//     if globalCanvasService.groupsViewModel.isInitialLoadComplete && !isRefreshing {
//         logger.info("🔄 GroupsToolbarView: View model loaded and not refreshing - updating view model")
//         // Update the view model directly without triggering another refresh cycle
//         Task {
//             await MainActor.run {
//                 globalCanvasService.groupsViewModel.allGroups = newGroups
//                 globalCanvasService.groupsViewModel.displayedGroups = newGroups
//             }
//         }
//     } else {
//         logger.info("🔄 GroupsToolbarView: Skipping update - isInitialLoadComplete: \(globalCanvasService.groupsViewModel.isInitialLoadComplete), isRefreshing: \(isRefreshing)")
//     }
// }
```
**Reason**: This disabled code was an earlier attempt to solve the synchronization problem but caused infinite loops. Replaced by proper observer setup in ViewModels with loop prevention mechanisms.

#### Added: New Synchronization Methods
**Files Modified**: 
- `Core/Services/ContactsViewModel.swift`
- `Core/Services/GroupsViewModel.swift`

**New Methods**:
- `syncFromProvider()` - Async method that only copies data, never triggers database operations (prevents loops)
- `setupDataProviderObserver()` - Sets up Combine observer to automatically sync when dataProvider publishes changes

**Loop Prevention Mechanisms**:
1. Separate methods: `syncFromProvider()` never calls database operations
2. Guard clauses: `isLoading` flag prevents concurrent operations
3. Observer logic: Only triggers on non-empty data and when not loading
4. One-way flow: dataProvider → ViewModel (never ViewModel → dataProvider in observer)

**Modified**: `UI/Shell/MainCRMView.swift`
- Added observer setup after database connection
- Added initial sync trigger to populate ViewModels immediately after database load

### Files to be Removed
- `App/Info.plist` - Moving to Application/App/Info.plist
- `build_app.sh` - Moving to Build/Scripts/build.sh
- `Package.swift` - Moving to Project/Package.swift
- `README.md` - Moving to Project/README.md

### Code to be Removed
- Duplicate ContentView files
- Unused imports
- Dead code paths
- Obsolete comments

## Migration Notes

### Dependencies to Update
- Import statements need to be updated throughout the codebase
- File references in build scripts need to be updated
- Xcode project file references need to be updated
- Python script paths need to be updated

### Breaking Changes
- File paths will change
- Some class names may be updated for clarity
- Some method signatures may be updated for consistency

### Testing Requirements
- All moved code must be tested after migration
- Integration tests must verify functionality still works
- UI tests must verify user experience is maintained
- Performance tests must verify no degradation

## Completion Checklist

- [ ] All files moved to new locations
- [ ] All import statements updated
- [ ] All file references updated
- [ ] All tests passing
- [ ] All functionality verified
- [ ] Documentation updated
- [ ] Build process working
- [ ] Deployment process working
- [ ] Performance verified
- [ ] Security verified

---

**Last Updated**: 2024-12-19
**Migration Status**: 🔄 In Progress
**Next Review**: TBD
