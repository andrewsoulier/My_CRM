# Contacts Bar Selection Features

This document describes the selection features implemented in the Contacts Bar view, providing comprehensive keyboard and mouse-based selection capabilities similar to file selection in macOS Finder.

## Overview

The Contacts Bar and Groups Bar now support full selection functionality including:
- Keyboard navigation with arrow keys
- Mouse-based selection with modifier keys
- Range selection with Shift+click (clears existing selections)
- Multi-selection with Command+click or Option+click
- Keyboard-based range extension
- Identical selection behavior for both contacts and groups

## Selection Methods

### Mouse Selection

#### Single Click
- **Action**: Click on any contact
- **Behavior**: Selects only that contact, deselecting all others
- **Visual**: Contact row highlighted with accent color

#### Command+Click (⌘+Click)
- **Action**: Hold Command key and click on contacts
- **Behavior**: Toggles selection of individual contacts (add/remove from selection)
- **Use Case**: Select multiple non-contiguous contacts
- **Visual**: Each selected contact highlighted independently

#### Option+Click (⌥+Click)
- **Action**: Hold Option key and click on contacts
- **Behavior**: Toggles selection of individual contacts (add/remove from selection)
- **Use Case**: Alternative to Command+Click for selecting multiple non-contiguous contacts
- **Visual**: Each selected contact highlighted independently

#### Shift+Click
- **Action**: Hold Shift key and click on a contact
- **Behavior**: Selects range from last selected contact to clicked contact (clears previous selections)
- **Use Case**: Select contiguous range of contacts (standard macOS behavior)
- **Visual**: All contacts in range highlighted

### Keyboard Navigation

#### Basic Navigation
- **↑ Arrow**: Move focus up one contact
- **↓ Arrow**: Move focus down one contact
- **Behavior**: Selects the focused contact, deselecting others
- **Visual**: Focused contact highlighted with focus ring

#### Range Extension
- **Shift+↑**: Extend selection up one contact
- **Shift+↓**: Extend selection down one contact
- **Behavior**: Extends selection range from last selected contact
- **Use Case**: Extend or modify existing range selection

#### Jump Navigation
- **Cmd+↑**: Jump to first contact and select it
- **Cmd+↓**: Jump to last contact and select it
- **Behavior**: Clears current selection and selects target contact

#### Range to Boundaries
- **Cmd+Shift+↑**: Extend selection to top of list
- **Cmd+Shift+↓**: Extend selection to bottom of list
- **Behavior**: Extends selection from last selected contact to boundary
- **Use Case**: Select all contacts from current position to top/bottom

### Keyboard Shortcuts

#### Selection Management
- **Escape**: Clear all selections
- **Cmd+A**: Select all visible contacts
- **Behavior**: Selects all contacts currently displayed in the contacts bar

#### Focus Management
- **Tab**: Focus moves to search bar (when not in search)
- **Search Bar Focus**: Keyboard navigation disabled, only search shortcuts work
- **Auto-scroll**: Focused contact automatically scrolls into view

## Implementation Details

### SelectionManager Integration

The Contacts Bar uses the existing `SelectionManager` service which provides:
- Contact list context management
- Focus tracking with `focusedContactIndex`
- Selection state with `selectedContacts` set
- Keyboard navigation methods

### Visual Indicators

#### Selection Highlighting
- **Selected Contact**: Accent color background with subtle border
- **Focused Contact**: Focus ring with accent color border
- **Range Selection**: All contacts in range highlighted
- **Smooth Transitions**: Animated focus changes

#### Scroll Behavior
- **Auto-scroll**: Focused contact automatically scrolls to center
- **Smooth Animation**: 0.2-second ease-in-out animation
- **Viewport Awareness**: Only scrolls when contact is outside visible area

### Context Management

#### Contact List Context
- **Dynamic Updates**: Context updated when contacts list changes (search, filter, sort)
- **Index Validation**: Focus index validated when context changes
- **Search Integration**: Context switches between displayed contacts and search results

#### State Persistence
- **Selection Persistence**: Selections maintained during search/filter operations
- **Focus Persistence**: Focus maintained when possible during context changes
- **Automatic Cleanup**: Invalid selections removed when context changes

## Usage Examples

### Selecting Multiple Contacts
1. Click on first contact
2. Hold Command (or Option) and click on additional contacts
3. Result: Multiple non-contiguous contacts selected

### Selecting a Range
1. Click on first contact in desired range
2. Hold Shift and click on last contact in range
3. Result: Previous selections cleared, all contacts between first and last selected (standard macOS behavior)

### Keyboard Range Selection
1. Use arrow keys to navigate to first contact
2. Hold Shift and use arrow keys to extend selection
3. Result: Range selection extended with keyboard

### Selecting All Contacts
1. Press Cmd+A
2. Result: All visible contacts selected

### Clearing Selection
1. Press Escape or click on empty area
2. Result: All selections cleared

## Technical Implementation

### Key Components

