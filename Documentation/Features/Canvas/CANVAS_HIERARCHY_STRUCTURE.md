# Canvas Hierarchy Structure

## Overview

The canvas system has been restructured to follow a clear parent-child relationship that simplifies the code and treats each canvas as a whole element. This new structure separates concerns and makes the code more maintainable.

## Layer Structure

```
Main Window
├── View
│   ├── Tools and Menus (rendered on top)
│   └── Canvas
│       ├── User Nodes (contacts)
│       ├── Circle Groups
│       │   └── Transform Handles (resize, rotate)
│       └── Background (grid, etc.)
```

## Component Hierarchy

### 1. SimplifiedCanvasView (Parent)
- **Purpose**: Main canvas container that manages the entire canvas state
- **Responsibilities**:
  - Coordinate transformations (zoom, pan)
  - Handle canvas-level gestures (pan, zoom, selection)
  - Manage keyboard and scroll wheel events
  - Render toolbar and menus on top
  - Coordinate between child components

### 2. CanvasContainer (Child)
- **Purpose**: Manages group circles and their transform controls
- **Responsibilities**:
  - Render group circles
  - Handle group-specific drag and drop
  - Manage transform controls (resize, rotate handles)
  - Coordinate group interactions

### 3. GroupCircleWithTransforms (Child of CanvasContainer)
- **Purpose**: Individual group circle with its transform controls
- **Responsibilities**:
  - Render the group circle
  - Show/hide transform controls based on selection state
  - Handle group-specific gestures

### 4. TransformControls (Child of GroupCircleWithTransforms)
- **Purpose**: Resize and rotate handles for selected groups
- **Responsibilities**:
  - Render resize handles (4 corners)
  - Render rotate handle (top center)
  - Handle transform gestures
  - Update group properties

## Key Benefits

### 1. Simplified Code Structure
- **Before**: Complex nested gesture handling in multiple components
- **After**: Clear separation of concerns with parent managing canvas-level operations and children handling element-specific operations

### 2. Better State Management
- **Before**: State scattered across multiple components
- **After**: Centralized state management in the parent canvas view

### 3. Improved Performance
- **Before**: Multiple gesture recognizers competing
- **After**: Coordinated gesture handling with clear hierarchy

### 4. Easier Maintenance
- **Before**: Changes required updates to multiple files
- **After**: Changes are isolated to specific components in the hierarchy

## Component Responsibilities

### Parent Components (Canvas Level)
- `SimplifiedCanvasView`: Main canvas container
- `CanvasBackground`: Grid and background rendering
- `CanvasContent`: Content layer management
- `CanvasToolbar`: Tools and menus

### Child Components (Element Level)
- `CanvasContainer`: Group management
- `GroupCircleWithTransforms`: Individual group with transforms
- `TransformControls`: Resize and rotate handles
- `ContactsLayer`: Contact node management

## Data Flow

1. **User Interaction** → `SimplifiedCanvasView`
2. **Canvas-level gestures** → Handled by parent
3. **Element-specific gestures** → Delegated to appropriate child
4. **State updates** → Propagated up to parent
5. **UI updates** → Propagated down to children

## File Structure

```
UI/Pages/PeopleMaps/
├── SimplifiedCanvasView.swift     # Main canvas container
├── CanvasContainer.swift          # Group management
└── GroupsMapViewModel.swift       # View model

Core/Models/
├── CanvasModels.swift             # Core data models
└── CanvasTypes.swift              # Supporting types

UI/Components/
└── GroupCircleView.swift          # Simplified group circle
```

## Migration Notes

### What Changed
1. **GroupCircleView**: Removed drag/drop functionality, simplified to pure display component
2. **Canvas Structure**: Moved from flat structure to hierarchical parent-child relationship
3. **Gesture Handling**: Centralized in parent, delegated to children as needed
4. **State Management**: Simplified with clear data flow

### What Stayed the Same
1. **Data Models**: ContactNode, GroupCircle, CanvasState remain unchanged
2. **View Model**: GroupsMapViewModel maintains same interface
3. **Core Functionality**: All features preserved, just reorganized

## Usage Example

```swift
// The new structure is used automatically when navigating to People Maps
// No changes needed in existing navigation code

struct WorkspaceView: View {
    var body: some View {
        switch appState.selectedPage {
        case .peopleMaps:
            SimplifiedCanvasView() // New hierarchical canvas
        // ... other cases
        }
    }
}
```

## Future Enhancements

This structure makes it easier to add:
1. **New element types**: Add new child components following the same pattern
2. **Advanced transforms**: Extend TransformControls with more handle types
3. **Custom tools**: Add new toolbar items without affecting canvas logic
4. **Performance optimizations**: Implement view recycling and lazy loading
