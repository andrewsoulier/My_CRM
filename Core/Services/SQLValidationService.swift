import Foundation
import SQLite3

// MARK: - SQL Validation Service

@MainActor
class SQLValidationService: ObservableObject {
    static let shared = SQLValidationService()
    
    private let logger = LogManager.shared
    private let databaseLogger = DatabaseLogger.shared
    
    // Validation configuration
    private let maxStringLength = 10000
    private let maxJsonLength = 50000
    private let allowedSqlKeywords = ["SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER", "BEGIN", "COMMIT", "ROLLBACK"]
    
    private init() {}
    
    // MARK: - Main Validation Function
    
    /// Validates data and SQL query before execution, with comprehensive logging
    /// - Parameters:
    ///   - operation: The operation being performed (e.g., "SAVE_CONTACT", "UPDATE_GROUP")
    ///   - query: The SQL query string
    ///   - parameters: Dictionary of parameters being bound to the query
    ///   - data: The data object being saved (for validation and logging)
    /// - Returns: ValidationResult indicating if the operation should proceed
    func validateSQLOperation(
        operation: String,
        query: String,
        parameters: [String: Any] = [:],
        data: Any? = nil
    ) -> ValidationResult {
        
        let validationId = UUID().uuidString.prefix(8)
        let timestamp = Date()
        
        logger.info("🔍 [\(validationId)] Starting SQL validation for operation: \(operation)")
        
        // Log the incoming data
        logIncomingData(validationId: String(validationId), operation: operation, data: data, parameters: parameters)
        
        // Validate SQL query syntax and safety
        let sqlValidation = validateSQLQuery(query: query, validationId: String(validationId))
        if !sqlValidation.isValid {
            return sqlValidation
        }
        
        // Validate parameters
        let parameterValidation = validateParameters(parameters: parameters, validationId: String(validationId))
        if !parameterValidation.isValid {
            return parameterValidation
        }
        
        // Validate data object if provided
        if let data = data {
            let dataValidation = validateDataObject(data: data, operation: operation, validationId: String(validationId))
            if !dataValidation.isValid {
                return dataValidation
            }
        }
        
        // Log the final SQL query that will be executed
        logSQLExecution(validationId: String(validationId), operation: operation, query: query, parameters: parameters)
        
        logger.info("✅ [\(validationId)] SQL validation passed for operation: \(operation)")
        
        return ValidationResult(
            isValid: true,
            validationId: String(validationId),
            timestamp: timestamp,
            warnings: sqlValidation.warnings + parameterValidation.warnings,
            operation: operation
        )
    }
    
    // MARK: - SQL Query Validation
    
    private func validateSQLQuery(query: String, validationId: String) -> ValidationResult {
        logger.info("🔍 [\(validationId)] Validating SQL query syntax and safety")
        
        var warnings: [String] = []
        
        // Check for basic SQL injection patterns
        let dangerousPatterns = [
            ("--", "SQL comment detected"),
            ("/*", "SQL block comment detected"),
            (";", "Multiple statement separator detected"),
            ("DROP", "DROP statement detected"),
            ("TRUNCATE", "TRUNCATE statement detected"),
            ("ALTER", "ALTER statement detected")
        ]
        
        let upperQuery = query.uppercased()
        
        for (pattern, message) in dangerousPatterns {
            if upperQuery.contains(pattern) {
                logger.error("❌ [\(validationId)] SQL Safety Violation: \(message)")
                return ValidationResult(
                    isValid: false,
                    validationId: validationId,
                    timestamp: Date(),
                    errors: ["SQL Safety Violation: \(message)"],
                    operation: "SQL_VALIDATION"
                )
            }
        }
        
        // Check query length
        if query.count > maxStringLength {
            warnings.append("SQL query is very long (\(query.count) characters)")
        }
        
        // Validate basic SQL structure
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            logger.error("❌ [\(validationId)] Empty SQL query")
            return ValidationResult(
                isValid: false,
                validationId: validationId,
                timestamp: Date(),
                errors: ["Empty SQL query"],
                operation: "SQL_VALIDATION"
            )
        }
        
