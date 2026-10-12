# Groups Toolbar Implementation

## Overview

The Groups Toolbar is a collapsible sidebar component for the Deck Builder page that displays all groups (including decks) from the database. It follows the same design patterns and style as the Contacts Toolbar, providing a consistent user experience.

## Features

### Core Functionality
- **Collapsible Design**: Can be collapsed/expanded with smooth animations
- **Group Display**: Shows all groups from the database with member counts and metadata
- **Search Functionality**: Search groups by name or member names
- **Group Creation**: Create new groups or decks directly from the toolbar
- **Drag & Drop**: Accept contacts dragged from the contacts toolbar to add them to groups
- **Deck Selection**: Click on decks to select them for editing in the main area

### Visual Design
- **Consistent Styling**: Matches the Contacts Toolbar design language
- **Group Icons**: Different icons for regular groups vs decks
- **Member Previews**: Shows profile images of first few members
- **Selection States**: Visual feedback for selected groups
- **Color Coding**: Groups display with their assigned colors
- **Contact Cards**: Uniform height cards with profile photos and consistent layout

## Implementation Details

### File Structure
```
UI/Components/
├── GroupsToolbarView.swift          # Main toolbar component
└── (existing components)

UI/Pages/DeckBuilder/
└── DeckBuilderView.swift            # Updated to use GroupsToolbarView

State/
└── AppState.swift                   # Added isGroupsBarVisible state
```

### Key Components

#### GroupsToolbarView
- **Location**: `UI/Components/GroupsToolbarView.swift`
- **Purpose**: Main collapsible toolbar for displaying and managing groups
- **Features**:
  - Search and filter groups
  - Create new groups/decks
  - Display group information with member previews
  - Handle drag & drop for adding contacts
  - Communicate deck selection to parent view

#### GroupRowView
- **Location**: `UI/Components/GroupsToolbarView.swift` (nested struct)
- **Purpose**: Individual group display row
- **Features**:
  - Shows group icon, name, and member count
  - Displays member previews (profile images)
  - Handles selection and drag & drop
  - Context menu for group actions

#### DeckBuilderView Integration
- **Location**: `UI/Pages/DeckBuilder/DeckBuilderView.swift`
- **Changes**:
  - Replaced old sidebar with GroupsToolbarView
  - Added collapse/expand toggle button
  - Integrated deck selection callback
  - Added drag & drop support for deck content area
  - Updated CardView with profile photos and uniform height

### State Management

#### AppState Updates
```swift
@Published var isGroupsBarVisible = true

func toggleGroupsBar() {
    isGroupsBarVisible.toggle()
    savePersistedState()
}
```

#### Persistence
- Groups toolbar visibility state is persisted in UserDefaults
- State is restored on app launch
- Follows same pattern as contacts toolbar

### Drag & Drop Implementation

#### Contact to Group
- Contacts can be dragged from ContactsBarView to GroupsToolbarView
- Drop destination checks if contact is already in group
- Uses Contact's Transferable conformance
- Updates database via SQLiteDataProvider.add()

#### Contact to Deck Content
- Contacts can be dragged directly to deck content area
- Same duplicate checking and database update logic
- Visual feedback during drag operations

### Database Integration

#### Group Loading
- Groups are loaded from SQLite database via SQLiteDataProvider
- Includes member phones, metadata, and canvas associations
- Real-time updates when groups are modified

#### Member Management
- Adding contacts: `dataProvider.add(phones: [phone], to: groupID)`
- Removing contacts: `dataProvider.remove(phones: [phone], from: groupID)`
- Automatic UI updates when database changes

## Usage

### Basic Usage
```swift
GroupsToolbarView { selectedDeck in
    // Handle deck selection
    self.selectedDeck = selectedDeck
}
```

### With Custom Callback
```swift
GroupsToolbarView { deck in
    if let deck = deck {
        // Navigate to deck editing
        showDeckEditor(deck)
    }
}
```

## User Interactions

