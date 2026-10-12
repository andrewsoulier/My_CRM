# Canvas Controls Implementation

## Overview

This document summarizes the implementation of the canvas control menu with the specified controls and database integration for canvas persistence.

## ✅ **Completed Features**

### **1. Canvas Control Menu Structure**
The canvas toolbar now includes the following controls in order from left to right:

- **Canvas Selection Dropdown**: Shows available canvases with option to add new ones
- **Zoom Controls**: Plus/minus buttons with percentage display
- **Mode Toggle Icons**:
  - Select Mode (cursor arrow icon) - turns blue when active
  - Hand Mode (hand draw icon) - turns blue when active  
  - Add Group Mode (circle grid icon) - turns blue when active
  - Show Grid (grid icon) - turns blue when active

### **2. Hotkey Features Fixed (January 2025, Updated November 9, 2025)**
- **Scroll**: Pan canvas up/down vertically (fixed October 14, 2025 - scroll wheel now uses local event monitor)
- **Shift+Scroll**: Pan canvas left/right horizontally, now using horizontal trackpad deltas when available (fixed October 14, 2025; updated November 9, 2025)
- **Two-Finger Horizontal Scroll**: Direct horizontal trackpad gestures pan left/right without modifiers (added November 9, 2025)
- **Option+Scroll**: Zoom in/out while preserving the visible center point with automatic pan correction (fixed October 14, 2025; updated November 9, 2025)
- **Pinch to Zoom**: Works in all modes - selection, hand, and group add (fixed October 14, 2025 - removed hand mode restriction)
- **Click on Node**: Drop selection and select the clicked node
- **Shift+Click**: Toggle element in/out of selection (fixed October 2025 - now works for both contacts and groups)
- **Command+Click**: Toggle element in/out of selection (fixed October 2025 - now works for both contacts and groups)
- **Option+Click**: Add element to selection
- **Default Mode**: Canvas always opens in selection mode (V key mode)
- **Terminal Bell**: Fixed spacebar temporary hand mode making system sounds
- **Search Bar Focus**: Automatically released when canvas page is selected (fixed October 14, 2025)

### **3. Selection Behavior Improvements (October 2024-2025)**
- **Blank Space Selection Clearing**: Clicking on blank canvas areas clears all selections (selection mode only, but not with modifier keys)
- **Modifier Key Empty Space Handling**: Shift+click and Command+click on empty space do nothing (preserve existing selection)
- **Marquee Selection with Groups**: Marquee selection now works even when groups are selected
- **Shift+Marquee Toggle Mode**: Hold Shift while marquee selecting to toggle items in/out of selection
- **Command+Marquee Toggle Mode**: Hold Command while marquee selecting to toggle items in/out of selection (added October 2025)
- **Contact Click Selection Fixed**: Shift+click and Command+click now properly toggle contacts (fixed October 2025)
- **Transform Handle Priority**: Transform handles have higher gesture priority to prevent interference

### **4. Database Integration**
- **Canvas Persistence**: All canvas data is now saved to the database canvas table
- **Automatic Saving**: Canvas state is automatically saved when elements are added/modified
- **Canvas Loading**: Canvases are loaded from database on startup and when switching between canvases
- **Canvas Management**: Create, update, and delete operations are supported

### **5. Transform Controls for Group Circles**
- **Selection Indication**: Selected group circles show a blue border
- **Resize Handles**: Four directional resize handles (top, right, bottom, left)
- **Rotate Handle**: Rotation control with clockwise arrow icon
- **Child Relationship**: Transform controls are rendered as children of group circles
- **Gesture Priority Fix (October 2024)**: Transform handles now have high priority gestures to prevent interference from canvas-level drag gestures

### **6. Code Organization Improvements**
- **Moved Transform Handles**: ResizeHandle and RotateHandle definitions moved from CanvasOverlay.swift to CanvasContainer.swift
- **Simplified Structure**: Transform controls are now inline with group circle code
- **Better Separation**: Canvas overlay handles are separate from group circle transform controls

## **Technical Implementation Details**

### **Scroll Wheel and Zoom Fixes (October 14, 2025 – Updated November 9, 2025)**
The scroll wheel and pinch zoom functionality was not working properly. The fixes involved:

1. **Scroll Wheel Event Monitor Fix**: Changed from `addGlobalMonitorForEvents` to `addLocalMonitorForEvents` in `SimplifiedCanvasView.swift` (line 842)
   - Global monitors only capture events sent to other applications
   - Local monitors capture events sent to our own app when it's focused
   - Now returns `nil` to consume the event and prevent default scrolling behavior