        // Check if query starts with allowed keywords
        let firstWord = trimmedQuery.components(separatedBy: .whitespaces).first?.uppercased() ?? ""
        if !allowedSqlKeywords.contains(firstWord) {
            warnings.append("SQL query starts with unusual keyword: \(firstWord)")
        }
        
        logger.info("✅ [\(validationId)] SQL query validation passed")
        
        return ValidationResult(
            isValid: true,
            validationId: validationId,
            timestamp: Date(),
            warnings: warnings,
            operation: "SQL_VALIDATION"
        )
    }
    
    // MARK: - Parameter Validation
    
    private func validateParameters(parameters: [String: Any], validationId: String) -> ValidationResult {
        logger.info("🔍 [\(validationId)] Validating \(parameters.count) parameters")
        
        var warnings: [String] = []
        var errors: [String] = []
        
        for (key, value) in parameters {
            // Validate parameter key
            if key.isEmpty {
                errors.append("Empty parameter key")
                continue
            }
            
            if key.count > 100 {
                warnings.append("Parameter key '\(key)' is very long")
            }
            
            // Validate parameter value based on type
            switch value {
            case let stringValue as String:
                if stringValue.count > maxStringLength {
                    warnings.append("Parameter '\(key)' string value is very long (\(stringValue.count) characters)")
                }
                
                // Check for potential SQL injection in string values
                if stringValue.contains("'") && !stringValue.contains("''") {
                    warnings.append("Parameter '\(key)' contains unescaped single quotes")
                }
                
            case let intValue as Int:
                if intValue < 0 {
                    warnings.append("Parameter '\(key)' has negative integer value: \(intValue)")
                }
                
            case let doubleValue as Double:
                if doubleValue.isNaN || doubleValue.isInfinite {
                    errors.append("Parameter '\(key)' has invalid double value: \(doubleValue)")
                }
                
            case is Bool:
                // Boolean values are always valid
                break
                
            case let dataValue as Data:
                if dataValue.count > maxJsonLength {
                    warnings.append("Parameter '\(key)' data value is very large (\(dataValue.count) bytes)")
                }
                
            case is Date:
                // Date values are always valid
                break
                
            case let arrayValue as [Any]:
                if arrayValue.count > 1000 {
                    warnings.append("Parameter '\(key)' array has many items (\(arrayValue.count))")
                }
                
            case let dictValue as [String: Any]:
                if dictValue.count > 100 {
                    warnings.append("Parameter '\(key)' dictionary has many items (\(dictValue.count))")
                }
                
            case Optional<Any>.none:
                // Nil values are valid
                break
                
            default:
                warnings.append("Parameter '\(key)' has unexpected type: \(type(of: value))")
            }
        }
        
        if !errors.isEmpty {
            logger.error("❌ [\(validationId)] Parameter validation failed: \(errors.joined(separator: ", "))")
            return ValidationResult(
                isValid: false,
                validationId: validationId,
                timestamp: Date(),
                errors: errors,
                warnings: warnings,
                operation: "PARAMETER_VALIDATION"
            )
        }
        
        logger.info("✅ [\(validationId)] Parameter validation passed")
        
        return ValidationResult(
            isValid: true,
            validationId: validationId,
            timestamp: Date(),
            warnings: warnings,
            operation: "PARAMETER_VALIDATION"
        )
    }
    
    // MARK: - Data Object Validation
    
    private func validateDataObject(data: Any, operation: String, validationId: String) -> ValidationResult {
        logger.info("🔍 [\(validationId)] Validating data object for operation: \(operation)")
        
        var warnings: [String] = []
        var errors: [String] = []
        
        switch operation {
        case "SAVE_CONTACT":
            if let contact = data as? Contact {
                let contactValidation = validateContact(contact: contact, validationId: validationId)
                warnings.append(contentsOf: contactValidation.warnings)
                errors.append(contentsOf: contactValidation.errors)
            } else {
                errors.append("Expected Contact object for SAVE_CONTACT operation")
            }
            
        case "UPDATE_GROUP", "CREATE_GROUP":
            if let group = data as? ContactGroup {
                let groupValidation = validateGroup(group: group, validationId: validationId)
                warnings.append(contentsOf: groupValidation.warnings)
                errors.append(contentsOf: groupValidation.errors)
            } else {
                errors.append("Expected ContactGroup object for GROUP operation")
            }
            
        case "SAVE_INVITE", "UPDATE_INVITE":
            if let invite = data as? Invite {
                let inviteValidation = validateInvite(invite: invite, validationId: validationId)
                warnings.append(contentsOf: inviteValidation.warnings)
                errors.append(contentsOf: inviteValidation.errors)
            } else {
                errors.append("Expected Invite object for INVITE operation")
            }
            
        case "SAVE_BATCH_MESSAGE":
            if let batchMessage = data as? BatchMessage {
                let batchValidation = validateBatchMessage(batchMessage: batchMessage, validationId: validationId)
                warnings.append(contentsOf: batchValidation.warnings)
                errors.append(contentsOf: batchValidation.errors)
            } else {
                errors.append("Expected BatchMessage object for BATCH_MESSAGE operation")
            }
            
        default:
            warnings.append("Unknown operation type for data validation: \(operation)")
        }
        
        if !errors.isEmpty {
            logger.error("❌ [\(validationId)] Data validation failed: \(errors.joined(separator: ", "))")
            return ValidationResult(
                isValid: false,
                validationId: validationId,
                timestamp: Date(),
                errors: errors,
                warnings: warnings,
                operation: "DATA_VALIDATION"
            )
        }
        
        logger.info("✅ [\(validationId)] Data validation passed")
        
        return ValidationResult(
            isValid: true,
            validationId: validationId,
            timestamp: Date(),
            warnings: warnings,
            operation: "DATA_VALIDATION"
        )
    }
    
    // MARK: - Entity-Specific Validation
    
    private func validateContact(contact: Contact, validationId: String) -> ValidationResult {
        var warnings: [String] = []
        var errors: [String] = []
        
        // Validate phone number
        if contact.phone.isEmpty {
            errors.append("Contact phone number is empty")
        } else if !isValidPhoneNumber(contact.phone) {
            warnings.append("Contact phone number format may be invalid: \(contact.phone)")
        }
        
        // Validate name
        if contact.name.isEmpty {
            warnings.append("Contact name is empty")
        } else if contact.name.count > 200 {
            warnings.append("Contact name is very long (\(contact.name.count) characters)")
        }
        
        // Validate email if present
        if let email = contact.email, !email.isEmpty {
            if !isValidEmail(email) {
                warnings.append("Contact email format may be invalid: \(email)")
            }
        }
        
        // Validate notes length
        if let notes = contact.notes, notes.count > maxStringLength {
            warnings.append("Contact notes are very long (\(notes.count) characters)")
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            validationId: validationId,
            timestamp: Date(),
            errors: errors,
            warnings: warnings,
            operation: "CONTACT_VALIDATION"
        )
    }
    
    private func validateGroup(group: ContactGroup, validationId: String) -> ValidationResult {
        var warnings: [String] = []
        var errors: [String] = []
        
        // Validate group name
        if group.name.isEmpty {
            errors.append("Group name is empty")
        } else if group.name.count > 200 {
            warnings.append("Group name is very long (\(group.name.count) characters)")
        }
        
        // Validate member phones
        if group.memberPhones.isEmpty {
            warnings.append("Group has no members")
        } else if group.memberPhones.count > 1000 {
            warnings.append("Group has many members (\(group.memberPhones.count))")
        }
        
        // Validate canvases
        if group.canvases.count > 100 {
            warnings.append("Group has many canvases (\(group.canvases.count))")
        }
        
        // Validate linked group IDs
        if group.linkedGroupIDs.count > 50 {
            warnings.append("Group has many linked groups (\(group.linkedGroupIDs.count))")
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            validationId: validationId,
            timestamp: Date(),
            errors: errors,
            warnings: warnings,
            operation: "GROUP_VALIDATION"
        )
    }
    
    private func validateInvite(invite: Invite, validationId: String) -> ValidationResult {
        var warnings: [String] = []
        var errors: [String] = []
        
        // Validate title
        if invite.title.isEmpty {
            errors.append("Invite title is empty")
        } else if invite.title.count > 500 {
            warnings.append("Invite title is very long (\(invite.title.count) characters)")
        }
        
        // Validate description length
        if let description = invite.description, description.count > maxStringLength {
            warnings.append("Invite description is very long (\(description.count) characters)")
        }
        
        // Validate phone numbers
        if let toPhone = invite.toPhone, !toPhone.isEmpty && !isValidPhoneNumber(toPhone) {
            warnings.append("Invite 'to' phone number format may be invalid: \(toPhone)")
        }
        
        if let fromPhone = invite.fromPhone, !fromPhone.isEmpty && !isValidPhoneNumber(fromPhone) {
            warnings.append("Invite 'from' phone number format may be invalid: \(fromPhone)")
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            validationId: validationId,
            timestamp: Date(),
            errors: errors,
            warnings: warnings,
            operation: "INVITE_VALIDATION"
        )
    }
    
    private func validateBatchMessage(batchMessage: BatchMessage, validationId: String) -> ValidationResult {
        var warnings: [String] = []
        var errors: [String] = []
        
        // Validate message template
        if batchMessage.messageTemplate.isEmpty {
            errors.append("Batch message template is empty")
        } else if batchMessage.messageTemplate.count > maxStringLength {
            warnings.append("Batch message template is very long (\(batchMessage.messageTemplate.count) characters)")
        }
        
        // Validate recipients
        if batchMessage.recipients.isEmpty {
            errors.append("Batch message has no recipients")
        } else if batchMessage.recipients.count > 10000 {
            warnings.append("Batch message has many recipients (\(batchMessage.recipients.count))")
        }
        
        // Validate recipient data
        for (index, recipient) in batchMessage.recipients.enumerated() {
            if recipient.phone.isEmpty {
                errors.append("Recipient \(index) has empty phone number")
            } else if !isValidPhoneNumber(recipient.phone) {
                warnings.append("Recipient \(index) phone number format may be invalid: \(recipient.phone)")
            }
        }
        
        return ValidationResult(
            isValid: errors.isEmpty,
            validationId: validationId,
            timestamp: Date(),
            errors: errors,
            warnings: warnings,
            operation: "BATCH_MESSAGE_VALIDATION"
        )
    }
    
    // MARK: - Helper Functions
    
    private func isValidPhoneNumber(_ phone: String) -> Bool {
        // Basic phone number validation - can be enhanced
        let phoneRegex = "^[+]?[0-9\\s\\-\\(\\)]{7,20}$"
        return NSPredicate(format: "SELF MATCHES %@", phoneRegex).evaluate(with: phone)
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: email)
    }
    
    // MARK: - Logging Functions
    
    private func logIncomingData(validationId: String, operation: String, data: Any?, parameters: [String: Any]) {
        logger.info("📥 [\(validationId)] Incoming data for operation: \(operation)")
        
        // Log parameters
        if !parameters.isEmpty {
            logger.info("📥 [\(validationId)] Parameters (\(parameters.count)):")
            for (key, value) in parameters {
                let valueDescription = describeValue(value)
                logger.info("📥 [\(validationId)]   \(key): \(valueDescription)")
            }
        }
        
        // Log data object
        if let data = data {
            let dataDescription = describeDataObject(data)
            logger.info("📥 [\(validationId)] Data object: \(dataDescription)")
        }
    }
    
    private func logSQLExecution(validationId: String, operation: String, query: String, parameters: [String: Any]) {
        logger.info("🚀 [\(validationId)] Executing SQL for operation: \(operation)")
        logger.info("🚀 [\(validationId)] SQL Query: \(query)")
        
        if !parameters.isEmpty {
            logger.info("🚀 [\(validationId)] Bound Parameters:")
            for (key, value) in parameters {
                let valueDescription = describeValue(value)
                logger.info("🚀 [\(validationId)]   \(key): \(valueDescription)")
            }
        }
        
        // Log to database logger as well
        databaseLogger.logDatabaseOperation(
            operation: "SQL_VALIDATION_\(operation)",
            details: "Validated SQL execution for \(operation) with \(parameters.count) parameters",
            success: true
        )
    }
    
    private func describeValue(_ value: Any) -> String {
        switch value {
        case let stringValue as String:
            let truncated = stringValue.count > 100 ? String(stringValue.prefix(100)) + "..." : stringValue
            return "String(\(stringValue.count) chars): '\(truncated)'"
        case let intValue as Int:
            return "Int: \(intValue)"
        case let doubleValue as Double:
            return "Double: \(doubleValue)"
        case let boolValue as Bool:
            return "Bool: \(boolValue)"
        case let dataValue as Data:
            return "Data(\(dataValue.count) bytes)"
        case let dateValue as Date:
            return "Date: \(dateValue)"
        case let arrayValue as [Any]:
            return "Array(\(arrayValue.count) items)"
        case let dictValue as [String: Any]:
            return "Dictionary(\(dictValue.count) keys)"
        case Optional<Any>.none:
            return "nil"
        default:
            return "\(type(of: value)): \(value)"
        }
    }
    
    private func describeDataObject(_ data: Any) -> String {
        switch data {
        case let contact as Contact:
            return "Contact(name: '\(contact.name)', phone: '\(contact.phone)', email: \(contact.email ?? "nil"))"
        case let group as ContactGroup:
            return "ContactGroup(name: '\(group.name)', members: \(group.memberPhones.count), canvases: \(group.canvases.count))"
        case let invite as Invite:
            return "Invite(title: '\(invite.title)', status: \(invite.completionStatus.rawValue))"
        case let batchMessage as BatchMessage:
            return "BatchMessage(template: '\(String(batchMessage.messageTemplate.prefix(50)))...', recipients: \(batchMessage.recipients.count))"
        default:
            return "\(type(of: data))"
        }
    }
}

