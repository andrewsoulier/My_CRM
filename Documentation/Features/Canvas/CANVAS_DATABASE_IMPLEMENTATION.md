# Canvas Database Implementation

## Overview

This document describes the comprehensive canvas database implementation for the My CRM application. The canvas system provides persistent storage for visual relationship mapping, allowing users to create, manage, and interact with visual canvases containing contacts, groups, and other elements.

## Database Schema

### Canvases Table

The `canvases` table stores all canvas definitions and layouts:

```sql
CREATE TABLE canvases (
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
);
```

### Element Structure

Each canvas element is stored as a JSON object with the following structure:

```json
{
    "element_id": "unique-element-id",
    "element_type": "contact|group|deck|custom",
    "location": {"x": 100, "y": 100},
    "scale": 1.0,
    "width": 60,
    "height": 80,
    "rotation": 0,
    "color": "#007AFF"
}
```

### Element Counts

The `element_counts` field stores a JSON object with counts by type:

```json
{
    "contacts": 5,
    "groups": 3,
    "decks": 1,
    "all": 9
}
```

### Canvas Types

- `group_map`: Visual mapping of contact groups
- `deck_map`: Visual mapping of contact decks  
- `contact_map`: Visual mapping of individual contacts
- `custom`: Custom canvas type

## Performance Optimizations

### Indexes

The following indexes are created for optimal performance:

- `idx_canvases_id`: UNIQUE on canvas_id
- `idx_canvases_name`: INDEX on canvas_name
- `idx_canvases_type`: INDEX on canvas_type
- `idx_canvases_created`: INDEX on date_created
- `idx_canvases_updated`: INDEX on date_updated
- `idx_canvases_type_updated`: INDEX on canvas_type, date_updated

### JSON Storage

- Canvas elements are stored as JSON arrays for flexibility
- Element counts are automatically calculated and cached
- Canvas state (zoom, pan, grid settings) is stored as JSON
- Metadata allows for future extensibility

## API Implementation

### Python Backend

#### DatabaseManager Class

The `DatabaseManager` class provides comprehensive canvas management:

```python
# Create a new canvas
db.create_canvas(canvas_id, canvas_name, canvas_type, initial_elements, initial_state)

# Retrieve a canvas
canvas = db.get_canvas(canvas_id)

# Update canvas properties
db.update_canvas(canvas_id, updates)

# Delete a canvas
db.delete_canvas(canvas_id)

# Element operations
db.add_canvas_element(canvas_id, element)
db.update_canvas_element(canvas_id, element_id, updates)
db.remove_canvas_element(canvas_id, element_id)

# Search and discovery
canvases = db.get_all_canvases(canvas_type)
results = db.search_canvases(query, canvas_type)
```

#### Canvas Manager Script

Command-line interface for canvas operations:

```bash
# Create canvas
python3 canvas_manager.py create_canvas --canvas-id "my-canvas" --canvas-name "My Canvas" --canvas-type "group_map"

# Get canvas
python3 canvas_manager.py get_canvas --canvas-id "my-canvas"

# Add element
python3 canvas_manager.py add_element --canvas-id "my-canvas" --element '{"element_id": "contact-1", "element_type": "contact", ...}'

# Update element
python3 canvas_manager.py update_element --canvas-id "my-canvas" --element-id "contact-1" --element '{"scale": 1.5, ...}'

# Search canvases
python3 canvas_manager.py search_canvases --query "My Canvas"
```

### Swift Frontend

#### Canvas Models

```swift
struct Canvas: Identifiable, Codable {
    let id: String
    var name: String
    var elements: [CanvasElement]
    var elementCounts: ElementCounts
    var dateCreated: Date
    var dateUpdated: Date
    var canvasType: CanvasType
    var canvasState: CanvasState
    var metadata: [String: Any]
}

struct CanvasElement: Identifiable, Codable {
    let id: String
    var elementType: ElementType
    var location: CGPoint
    var scale: CGFloat
    var width: CGFloat
    var height: CGFloat
    var rotation: CGFloat
    var color: String
}
```

#### CanvasUpdateService

The `CanvasUpdateService` provides real-time canvas management with debounced updates:

```swift
let canvasService = CanvasUpdateService()

// Create and load canvases
let canvas = canvasService.createCanvas(name: "My Canvas", type: .groupMap)
let loadedCanvas = canvasService.loadCanvas(id: "canvas-id")

// Save changes (automatically debounced)
canvasService.saveCanvas(canvas)

// Element operations
canvasService.addElement(element, to: canvasId)
canvasService.updateElement(element, in: canvasId)
canvasService.removeElement(elementId: "element-id", from: canvasId)

// Batch operations
canvasService.updateElementPositions(elements, in: canvasId)
canvasService.updateCanvasState(state, for: canvasId)
```

## Integration with UI

### Real-time Updates

The canvas system integrates seamlessly with the UI:

1. **Debounced Saves**: UI changes are automatically saved after 0.5 seconds of inactivity
2. **Batch Operations**: Multiple element updates are grouped for efficiency
3. **Error Handling**: Failed updates are reported to the UI
4. **State Persistence**: Canvas view state (zoom, pan, grid) is preserved

### Conversion Utilities

Built-in conversion between UI models and database format:

