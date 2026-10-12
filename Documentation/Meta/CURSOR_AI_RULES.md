# Cursor AI Rules for My CRM Project

## Database-Centric Architecture Rules

### Core Principle
**All aspects of this application must be reflected in the database such that any change to the data anywhere is always reflected in the database. The goal is to be able to take the database in any format and provide a usable UI for the user to interact with it.**

### Mandatory Implementation Rules

#### 1. Database as Single Source of Truth
- All application state, user interactions, and data modifications must be persisted in the database
- No UI state should exist without corresponding database persistence
- Database state takes precedence over any UI state
- All changes must be immediately synchronized with the database

#### 2. Stateless UI Components
- UI components must not maintain independent state that isn't reflected in the database
- All UI components should be views of database content
- UI state must be reconstructable from database content
- Temporary UI state must be explicitly marked as temporary

#### 3. Database-First Development
- Always design database schema first before implementing UI
- Implement database services before UI components
- All user interactions must trigger immediate database updates
- Database operations must be properly error-handled and recoverable

#### 4. Real-time Synchronization
- All UI changes must be immediately persisted to database
- Implement database observers for real-time UI updates
- Use database transactions for complex operations
- Ensure data consistency across all application components

#### 5. Error Handling and Recovery
- Implement proper database error handling
- Application must be able to recover from database failures
- UI state should be reconstructable from database content
- Implement proper rollback mechanisms for failed operations

## Development Workflow Rules

### Before Starting Any Feature
1. **Database Schema First**: Design and update database schema in `database_requirements.json`
2. **Service Layer**: Implement database services with proper error handling
3. **UI Components**: Create stateless UI components that reflect database state
4. **Testing**: Write database integration tests and UI component tests

### Code Review Requirements
- [ ] All user interactions update the database
- [ ] No UI state exists without database persistence
- [ ] Database operations are properly error-handled
- [ ] UI state can be reconstructed from database
- [ ] All changes are immediately synchronized
- [ ] Database schema is properly documented

### Testing Requirements
- All tests must verify database persistence
- UI component tests must verify database state reflection
- Database integration tests must cover all CRUD operations
- Error handling tests must verify recovery scenarios

## File Structure Rules

### Database Schema
- All schema changes must be documented in `database_requirements.json`
- Database migrations must be backward compatible
- Schema changes must be tested before implementation

### Service Layer
- All services must implement database-first patterns
- Services must handle database errors gracefully
- Services must provide real-time synchronization capabilities

### UI Components
- UI components must be stateless database views
- All user interactions must trigger database updates
- UI state must be persisted to database

## Documentation Requirements

### After Every Code Change
1. Update relevant documentation files
2. Update database schema documentation if applicable
3. Update implementation guides if new patterns are introduced
4. Ensure all documentation reflects database-centric approach
5. Confirm every new or updated guide lives inside the `Documentation/` hierarchy and is indexed in `Documentation/README.md`

### Documentation Files to Maintain
- `Documentation/Architecture/DATABASE_CENTRIC_ARCHITECTURE.md` - Core architecture principles
- `Documentation/Database/database_requirements.json` - Database schema
- `Documentation/Development/DATABASE_FIRST_IMPLEMENTATION_GUIDE.md` - Implementation patterns
- `Documentation/README.md` - Directory index and placement rules for all documentation
- `README.md` - Project overview with database-centric principles
- `Documentation/Meta/CURSOR_AI_RULES.md` - This file with current rules

## Build and Deployment Rules

### After Every Change
1. Kill all related processes
2. Use `./build_app.sh "Build description (5-10 words)"` - The script automatically creates a project archive
3. The build script automatically bundles a copy of the project, labels it with date and description, and places it in "andrewsoulier/My_CRM Project/Working Files, not part of app/Project Archives"
4. Launch the new build
5. After 5 seconds, scan CPU usage and application logs on **every computer listed in `REMOTE_COMPUTERS` (including the local Mac)** and report any errors or anomalies discovered
6. Keep the `REMOTE_COMPUTERS` array inside `build_app.sh` up to date; it is the canonical list for multi-machine builds and health checks

### File Management
- Do not delete files, simply de-reference them and mark them for deletion with a prefix "-- Old --"
- Always refer to README, requirements, .md, and .txt files that show the intended structure when starting a new task
- If user requests differ from support documentation, update the support documentation to match

## Memory and Context Rules

### Element ID Management
- Always set element_ID using the database ID; never fallback to a UUID
- For groups in the canvas view, identify them by their integer database ID rather than UUID strings
- If no database ID is found, treat the element as deleted

### Data Structure Naming
- Use "ContactGroup" for data structures holding groups of contacts in the database
- Use "GroupCircle" for the UI element representing a contact group with a circle or ellipsis on the Groups map canvases

### UI Behavior
- In the project UI, pressing 'G' activates the group tool
- After a group is made, it automatically returns to selection mode

## Quality Assurance Rules

### Code Quality
- Follow Swift naming conventions
- Add documentation comments for public APIs
- Write unit tests for all business logic and database operations
- Use `@MainActor` for UI-related code
- Prefer `Observable` over `ObservableObject` where possible

### Performance
- Use database pagination for large datasets
- Implement efficient change detection
- Use debounced updates for rapid changes
- Cache frequently accessed data with database validation

### Security
- Validate all database inputs
- Use parameterized queries to prevent SQL injection
- Implement proper authentication and authorization
- Secure sensitive data in the database

## Conclusion

These rules ensure that the My CRM application maintains its database-centric architecture, providing reliable operation, data integrity, and the ability to work with any database containing the proper schema. All development work must follow these principles to maintain the integrity and reliability of the application.

**Remember**: Database First, UI Second - Always design and implement the database layer before creating UI components.