// MARK: - Validation Result

struct ValidationResult {
    let isValid: Bool
    let validationId: String
    let timestamp: Date
    let errors: [String]
    let warnings: [String]
    let operation: String
    
    init(isValid: Bool, validationId: String, timestamp: Date, errors: [String] = [], warnings: [String] = [], operation: String) {
        self.isValid = isValid
        self.validationId = validationId
        self.timestamp = timestamp
        self.errors = errors
        self.warnings = warnings
        self.operation = operation
    }
}

// MARK: - Safe SQL Execution Wrapper

extension SQLValidationService {
    
    /// Safely executes SQL with validation and comprehensive logging
    /// - Parameters:
    ///   - operation: The operation being performed
    ///   - query: The SQL query string
    ///   - database: The SQLite database pointer
    ///   - parameters: Parameters to bind to the query
    ///   - data: The data object being saved
    /// - Returns: SQLExecutionResult with success status and details
    func executeSQLWithValidation(
        operation: String,
        query: String,
        database: OpaquePointer?,
        parameters: [String: Any] = [:],
        data: Any? = nil
    ) -> SQLExecutionResult {
        
        // Validate before execution
        let validation = validateSQLOperation(
            operation: operation,
            query: query,
            parameters: parameters,
            data: data
        )
        
        if !validation.isValid {
            logger.error("❌ SQL execution blocked due to validation failure")
            return SQLExecutionResult(
                success: false,
                operation: operation,
                validationId: validation.validationId,
                error: "Validation failed: \(validation.errors.joined(separator: ", "))",
                warnings: validation.warnings
            )
        }
        
        // Execute the SQL
        return executeValidatedSQL(
            operation: operation,
            query: query,
            database: database,
            parameters: parameters,
            validationId: validation.validationId,
            warnings: validation.warnings
        )
    }
    