#### ContactsBarView
- Handles keyboard input with `onKeyPress`
- Manages focus state with `@FocusState`
- Integrates with `ScrollViewReader` for auto-scroll

#### ContactRowView
- Detects modifier keys in tap gestures
- Provides visual feedback for selection state
- Handles individual contact selection

#### SelectionManager
- Manages selection state and focus tracking
- Provides keyboard navigation methods
- Handles range selection logic

### Event Handling

#### Keyboard Events
```swift
private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
    guard !isSearchFocused else { return .ignored }
    
    switch keyPress.key {
    case .escape:
        selectionManager.clearAllSelections()
        return .handled
    case KeyEquivalent("a"):
        if keyPress.modifiers.contains(.command) {
            selectionManager.selectAllContacts()
            return .handled
        }
    case .upArrow:
        selectionManager.moveFocusUp(modifiers: keyPress.modifiers)
        return .handled
    case .downArrow:
        selectionManager.moveFocusDown(modifiers: keyPress.modifiers)
        return .handled
    default:
        break
    }
    return .ignored
}
```

#### Mouse Events
```swift
private func handleContactSelection() {
    let modifiers = NSEvent.modifierFlags
    let eventModifiers: EventModifiers = {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        return result
    }()
    
    selectionManager.handleContactTap(contact.phone, modifiers: eventModifiers)
}
```

### Auto-scroll Implementation
```swift
.onChange(of: selectionManager.focusedContactIndex) { _, newIndex in
    if !selectionManager.contactListContext.isEmpty && 
       newIndex < selectionManager.contactListContext.count {
        let focusedPhone = selectionManager.contactListContext[newIndex]
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(focusedPhone, anchor: .center)
        }
    }
}
```

## Accessibility

### Keyboard Navigation
- Full keyboard accessibility for all selection operations
- Standard macOS keyboard shortcuts (Cmd+A, Escape, etc.)
- Arrow key navigation with modifier support

### Visual Feedback
- Clear visual indicators for selection state
- Focus rings for keyboard navigation
- Smooth animations for better user experience

### Screen Reader Support
- Contact information properly labeled
- Selection state communicated to assistive technologies
- Keyboard shortcuts documented and consistent

## Group Selection

All contact selection features work identically for groups in the Groups Bar:
- **Single Click**: Select a single group
- **Command+Click / Option+Click**: Toggle group selection
- **Shift+Click**: Select range of groups (clears existing selections)
- **Visual Indicators**: Selected groups show accent color background with border
- **Context Management**: Group list context maintained for range selections

## Future Enhancements

### Planned Features
- **Multi-column selection**: Support for selecting across multiple contact properties
- **Selection persistence**: Remember selections across app sessions
- **Bulk operations**: Apply actions to multiple selected contacts/groups
- **Selection history**: Undo/redo for selection operations
- **Keyboard navigation for groups**: Arrow key navigation in Groups Bar

### Potential Improvements
- **Custom selection modes**: Different selection behaviors for different use cases
- **Selection shortcuts**: Customizable keyboard shortcuts for selection operations
- **Visual selection tools**: Marquee selection with mouse drag
- **Selection filtering**: Filter contacts/groups based on selection criteria

## Testing

### Manual Testing Checklist

#### Contacts Bar
- [ ] Single click selection
- [ ] Command+click multi-selection
- [ ] Option+click multi-selection
- [ ] Shift+click range selection (clears existing)
- [ ] Arrow key navigation
- [ ] Shift+arrow range extension
- [ ] Command+arrow jump navigation
- [ ] Command+Shift+arrow boundary selection
- [ ] Escape to clear selection
- [ ] Command+A to select all
- [ ] Auto-scroll to focused contact
- [ ] Selection persistence during search
- [ ] Focus management during context changes
- [ ] Visual indicators show immediately
- [ ] Contacts display on app startup

#### Groups Bar
- [ ] Single click selection
- [ ] Command+click multi-selection
- [ ] Option+click multi-selection
- [ ] Shift+click range selection (clears existing)
- [ ] Visual indicators show immediately
- [ ] Groups display on app startup

### Automated Testing
- Unit tests for SelectionManager methods
- UI tests for keyboard navigation
- Integration tests for selection state management
- Performance tests for large contact lists

## Troubleshooting

### Common Issues

#### Selection Not Working
- Check if search bar has focus (keyboard navigation disabled)
- Verify SelectionManager is properly initialized
- Ensure contact list context is updated

#### Focus Not Visible
- Check if focus ring styling is applied
- Verify focusedContactIndex is within valid range
- Ensure contact list context matches displayed contacts

#### Auto-scroll Not Working
- Verify ScrollViewReader is properly configured
- Check if contact IDs are unique and consistent
- Ensure onChange handler is properly attached

#### Range Selection Issues
- Verify lastSelectedContact is properly set
- Check if contact list context is up to date
- Ensure range calculation logic is correct

### Debug Information
- Use console logging to track selection state changes
- Monitor focusedContactIndex and selectedContacts
- Check contact list context updates
- Verify keyboard event handling