### Toolbar Controls
1. **Collapse/Expand**: Click chevron button in header
2. **Search**: Type in search field to filter groups
3. **Create Group**: Click "Create Group" button
4. **Select Deck**: Click on any deck to select it

### Drag & Drop Operations
1. **Add Contact to Group**: Drag contact from contacts toolbar to group row
2. **Add Contact to Deck**: Drag contact to deck content area
3. **Visual Feedback**: Drop zones highlight during drag operations

### Context Menu Actions
- **Delete Group**: Right-click on any group to access the context menu with delete option
- Add Members
- Edit Group
- Start Deck (for deck groups)

### Right-Click Context Menu
The groups toolbar now supports right-click context menus for each group row:
- **Delete Group**: Removes the group from the database and performs canvas cleanup
- **Confirmation Dialog**: Shows a confirmation dialog before deletion to prevent accidental deletions
- **Database Cleanup**: Automatically removes group references from all canvases
- **Automatic UI Updates**: Immediately refreshes the groups list after successful deletion using callback mechanism and refresh trigger

### Group Sorting Options
The groups toolbar now includes a sorting dropdown with the following options:
- **Recently Updated** (default): Sort by creation date, most recent first
- **Date Created**: Sort by creation date, earliest first
- **Name**: Sort alphabetically by group name
- **Size**: Sort by member count, largest first

The sorting is applied immediately when the user selects a different option from the dropdown.

## Styling and Theming

### Color Scheme
- Background: `Color(NSColor.controlBackgroundColor)`
- Borders: `Color(.separatorColor)`
- Selection: `Color.accentColor.opacity(0.15)`
- Text: Primary and secondary text colors

### Layout
- Width: 300px when expanded
- Collapsed width: 40px with toggle button
- Smooth animations for collapse/expand
- Consistent padding and spacing
- Contact cards: Fixed 80px height with profile photos

## Future Enhancements

### Planned Features
- Group hierarchy support (parent/child groups)
- Bulk operations (select multiple groups)
- Group templates and presets
- Advanced filtering options
- Group statistics and analytics

### Technical Improvements
- Virtual scrolling for large group lists
- Lazy loading of group members
- Real-time collaboration features
- Enhanced search with fuzzy matching

## Dependencies

### Required Environment Objects
- `AppState`: For toolbar visibility state
- `SQLiteDataProvider`: For database operations
- `SelectionManager`: For group selection
- `DragDropManager`: For drag & drop operations
- `GlobalCanvasService`: For canvas integration

### Required Models
- `ContactGroup`: Group data model
- `Contact`: Contact data model (for drag & drop)
- `GroupMetadata`: Group metadata structure

## Testing

### Manual Testing Checklist
- [ ] Toolbar collapses and expands smoothly
- [ ] Groups load from database correctly
- [ ] Search functionality works
- [ ] Group creation works
- [ ] Drag & drop adds contacts to groups
- [ ] Deck selection updates main area
- [ ] State persists across app restarts
- [ ] Visual feedback during interactions
- [ ] Right-click context menu appears on group rows
- [ ] Delete group option works with confirmation dialog
- [ ] Group deletion removes from database and canvases
- [ ] Groups list automatically refreshes immediately after deletion
- [ ] Sorting dropdown appears in groups toolbar
- [ ] All four sorting options work correctly (Recently Updated, Date Created, Name, Size)
- [ ] Default sorting is "Recently Updated"
- [ ] Sorting changes are applied immediately when selected

### Unit Testing
- Group filtering logic
- Drag & drop validation
- State management
- Database operations

## Troubleshooting

### Common Issues
1. **Groups not loading**: Check database connection and group table
2. **Drag & drop not working**: Verify Contact Transferable conformance
3. **State not persisting**: Check UserDefaults key consistency
4. **UI not updating**: Ensure proper @Published property usage

### Debug Information
- Use LogManager for operation logging
- Check console for database errors
- Verify environment object injection
- Monitor state changes in AppState