    private func executeValidatedSQL(
        operation: String,
        query: String,
        database: OpaquePointer?,
        parameters: [String: Any],
        validationId: String,
        warnings: [String]
    ) -> SQLExecutionResult {
        
        guard let db = database else {
            logger.error("❌ [\(validationId)] Database connection is nil")
            return SQLExecutionResult(
                success: false,
                operation: operation,
                validationId: validationId,
                error: "Database connection is nil",
                warnings: warnings
            )
        }
        
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        
        if prepareResult != SQLITE_OK {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            logger.error("❌ [\(validationId)] Failed to prepare SQL statement: \(errorMessage)")
            return SQLExecutionResult(
                success: false,
                operation: operation,
                validationId: validationId,
                error: "Failed to prepare statement: \(errorMessage)",
                warnings: warnings
            )
        }
        
        // Bind parameters
        let bindResult = bindParameters(statement: statement, parameters: parameters, validationId: validationId)
        if !bindResult.success {
            sqlite3_finalize(statement)
            return SQLExecutionResult(
                success: false,
                operation: operation,
                validationId: validationId,
                error: bindResult.error ?? "Parameter binding failed",
                warnings: warnings
            )
        }
        
        // Execute the statement
        let stepResult = sqlite3_step(statement)
        let success = stepResult == SQLITE_DONE
        
        if success {
            logger.info("✅ [\(validationId)] SQL execution completed successfully")
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            logger.error("❌ [\(validationId)] SQL execution failed: \(errorMessage)")
        }
        
        sqlite3_finalize(statement)
        
        return SQLExecutionResult(
            success: success,
            operation: operation,
            validationId: validationId,
            error: success ? nil : "SQL execution failed",
            warnings: warnings
        )
    }
    