2. **Pinch Zoom in All Modes**: Removed hand mode restriction from `MagnificationGesture()` (lines 282-289)
   - Previously only worked in hand mode (`if viewModel.isHandMode`)
   - Now works in all canvas modes: selection, hand, and group add
   - Provides consistent zoom experience regardless of current mode

3. **Search Bar Focus Release**: Added automatic focus release when canvas page is selected
   - `SimplifiedCanvasView.onAppear` posts `UnfocusSearchBar` notification (line 361)
   - `WorkspaceView.onChange(of: selectedPage)` posts notification when switching to canvas page (line 79-83)
   - Ensures hotkeys work immediately without manual defocus
   - Search bars in `ContactsBarView` and `PageNavBarView` listen for this notification

4. **Shift-Select Multi-Selection Fixes** (October 14, 2025):
   - Fixed `SelectionManager.selectGroup()` to handle `.shift` modifier (now toggles selection like contacts do)
   - Added `toggleGroupSelection()` helper method to SelectionManager
   - Fixed canvas element modifier capture by adding mouse down event monitor
   - SwiftUI's `.onTapGesture` doesn't provide modifiers, so we capture them at mouse down time
   - Added `mouseDownMonitor` that captures `event.modifierFlags` on `.leftMouseDown` (line 860-863)
   - `handleContactTap()`, `handleGroupTap()`, and `handleUnifiedElementSelection()` now use `capturedModifierFlags`
   - Fixes issue where shift-select failed if user released shift key before tap handler ran

5. **Center-Preserving Zoom Adjustments** (November 9, 2025):
   - `GroupsMapViewModel.setZoom()` now recalculates pan offsets so the canvas center (or pinch anchor) remains stationary during zoom changes.
   - `CanvasGestures.handleZoomGesture()` and scroll-wheel zoom both call the new anchor-aware zoom path, ensuring consistent behavior across input types.
   - Horizontal trackpad deltas are respected, so two-finger left/right gestures pan the canvas horizontally without requiring Shift.

6. **Navigation Hotkey Release on Canvas Focus** (November 9, 2025):
   - Clicking anywhere on the canvas disables navigation bar hotkeys until the user interacts with the navigation UI again.
   - Prevents navigation shortcuts (W, comma, period) from intercepting canvas keystrokes, ensuring the canvas and its child views receive keyboard focus exclusively.

**Key Changes:**
- `SimplifiedCanvasView.swift`: Fixed scroll wheel monitor, removed pinch zoom restriction, added unfocus notification, added mouse down monitor for modifier capture
- `WorkspaceView.swift`: Added page selection change handler to unfocus search bars
- `SelectionManager.swift`: Added `toggleGroupSelection()` method and fixed `selectGroup()` to handle shift/command modifiers

### **Transform Handles Gesture Fix (October 2024)**
The transform handles were not responding to drag gestures due to gesture interference from canvas-level drag gestures. The fix involved:

1. **High Priority Gestures**: Transform handles now use `.highPriorityGesture()` to ensure they receive drag events before canvas gestures
2. **Canvas Gesture Exclusion**: Canvas-level drag gestures now check for transform handle areas and exclude them from marquee selection and pan gestures
3. **Group Container Gesture Management**: Group container drag gestures are disabled when transform handles are visible to prevent conflicts

**Key Changes:**
- `IntegratedResizeHandle` now uses `.highPriorityGesture()` instead of `.gesture()`
- `SimplifiedCanvasView` checks for transform handle positions in drag and tap gesture handlers
- `GroupCircleContainer` disables its drag gesture when `showTransformHandles` is true

### **Selection Behavior Improvements (October 2024-2025)**
The canvas selection system was enhanced to provide better user experience:

1. **Blank Space Selection Clearing**: 
   - Clicking on empty canvas areas now clears all selections
   - Only works in selection mode (not in hand mode or group add mode)
   - Respects shift key modifier for toggle mode

2. **Marquee Selection with Groups Selected**:
   - Removed the `!viewModel.isDragging` condition that prevented marquee selection when groups were selected
   - Marquee selection now works regardless of current selection state

3. **Shift+Marquee and Command+Marquee Toggle Mode**:
   - Hold Shift or Command while marquee selecting to toggle items in/out of selection
   - Items already selected are removed, items not selected are added
   - Works for both contacts and groups
   - Regular marquee (without modifiers) replaces the selection

4. **Contact Click Selection Fixed (October 2025)**:
   - Contact clicks now properly handle modifier keys
   - Shift+click on contact toggles selection (was broken, now fixed)
   - Command+click on contact toggles selection (was broken, now fixed)
   - Regular click replaces selection (already worked)

