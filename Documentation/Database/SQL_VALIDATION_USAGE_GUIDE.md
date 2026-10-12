# SQL Validation Service Usage Guide

## Overview

The `SQLValidationService` provides comprehensive validation and logging for all SQL operations in your CRM application. It helps prevent data corruption by validating inputs before executing SQL queries and provides detailed logging for debugging.

## Key Features

### 1. **Data Validation**
- Validates all data types before SQL execution
- Checks for SQL injection patterns
- Validates phone numbers, emails, and other field formats
- Ensures data integrity across all operations

### 2. **Comprehensive Logging**
- Logs all incoming data and parameters
- Logs the final SQL query being executed
- Provides validation IDs for tracking operations
- Integrates with your existing `LogManager` and `DatabaseLogger`

### 3. **SQL Safety**
- Prevents dangerous SQL operations (DROP, TRUNCATE, etc.)
- Validates SQL query syntax and structure
- Ensures proper parameter binding

## Usage Examples

### Basic Validation

```swift
// Validate a contact save operation
let validation = SQLValidationService.shared.validateSQLOperation(
    operation: "SAVE_CONTACT",
    query: "INSERT INTO contacts (phone, name) VALUES (?, ?)",
    parameters: ["phone": "+1234567890", "name": "John Doe"],
    data: contact
)

if validation.isValid {
    // Proceed with SQL execution
    print("✅ Validation passed: \(validation.validationId)")
} else {
    // Handle validation errors
    print("❌ Validation failed: \(validation.errors)")
}
```

### Using the Validated SQL Execution Wrapper

```swift
// Direct validated SQL execution
let result = SQLValidationService.shared.executeSQLWithValidation(
    operation: "UPDATE_GROUP",
    query: "UPDATE groups SET name = ?, color = ? WHERE id = ?",
    database: database,
    parameters: ["name": "New Group Name", "color": "#FF0000", "id": 123],
    data: contactGroup
)

if result.success {
    print("✅ SQL execution successful")
} else {
    print("❌ SQL execution failed: \(result.error ?? "Unknown error")")
}
```

### Integration with SQLiteDataProvider

The `SQLiteDataProvider` now includes validated versions of all SQL operations:

```swift
// Instead of calling the old method:
// await saveContactToDatabase(contact)

// Use the validated version:
await saveContactToDatabaseValidated(contact)
```

## Validation Rules

### Contact Validation
- Phone number must not be empty and should match phone format
- Name should not be empty (warning if empty)
- Email format validation if provided
- Notes length validation (warns if > 10,000 characters)

### Group Validation
- Group name must not be empty
- Member phone count validation (warns if > 1,000)
- Canvas count validation (warns if > 100)
- Linked group count validation (warns if > 50)

### Invite Validation
- Title must not be empty
- Description length validation
- Phone number format validation
- Due date validation

### Batch Message Validation
- Message template must not be empty
- Recipients must not be empty
- Recipient count validation (warns if > 10,000)
- Individual recipient phone validation

## SQL Safety Checks

The service prevents execution of potentially dangerous SQL operations:

- **SQL Comments**: Detects `--` and `/*` patterns
- **Multiple Statements**: Detects semicolon separators
- **Dangerous Operations**: Blocks DROP, TRUNCATE, ALTER statements
- **Query Length**: Warns about extremely long queries
- **Unusual Keywords**: Warns about non-standard SQL keywords

## Logging Output

### Validation Logging
```
🔍 [a1b2c3d4] Starting SQL validation for operation: SAVE_CONTACT
📥 [a1b2c3d4] Incoming data for operation: SAVE_CONTACT
📥 [a1b2c3d4] Parameters (2):
📥 [a1b2c3d4]   phone: String(12 chars): '+1234567890'
📥 [a1b2c3d4]   name: String(8 chars): 'John Doe'
📥 [a1b2c3d4] Data object: Contact(name: 'John Doe', phone: '+1234567890', email: john@example.com)
🔍 [a1b2c3d4] Validating SQL query syntax and safety
✅ [a1b2c3d4] SQL query validation passed
🔍 [a1b2c3d4] Validating 2 parameters
✅ [a1b2c3d4] Parameter validation passed
🔍 [a1b2c3d4] Validating data object for operation: SAVE_CONTACT
✅ [a1b2c3d4] Data validation passed
🚀 [a1b2c3d4] Executing SQL for operation: SAVE_CONTACT
🚀 [a1b2c3d4] SQL Query: INSERT INTO contacts (phone, name) VALUES (?, ?)
🚀 [a1b2c3d4] Bound Parameters:
🚀 [a1b2c3d4]   phone: String(12 chars): '+1234567890'
🚀 [a1b2c3d4]   name: String(8 chars): 'John Doe'
✅ [a1b2c3d4] SQL validation passed for operation: SAVE_CONTACT
```

### Error Logging
```
❌ [a1b2c3d4] SQL Safety Violation: DROP statement detected
❌ [a1b2c3d4] Contact phone number is empty
❌ [a1b2c3d4] Parameter 'name' has unexpected type: NSNumber
```

## Migration Strategy

### Phase 1: Enable Validation (Current)
1. Add the `SQLValidationService` to your project
2. The validated methods are available alongside existing methods
3. Test the validation system with existing operations

### Phase 2: Gradual Migration
1. Start using validated methods for new features
2. Gradually replace existing SQL calls with validated versions
3. Monitor logs for any validation issues

### Phase 3: Full Migration
1. Replace all SQL operations with validated versions
2. Remove old unvalidated methods
3. Enable strict validation mode

## Configuration

### Validation Limits
```swift
private let maxStringLength = 10000        // Maximum string length
private let maxJsonLength = 50000          // Maximum JSON data length
private let allowedSqlKeywords = [...]     // Allowed SQL operation keywords
```

### Custom Validation Rules
You can extend the validation by adding custom rules in the entity-specific validation methods:

```swift
private func validateContact(contact: Contact, validationId: String) -> ValidationResult {
    // Add your custom validation rules here
    var warnings: [String] = []
    var errors: [String] = []
    
    // Custom rule example
    if contact.name.contains("test") {
        warnings.append("Contact name contains 'test' - may be test data")
    }
    
    return ValidationResult(isValid: errors.isEmpty, ...)
}
```

## Benefits

1. **Data Integrity**: Prevents corrupted data from entering the database
2. **Security**: Protects against SQL injection attacks
3. **Debugging**: Comprehensive logging helps identify issues quickly
4. **Monitoring**: Validation IDs allow tracking of specific operations
5. **Consistency**: Ensures all data follows the same validation rules
6. **Audit Trail**: Complete log of all database operations

## Performance Considerations

- Validation adds minimal overhead (typically < 1ms per operation)
- Logging can be controlled via your existing log level settings
- Validation is performed in-memory before database operations
- Failed validations prevent expensive database operations

## Integration with Existing Systems

The validation service integrates seamlessly with your existing logging infrastructure:

- Uses `LogManager.shared` for application logging
- Uses `DatabaseLogger.shared` for database operation logging
- Maintains the same logging format and patterns
- Preserves all existing functionality while adding validation

This system ensures that your database operations are safe, logged, and validated while maintaining the performance and functionality of your existing CRM application.