    private func bindParameters(statement: OpaquePointer?, parameters: [String: Any], validationId: String) -> (success: Bool, error: String?) {
        // Note: This is a simplified parameter binding implementation
        // In a real implementation, you'd need to map parameter names to their positions
        // and handle different data types appropriately
        
        for (index, (_, value)) in parameters.enumerated() {
            let parameterIndex = Int32(index + 1) // SQLite parameters are 1-indexed
            
            switch value {
            case let stringValue as String:
                sqlite3_bind_text(statement, parameterIndex, stringValue, -1, nil)
            case let intValue as Int:
                sqlite3_bind_int(statement, parameterIndex, Int32(intValue))
            case let doubleValue as Double:
                sqlite3_bind_double(statement, parameterIndex, doubleValue)
            case let boolValue as Bool:
                sqlite3_bind_int(statement, parameterIndex, boolValue ? 1 : 0)
            case let dataValue as Data:
                let _ = dataValue.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, parameterIndex, bytes.baseAddress, Int32(dataValue.count), nil)
                }
            case Optional<Any>.none:
                sqlite3_bind_null(statement, parameterIndex)
            default:
                // Convert to string as fallback
                let stringValue = String(describing: value)
                sqlite3_bind_text(statement, parameterIndex, stringValue, -1, nil)
            }
        }
        
        return (success: true, error: nil)
    }
}

// MARK: - SQL Execution Result

struct SQLExecutionResult {
    let success: Bool
    let operation: String
    let validationId: String
    let error: String?
    let warnings: [String]
    let timestamp: Date
    
    init(success: Bool, operation: String, validationId: String, error: String? = nil, warnings: [String] = []) {
        self.success = success
        self.operation = operation
        self.validationId = validationId
        self.error = error
        self.warnings = warnings
        self.timestamp = Date()
    }
}
