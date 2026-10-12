# Navigation Structure Documentation

## Overview

This document describes the navigation structure and terminology used in My CRM for AI development and future reference.

## Navigation Bar Structure

The main navigation is defined in `State/AppState.swift` in the `Page` enum. The navigation bar displays these main sections:

> **Developer Mode Gating**  
> Pages marked as placeholders (see `Page.isPlaceholder`) are hidden by default. Enable `Developer Mode` in settings to surface unfinished pages for internal testing. The `Settings` page is always visible.

### Main Pages
- **Relationship Maps** (formerly "People Maps") - Interactive canvas for visual relationship mapping
- **Groups** (formerly "Deck Builder") - Create and manage contact groups with collapsible groups toolbar

### Tools Section
- **Smart Lists** - Intelligent contact filtering and organization
- **Timeline View** - Chronological view of contact interactions
- **Flashcard Trainer** - Memory training for contact information
- **Engagement Dashboard** - Analytics and engagement metrics

### Management Section
- **Canvas Management** - Manage canvas layouts and configurations
- **Automations Manager** - Automated workflows and triggers
- **Tag Manager** - Contact tagging and categorization
- **Groups & Circles** - Advanced group management
- **Import/Sync** - Data import and synchronization tools
- **Settings** - Application configuration and preferences

## Key Terminology Changes

### Updated Navigation Labels (2025-01-09)
- **"People Maps" → "Relationship Maps"**: Better reflects the purpose of visual relationship mapping
- **"Deck Builder" → "Groups"**: Simplified terminology focusing on group management functionality

### Consistent Terminology
- **ContactGroup**: Data structure for groups of contacts in the database
- **GroupCircle**: UI element representing a contact group with visual circle/ellipsis on canvas
- **Groups Toolbar**: Collapsible sidebar for managing groups and decks with drag & drop
- **Relationship Maps**: The main canvas view for visual contact organization

## Navigation Implementation

### Page Enum Structure
```swift
enum Page: String, CaseIterable {
    case peopleMaps = "Relationship Maps"
    case deckBuilder = "Groups"
    case canvasManagement = "Canvas Management"
    case smartLists = "Smart Lists"
    case timeline = "Timeline View"
    case flashcardTrainer = "Flashcard Trainer"
    case engagementDashboard = "Engagement Dashboard"
    case automationsManager = "Automations Manager"
    case tagManager = "Tag Manager"
    case groupsAndCircles = "Groups & Circles"
    case importSync = "Import/Sync"
    case settings = "Settings"
}
```

### Navigation Bar Components
- **PageNavBarView**: Main navigation component with collapsible sections
- **NavigationSection**: Groups navigation items by category (Main, Tools, Management)
- **NavigationItem**: Individual navigation items with icons and expansion state

## UI Component Mapping

### Main Views
- **Relationship Maps**: `SimplifiedCanvasView` - Interactive canvas for visual organization
- **Groups**: `GroupsMapViewModel` - Group management with visual elements
- **Canvas Management**: `CanvasManagementView` - Canvas configuration and settings

### Supporting Components
- **Groups Toolbar**: `GroupsToolbarView` - Collapsible groups management
- **Contact Nodes**: `ContactNodeView` - Individual contact representation
- **Group Circles**: `GroupCircleView` - Visual group representation

## Development Guidelines

### When Adding New Navigation Items
1. Add new case to `Page` enum in `State/AppState.swift`
2. Add corresponding icon in the `icon` computed property
3. Include in appropriate section in `PageNavBarView.swift`
4. Create corresponding view in `UI/Pages/` directory
5. Update this documentation

### When Modifying Navigation Labels
1. Update the raw value in `Page` enum
2. Update all references in documentation
3. Update UI component names if they reference the old terminology
4. Update this documentation with change log

### Naming Conventions
- Use descriptive, user-friendly names for navigation labels
- Keep terminology consistent across the application
- Avoid technical jargon in user-facing navigation
- Use title case for navigation labels

## Change Log

### 2025-11-09
- Updated navigation bar styling to use neutral highlights in dark mode with 10% gray selection bars
- Navigation header and tab backgrounds now inherit the window background in dark mode for higher contrast
- Documented selection highlight change for accessibility review

### 2025-01-09
- Changed "People Maps" to "Relationship Maps" for better clarity
- Changed "Deck Builder" to "Groups" for simplified terminology
- Updated all related documentation and references
- Implemented persistent settings system with JSON file storage in App Support directory
- Added auto-save functionality for all settings changes
- Added debug section with button to open settings file in text editor

## Future Considerations

### Planned Navigation Updates
- Consider adding breadcrumb navigation for deep navigation
- Implement search within navigation for large numbers of pages
- Add keyboard shortcuts for quick navigation
- Consider collapsible sub-sections for related functionality

### Accessibility
- Ensure all navigation items have proper accessibility labels
- Support keyboard navigation for all navigation elements
- Provide screen reader friendly navigation structure
- Consider high contrast mode compatibility

---

**Note**: This documentation should be updated whenever navigation structure changes to ensure AI assistants and future developers understand the current state of the application.