```swift
// Convert ContactNode to CanvasElement
let element = contactNode.toCanvasElement()

// Convert CanvasElement back to ContactNode
let contactNode = ContactNode.fromCanvasElement(element)

// Convert GroupCircle to CanvasElement
let element = groupCircle.toCanvasElement()
```

## Scalability Considerations

### Performance

- **Indexed Queries**: Fast retrieval by canvas type and date
- **JSON Storage**: Efficient storage of complex element data
- **Debounced Updates**: Reduces database load during UI interactions
- **Batch Operations**: Groups multiple updates for efficiency

### Future Extensibility

- **Element Types**: Easy to add new element types (decks, custom elements)
- **Canvas Types**: Extensible canvas type system
- **Metadata**: Flexible metadata storage for future features
- **State Management**: Canvas state can be extended with new properties

### Data Integrity

- **Automatic Counts**: Element counts are always accurate
- **Foreign Key Relationships**: Proper relationships with contacts and groups
- **Audit Trail**: Creation and update timestamps for all canvases
- **Validation**: JSON schema validation for element data

## Testing

### Database Schema Tests

Run the comprehensive test suite:

```bash
python3 test_database_schema.py
```

This tests:
- Table creation and structure
- Index creation
- CRUD operations
- Element management
- Search functionality
- Data integrity

### Manual Testing

Test the canvas manager script:

```bash
# Create a test canvas
python3 canvas_manager.py create_canvas --canvas-id "test" --canvas-name "Test" --canvas-type "group_map"

# Add elements
python3 canvas_manager.py add_element --canvas-id "test" --element '{"element_id": "contact-1", "element_type": "contact", ...}'

# Verify counts
python3 canvas_manager.py get_canvas --canvas-id "test"
```

## Usage Examples

### Creating a Group Map Canvas

```swift
let canvasService = CanvasUpdateService()

// Create a new group map canvas
let canvas = canvasService.createCanvas(name: "Team Relationships", type: .groupMap)

// Add contact elements
let contactElement = CanvasElement(
    id: UUID().uuidString,
    elementType: .contact,
    location: CGPoint(x: 100, y: 100),
    scale: 1.0,
    width: 60,
    height: 80,
    rotation: 0,
    color: "#007AFF"
)

canvasService.addElement(contactElement, to: canvas.id)

// Add group elements
let groupElement = CanvasElement(
    id: UUID().uuidString,
    elementType: .group,
    location: CGPoint(x: 200, y: 200),
    scale: 1.0,
    width: 100,
    height: 100,
    rotation: 0,
    color: "#FF3B30"
)

canvasService.addElement(groupElement, to: canvas.id)
```

### Loading and Updating a Canvas

```swift
// Load existing canvas
if let canvas = canvasService.loadCanvas(id: "existing-canvas-id") {
    // Update element positions
    var updatedElements = canvas.elements
    updatedElements[0].location = CGPoint(x: 150, y: 150)
    
    var updatedCanvas = canvas
    updatedCanvas.elements = updatedElements
    
    // Save changes (automatically debounced)
    canvasService.saveCanvas(updatedCanvas)
}
```

## Cache Management and Data Integrity

### Canvas Loading Process

The canvas loading process includes automatic cleanup of deleted group references:

1. **Canvas Loading**: When a canvas is loaded from the database, the system checks for references to deleted groups
2. **Element Cleanup**: The `cleanupCanvasElements` method removes canvas elements that reference non-existent groups
3. **Preserved Changes**: The cleanup process does not immediately save the cleaned canvas to prevent overwriting recent changes
4. **Delayed Save**: Cleaned canvases are saved after the loading process completes to ensure data integrity

### Cache Override Prevention

**Issue Resolved**: Previously, the canvas loading process would immediately save cleaned canvases back to the database, which could overwrite recent changes with older cached data.

**Solution**: The cleanup process now:
- Creates a cleaned canvas with valid elements only
- Does not immediately save the cleaned canvas to the database
- Saves the cleaned canvas only after the loading process completes
- Preserves recent changes by avoiding premature database writes

### Implementation Details

```swift
// In cleanupCanvasElements method
let cleanedCanvas = Canvas(
    id: canvas.id,
    name: canvas.name,
    elements: validElements,  // Only elements referencing existing groups
    canvasType: canvas.canvasType,
    canvasState: canvas.canvasState
)

// Cleaned canvas is returned but not immediately saved
// This prevents overwriting recent changes with cached data
return cleanedCanvas
```

The cleaned canvas is then saved after the loading process completes:

```swift
// In loadCanvasFromDatabase method
if cleanedCanvas.elements.count != canvas.elements.count {
    // Canvas was cleaned - save the cleaned version
    let dbRepository = DatabaseCanvasRepository()
    let success = dbRepository.updateCanvas(cleanedCanvas)
}
```

## Conclusion

The canvas database implementation provides a robust, scalable foundation for visual relationship mapping in the My CRM application. With comprehensive CRUD operations, real-time updates, excellent performance characteristics, and proper cache management, it supports the current needs while remaining extensible for future features.

The system successfully balances flexibility (JSON storage) with performance (indexed queries) and provides a clean API for both Python backend operations and Swift frontend integration. The recent cache management improvements ensure that recent canvas changes are preserved during the loading process.