**Key Changes:**
- `SimplifiedCanvasView` tap gesture now clears selections on blank space in selection mode (but respects modifier keys)
- `SimplifiedCanvasView` drag gesture removed `!viewModel.isDragging` condition
- `CanvasGestures.swift` enhanced marquee selection logic with toggle mode support for both Shift and Command modifiers
- `SimplifiedCanvasView.handleContactTap()` fixed to call `handleUnifiedSelection()` with modifier keys (October 2025)
- `WorkspaceView.swift` updated to respect modifier keys when clearing selections on empty space
- Multiple tap gesture handlers now check for `.shift` and `.command` modifiers before clearing selections

### **Database Schema Integration**
```swift
// Canvas data is saved to database with the following structure:
struct Canvas {
    let id: String
    let name: String
    let elements: [CanvasElement]  // Contacts and groups
    let canvasType: CanvasType
    let canvasState: CanvasState   // Zoom, pan, grid settings, etc.
}
```

### **Canvas State Management**
```swift
// Canvas state includes:
struct CanvasState {
    var zoom: CGFloat
    var pan: CGPoint
    var gridEnabled: Bool
    var snapToGrid: Bool
    var gridSize: CGFloat
    var multiSelectMode: Bool
    var mode: CanvasMode          // select, hand, addGroup
    var selection: Set<UUID>
}
```

### **Transform Controls Structure**
```swift
// Transform controls are children of group circles:
GroupCircleWithTransforms {
    GroupCircleBackground
    TransformControls (only when selected) {
        ResizeHandle (4 directions)
        RotateHandle
    }
}
```

## **File Changes Summary**

### **Modified Files:**
1. **UI/Pages/PeopleMaps/SimplifiedCanvasView.swift**
   - Updated CanvasToolbar with proper controls layout
   - Added canvas selection dropdown
   - Added mode toggle buttons with visual feedback
   - **Fixed transform handle gesture interference** (October 2024)

2. **UI/Pages/PeopleMaps/GroupsMapViewModel.swift**
   - Integrated with DatabaseCanvasRepository
   - Added canvas persistence methods
   - Added mode management (setMode, toggleGrid)
   - Added database save/load operations

3. **UI/Components/GroupCircleView.swift**
   - Added ResizeHandle and RotateHandle definitions
   - Integrated transform controls with group circles
   - Added selection state management
   - **Fixed gesture priority for transform handles** (October 2024)

4. **UI/Pages/PeopleMaps/CanvasContainer.swift**
   - Added ResizeHandle and RotateHandle definitions
   - Integrated transform controls with group circles
   - Added selection state management

5. **UI/Pages/PeopleMaps/CanvasOverlay.swift**
   - Removed duplicate ResizeHandle and RotateHandle definitions
   - Updated GroupTransformHandles to use inline definitions

6. **Core/Models/CanvasModels.swift**
   - Added mode property to CanvasState
   - Updated database conversion methods

7. **Core/Models/CanvasTypes.swift**
   - Added CanvasMode enum with Codable support
   - Added GridBackground component

## **Usage Instructions**

### **Canvas Selection**
- Use the dropdown menu to switch between different canvases
- "Add New Canvas" option available for creating new canvases

### **Mode Controls**
- **Select Mode**: Click to select and manipulate elements
- **Hand Mode**: Click and drag to pan the canvas
- **Add Group Mode**: Click to add new group circles
- **Grid Toggle**: Click to show/hide the background grid

### **Transform Controls**
- **Select a group circle** to see transform controls
- **Drag resize handles** to resize the circle in four directions
- **Drag rotate handle** to rotate the circle

### **Selection Behaviors**
- **Click on blank space** in selection mode to clear all selections
- **Shift+Click or Command+Click** on any element to toggle its selection
- **Regular click** on any element to replace selection with just that element
- **Marquee selection** works even when groups are selected
- **Shift+Marquee or Command+Marquee** to toggle items in/out of selection
- **Regular marquee** (no modifiers) replaces selection with items in rectangle
- **Transform handles** have priority over canvas gestures

### **Database Persistence**
- All changes are automatically saved to the database
- Canvas state persists between app sessions
- Multiple canvases can be created and managed

## **Future Enhancements**

1. **Canvas Templates**: Pre-built canvas layouts
2. **Canvas Export/Import**: Share canvas configurations
3. **Advanced Transform Controls**: Skew, scale, etc.
4. **Canvas Collaboration**: Multi-user canvas editing
5. **Canvas History**: Undo/redo for canvas operations
