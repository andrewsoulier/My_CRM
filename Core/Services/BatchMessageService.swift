import Foundation
import UserNotifications

// MARK: - Error Categories

enum MessageSendErrorCategory {
    case authorizationDenied
    case messagesNotRunning
    case networkError
    case invalidRecipient
    case rateLimited
    case timeout
    case unknown
    
    var shouldRetry: Bool {
        switch self {
        case .authorizationDenied, .invalidRecipient:
            return false // Don't retry these
        case .messagesNotRunning, .networkError, .rateLimited, .timeout, .unknown:
            return true // Can retry these
        }
    }
    
    var retryDelay: TimeInterval {
        switch self {
        case .rateLimited:
            return 5.0 // 5 seconds for rate limiting
        case .networkError:
            return 2.0 // 2 seconds for network issues
        case .timeout:
            return 3.0 // 3 seconds for timeouts
        default:
            return 1.0 // 1 second default
        }
    }
    
    var userMessage: String {
        switch self {
        case .authorizationDenied:
            return "Permission denied. Please grant Messages authorization in System Settings."
        case .messagesNotRunning:
            return "Messages app is not running. Please launch Messages and try again."
        case .networkError:
            return "Network or iMessage service issue. The message will be retried."
        case .invalidRecipient:
            return "Invalid phone number or recipient."
        case .rateLimited:
            return "Sending too fast. Messages are being rate limited."
        case .timeout:
            return "Message send timed out. Will retry."
        case .unknown:
            return "An unknown error occurred."
        }
    }
    
    static func categorize(error: String) -> MessageSendErrorCategory {
        let lowercased = error.lowercased()
        
        // Authorization errors
        if lowercased.contains("not authorized") || 
           lowercased.contains("-1743") ||
           lowercased.contains("permission") {
            return .authorizationDenied
        }
        
        // Messages not running
        if lowercased.contains("application isn't running") ||
           lowercased.contains("messages is not running") ||
           lowercased.contains("not running") {
            return .messagesNotRunning
        }
        
        // Network/iMessage errors
        if lowercased.contains("network") ||
           lowercased.contains("imessage") ||
           lowercased.contains("not signed in") ||
           lowercased.contains("connection") {
            return .networkError
        }
        
        // Invalid recipient
        if lowercased.contains("buddy") ||
           lowercased.contains("invalid") ||
           lowercased.contains("not found") {
            return .invalidRecipient
        }
        
        // Rate limiting
        if lowercased.contains("rate") ||
           lowercased.contains("too many") ||
           lowercased.contains("throttle") {
            return .rateLimited
        }
        
        // Timeout
        if lowercased.contains("timeout") ||
           lowercased.contains("timed out") {
            return .timeout
        }
        
        return .unknown
    }
}

// MARK: - Template Engine
struct TemplateEngine {
    static let logger = LogManager.shared
    
    static func process(template: String, chipMetadata: ChipMetadata?, fieldValues: [String: String]) -> String {
        var processedMessage = template
        
        logger.info("🔄 TemplateEngine: Input template: '\(template)'")
        logger.info("🔄 TemplateEngine: ChipMetadata: \(chipMetadata?.chips.count ?? 0) chips")
        logger.info("🔄 TemplateEngine: Field values: \(fieldValues)")
        
        // Use simple @field replacement since we now store templates as plain text with @field placeholders
        // ChipMetadata ranges are from the rich text (NSTextAttachment = 1 char), not the plain text template
        if let metadata = chipMetadata, !metadata.chips.isEmpty {
            logger.info("🔄 TemplateEngine: Using metadata-aware replacement for \(metadata.chips.count) chip(s)")
            
            for (index, chip) in metadata.chips.enumerated() {
                if chip.type == .contactField, let fieldName = chip.field {
                    let fieldPattern = "@\(fieldName)"
                    let fieldValue = fieldValues[fieldName] ?? ""
                    
                    logger.info("🔄 TemplateEngine: Chip \(index): Replacing '\(fieldPattern)' with '\(fieldValue)'")
                    let before = processedMessage
                    processedMessage = processedMessage.replacingOccurrences(of: fieldPattern, with: fieldValue)
                    
                    if before != processedMessage {
                        logger.info("   ✅ Replaced successfully")
                    } else {
                        logger.warning("   ⚠️ Pattern '\(fieldPattern)' not found in template")
                    }
                }
            }
            
            logger.info("✅ TemplateEngine: Processed with chip metadata. Final message: '\(processedMessage)'")
        } else {
            // Fallback to simple @field replacement if no chip metadata
            logger.info("🔄 TemplateEngine: Using simple @field replacement")
            for (field, value) in fieldValues {
                let fieldPattern = "@\(field)"
                processedMessage = processedMessage.replacingOccurrences(of: fieldPattern, with: value)
            }
            logger.info("✅ TemplateEngine: Processed with simple @field replacement.")
        }
        
        // Log any remaining @tokens
        let remainingTokens = findRemainingTokens(in: processedMessage)
        if !remainingTokens.isEmpty {
            logger.warning("⚠️ TemplateEngine: Unmatched @tokens remaining: \(remainingTokens.joined(separator: ", "))")
        }
        
        return processedMessage
    }
    
    private static func findRemainingTokens(in text: String) -> [String] {
        let pattern = "@(\\w+)"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
            return matches.map { (text as NSString).substring(with: $0.range) }
        } catch {
            logger.error("❌ TemplateEngine: Error finding remaining tokens: \(error)")
            return []
        }
    }
}

@MainActor
class BatchMessageService: ObservableObject {
    static let shared = BatchMessageService()
    
    var dataProvider: SQLiteDataProvider!
    private let logger = LogManager.shared
    
    // Processing state
    @Published var isProcessingMessages = false
    @Published var currentProcessingMessage: BatchMessage?
    @Published var processingProgress: Double = 0.0
    
    private var processingTimer: Timer?
    private var schedulingTimer: Timer?
    
    private init() {
        // Don't start scheduling timer in init - will be started when dataProvider is set
    }
    
    func configure(with dataProvider: SQLiteDataProvider) {
        self.dataProvider = dataProvider
        Task { @MainActor in
            await recoverStuckMessages()
        }
        startSchedulingTimer()
    }
    
    deinit {
        processingTimer?.invalidate()
        schedulingTimer?.invalidate()
    }
    
    // MARK: - Shutdown
    
    func shutdown() {
        logger.info("🛑 Shutting down BatchMessageService...")
        processingTimer?.invalidate()
        processingTimer = nil
        schedulingTimer?.invalidate()
        schedulingTimer = nil
        logger.info("✅ BatchMessageService shutdown complete")
    }
    
    // MARK: - Scheduling Timer
    
    private func startSchedulingTimer() {
        // Check for scheduled messages every minute
        schedulingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                await self.checkScheduledMessages()
            }
        }
    }
    
    // MARK: - Recovery
    
    private func recoverStuckMessages() async {
        logger.info("🔍 Checking for stuck messages from previous session...")
        
        // Find any messages that were stuck in 'sending' status
        let stuckMessages = dataProvider.batchMessages.filter { $0.status == .sending }
        
        if stuckMessages.isEmpty {
            logger.info("✅ No stuck messages found")
            return
        }
        
        logger.warning("⚠️ Found \(stuckMessages.count) message(s) stuck in 'sending' status")
        
        for var message in stuckMessages {
            // Check if any messages were actually sent
            if message.sentCount > 0 {
                // Some messages were sent before crash - mark as failed to prevent duplicates
                logger.warning("⚠️ Message \(message.id) had \(message.sentCount) messages sent before interruption - marking as failed to prevent duplicates")
                message.status = .failed
                message.completedTime = Date()
                await dataProvider.saveBatchMessage(message)
            } else {
                // No messages were sent - reset to scheduled or pending
                if let scheduledTime = message.scheduledTime, scheduledTime > Date() {
                    // Still in the future - reset to scheduled
                    logger.info("🔄 Resetting message \(message.id) back to 'scheduled' status")
                    message.status = .scheduled
                    await dataProvider.saveBatchMessage(message)
                } else if message.scheduledTime != nil {
                    // Scheduled time has passed - process now
                    logger.info("🔄 Processing overdue message \(message.id) that was stuck")
                    message.status = .scheduled
                    await dataProvider.saveBatchMessage(message)
                    await processBatchMessage(message)
                } else {
                    // Immediate send - reset to pending
                    logger.info("🔄 Resetting message \(message.id) back to 'pending' status")
                    message.status = .pending
                    await dataProvider.saveBatchMessage(message)
                }
            }
        }
        
        logger.info("✅ Stuck message recovery complete")
    }
    
    private func checkScheduledMessages() async {
        logger.info("🔍 Checking for scheduled messages...")
        
        let scheduledMessages = dataProvider.getScheduledBatchMessages()
        let now = Date()
        
        logger.info("📊 Found \(scheduledMessages.count) messages with .scheduled status")
        
        // Log all messages in the database for debugging
        let allMessages = dataProvider.batchMessages
        logger.info("📊 Total messages in database: \(allMessages.count)")
        let statusBreakdown = Dictionary(grouping: allMessages, by: { $0.status })
        for (status, messages) in statusBreakdown {
            logger.info("  - \(status.rawValue): \(messages.count)")
        }
        
        for message in scheduledMessages {
            if let scheduledTime = message.scheduledTime,
               scheduledTime <= now,
               message.status == .scheduled {
                logger.info("🕐 Starting scheduled message: \(message.id)")
                logger.info("  ⏰ Scheduled for: \(scheduledTime.formatted())")
                logger.info("  📝 Status: \(message.status.rawValue)")
                await processBatchMessage(message)
            } else {
                // Log why this message wasn't processed
                if let scheduledTime = message.scheduledTime {
                    if scheduledTime > now {
                        logger.info("⏸️ Message \(message.id) not due yet (scheduled for \(scheduledTime.formatted()))")
                    } else if message.status != .scheduled {
                        logger.warning("⚠️ Message \(message.id) has scheduledTime but status is \(message.status.rawValue), not .scheduled")
                    }
                } else {
                    logger.warning("⚠️ Message \(message.id) has .scheduled status but no scheduledTime")
                }
            }
        }
        
        logger.info("✅ Scheduled message check complete")
    }
    
    // MARK: - Message Processing
    
    func processBatchMessage(_ batchMessage: BatchMessage) async {
        logger.info("🔄 BatchMessageService: processBatchMessage called for ID: \(batchMessage.id)")
        logger.info("📊 BatchMessageService: Message has \(batchMessage.recipients.count) recipients")
        logger.info("📝 BatchMessageService: Message template: '\(batchMessage.messageTemplate)'")
        
        guard !isProcessingMessages else {
            logger.warning("⚠️ Already processing messages, skipping batch: \(batchMessage.id)")
            return
        }
        
        guard dataProvider != nil else {
            logger.error("❌ BatchMessageService: DataProvider is nil!")
            return
        }
        
        // MARK: - Pre-Send Validation
        logger.info("🔍 Performing pre-send validation...")
        
        // Check authorization and Messages app status
        let authManager = MessagesAuthorizationManager.shared
        let validationResult = await authManager.validateCanSendMessages()
        
        if !validationResult.canSend {
            logger.error("❌ Pre-send validation failed:")
            for issue in validationResult.issues where issue.severity == .error {
                logger.error("  - \(issue.title): \(issue.description)")
            }
            
            // Mark message as failed with validation error
            var updatedMessage = batchMessage
            updatedMessage.status = .failed
            updatedMessage.completedTime = Date()
            updatedMessage.failedCount = batchMessage.recipients.count
            
            // Add validation errors to error log
            for (index, recipient) in batchMessage.recipients.enumerated() {
                let errorMessage = validationResult.issues.first(where: { $0.severity == .error })?.description ?? "Pre-send validation failed"
                updatedMessage.failedContacts[recipient.phone] = errorMessage
                updatedMessage.errorLog.append(BatchError(
                    timestamp: Date(),
                    phone: recipient.phone,
                    error: errorMessage,
                    retryAttempt: 0
                ))
            }
            
            await dataProvider.saveBatchMessage(updatedMessage)
            logger.error("❌ Batch message \(batchMessage.id) failed pre-send validation")
            return
        }
        
        // Log any warnings
        for issue in validationResult.issues where issue.severity == .warning {
            logger.warning("⚠️ \(issue.title): \(issue.description)")
        }
        
        logger.info("✅ Pre-send validation passed")
        
        isProcessingMessages = true
        currentProcessingMessage = batchMessage
        processingProgress = 0.0
        
        logger.info("🚀 Starting batch message processing: \(batchMessage.id)")
        
        // Update status to sending
        var updatedMessage = batchMessage
        updatedMessage.status = .sending
        updatedMessage.sentCount = 0
        updatedMessage.failedCount = 0
        updatedMessage.failedContacts = [:]
        updatedMessage.errorLog = []
        
        logger.info("💾 BatchMessageService: Updating message status to 'sending'")
        await dataProvider.saveBatchMessage(updatedMessage)
        logger.info("✅ BatchMessageService: Message status updated in database")
        
        // Process each recipient with delay
        let totalRecipients = batchMessage.recipients.count
        var sentCount = 0
        var failedCount = 0
        var failedContacts: [String: String] = [:]
        var errorLog: [BatchError] = []
        
        for (index, recipient) in batchMessage.recipients.enumerated() {
            // Process message template with field replacement
            LogManager.shared.debug("🧩 Replacement: templateLen=\(batchMessage.messageTemplate.count) fields=\(Array(recipient.fieldValues.keys)) sample={name=\(recipient.fieldValues["name"] ?? ""), first=\(recipient.fieldValues["first_name"] ?? ""), last=\(recipient.fieldValues["last_name"] ?? "")} ")
            LogManager.shared.debug("📝 Template before processing: '\(batchMessage.messageTemplate)'")
            LogManager.shared.debug("🔧 ChipMetadata: \(batchMessage.chipMetadata?.chips.count ?? 0) chips")
            
            let personalizedMessage = TemplateEngine.process(
                template: batchMessage.messageTemplate,
                chipMetadata: batchMessage.chipMetadata,
                fieldValues: recipient.fieldValues
            )
            let snippet = String(personalizedMessage.prefix(120))
            LogManager.shared.debug("🧪 Personalized preview: \(snippet)")
            
            logger.info("📱 Sending message \(index + 1)/\(totalRecipients) to \(recipient.phone)")
            
            // Attempt to send message
            let sendResult = await sendMessage(to: recipient.phone, message: personalizedMessage)
            
            if sendResult.success {
                sentCount += 1
                logger.info("✅ Message sent successfully to \(recipient.phone)")
            } else {
                failedCount += 1
                failedContacts[recipient.phone] = sendResult.error ?? "Unknown error"
                errorLog.append(BatchError(
                    timestamp: Date(),
                    phone: recipient.phone,
                    error: sendResult.error ?? "Unknown error",
                    retryAttempt: 0
                ))
                logger.error("❌ Failed to send message to \(recipient.phone): \(sendResult.error ?? "Unknown error")")
            }
            
            // Update progress
            processingProgress = Double(index + 1) / Double(totalRecipients)
            
            // Update message in database
            updatedMessage.sentCount = sentCount
            updatedMessage.failedCount = failedCount
            updatedMessage.failedContacts = failedContacts
            updatedMessage.errorLog = errorLog
            await dataProvider.saveBatchMessage(updatedMessage)
            
            // Delay between messages (0.5 seconds)
            if index < batchMessage.recipients.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
        
        // Smart retry logic based on error categories
        if failedCount > 0 {
            logger.info("🔄 Analyzing \(failedCount) failed messages for smart retry...")
            
            let failedPhones = Array(failedContacts.keys)
            let failedRecipients = batchMessage.recipients.filter { failedPhones.contains($0.phone) }
            
            // Categorize errors and determine retry strategy
            var retriableRecipients: [(recipient: BatchRecipient, errorCategory: MessageSendErrorCategory, retryDelay: TimeInterval)] = []
            var nonRetriableRecipients: [BatchRecipient] = []
            
            for recipient in failedRecipients {
                if let errorString = failedContacts[recipient.phone] {
                    let category = MessageSendErrorCategory.categorize(error: errorString)
                    
                    if category.shouldRetry {
                        retriableRecipients.append((recipient, category, category.retryDelay))
                        logger.info("🔄 \(recipient.phone): \(category) - Will retry with \(category.retryDelay)s delay")
                    } else {
                        nonRetriableRecipients.append(recipient)
                        logger.warning("⏭️ \(recipient.phone): \(category) - Skipping retry")
                    }
                }
            }
            
            logger.info("📊 Retry strategy: \(retriableRecipients.count) retriable, \(nonRetriableRecipients.count) non-retriable")
            
            // Attempt retries with appropriate delays
            for (recipient, category, delay) in retriableRecipients {
                // Apply category-specific delay
                let delayNanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                
                let personalizedMessage = TemplateEngine.process(
                    template: batchMessage.messageTemplate,
                    chipMetadata: batchMessage.chipMetadata,
                    fieldValues: recipient.fieldValues
                )
                
                logger.info("🔄 Retrying message to \(recipient.phone) after \(delay)s delay (reason: \(category))")
                
                let retryResult = await sendMessage(to: recipient.phone, message: personalizedMessage)
                
                if retryResult.success {
                    sentCount += 1
                    failedCount -= 1
                    failedContacts.removeValue(forKey: recipient.phone)
                    
                    // Remove from error log
                    if let errorIndex = errorLog.firstIndex(where: { $0.phone == recipient.phone }) {
                        errorLog.remove(at: errorIndex)
                    }
                    
                    logger.info("✅ Retry successful for \(recipient.phone)")
                } else {
                    // Update error log with retry attempt
                    if let errorIndex = errorLog.firstIndex(where: { $0.phone == recipient.phone }) {
                        errorLog[errorIndex] = BatchError(
                            timestamp: Date(),
                            phone: recipient.phone,
                            error: retryResult.error ?? "Unknown error",
                            retryAttempt: 1
                        )
                    }
                    
                    let newCategory = MessageSendErrorCategory.categorize(error: retryResult.error ?? "Unknown error")
                    logger.error("❌ Retry failed for \(recipient.phone): \(newCategory) - \(retryResult.error ?? "Unknown error")")
                }
                
                // Update message after each retry
                updatedMessage.sentCount = sentCount
                updatedMessage.failedCount = failedCount
                updatedMessage.failedContacts = failedContacts
                updatedMessage.errorLog = errorLog
                await dataProvider.saveBatchMessage(updatedMessage)
            }
        }
        
        // Final status update
        updatedMessage.status = failedCount == 0 ? .completed : .failed
        updatedMessage.completedTime = Date()
        
        logger.info("💾 Saving final message status: \(updatedMessage.status.rawValue)")
        await dataProvider.saveBatchMessage(updatedMessage)
        
        // CRITICAL: Verify the status was saved to prevent re-queuing
        if let verifiedMessage = dataProvider.batchMessages.first(where: { $0.id == updatedMessage.id }) {
            logger.info("✅ VERIFIED: Message \(updatedMessage.id) status in database: \(verifiedMessage.status.rawValue)")
            logger.info("✅ VERIFIED: Completed time: \(verifiedMessage.completedTime?.formatted() ?? "nil")")
            
            if verifiedMessage.status == .scheduled {
                logger.error("🚨 CRITICAL ERROR: Message status is still .scheduled after save! This could cause duplicate sends!")
            } else {
                logger.info("✅ SUCCESS: Message will NOT be re-queued (status is \(verifiedMessage.status.rawValue), not .scheduled)")
            }
        } else {
            logger.error("❌ WARNING: Could not verify saved message in database!")
        }
        
        // Send notification if requested
        if batchMessage.notifyWhenSent {
            await sendCompletionNotification(
                sentCount: sentCount,
                failedCount: failedCount,
                totalCount: totalRecipients
            )
        }
        
        // Reset processing state
        isProcessingMessages = false
        currentProcessingMessage = nil
        processingProgress = 0.0
        
        logger.info("🏁 Batch message processing completed: \(sentCount) sent, \(failedCount) failed")
    }
    
    // MARK: - Message Sending
    
    private func sendMessage(to phone: String, message: String) async -> SendResult {
        let startTime = Date()
        logger.info("📤 Attempting to send message to \(phone)")
        logger.debug("   Message preview: \(String(message.prefix(50)))...")
        
        do {
            // Create AppleScript to send iMessage
            let script = createiMessageScript(phone: phone, message: message)
            logger.debug("   AppleScript created")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            try process.run()
            
            // Implement timeout handling
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds timeout
                if process.isRunning {
                    logger.warning("⚠️ AppleScript execution timeout for \(phone), terminating process")
                    process.terminate()
                }
            }
            
            process.waitUntilExit()
            timeoutTask.cancel()
            
            let duration = Date().timeIntervalSince(startTime)
            logger.debug("   Process completed in \(String(format: "%.2f", duration))s with status: \(process.terminationStatus)")
            
            if process.terminationStatus == 0 {
                logger.info("✅ Message sent successfully to \(phone) (took \(String(format: "%.2f", duration))s)")
                return SendResult(success: true, error: nil, errorCategory: nil)
            } else if process.terminationStatus == 15 { // SIGTERM from timeout
                logger.error("❌ Message send timed out for \(phone)")
                return SendResult(success: false, error: "Message send timed out after 30 seconds", errorCategory: .timeout)
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown AppleScript error"
                
                logger.error("❌ AppleScript failed for \(phone):")
                logger.error("   Status code: \(process.terminationStatus)")
                logger.error("   Error: \(errorString)")
                
                // Categorize the error
                let category = MessageSendErrorCategory.categorize(error: errorString)
                logger.error("   Category: \(category)")
                
                // Check if it's an iMessage failure, try SMS fallback
                if category == .networkError && (errorString.contains("iMessage") || errorString.contains("not signed in")) {
                    logger.info("📱 iMessage failed for \(phone), attempting SMS fallback")
                    return await sendSMS(to: phone, message: message)
                }
                
                return SendResult(success: false, error: errorString, errorCategory: category)
            }
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logger.error("❌ Failed to execute AppleScript for \(phone): \(error)")
            logger.error("   Duration before failure: \(String(format: "%.2f", duration))s")
            return SendResult(success: false, error: error.localizedDescription, errorCategory: .unknown)
        }
    }
    
    private func sendSMS(to phone: String, message: String) async -> SendResult {
        let startTime = Date()
        logger.info("📲 Attempting SMS fallback for \(phone)")
        
        // SMS fallback using Messages app
        let script = createSMSScript(phone: phone, message: message)
        
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            try process.run()
            
            // Implement timeout for SMS too
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds timeout
                if process.isRunning {
                    logger.warning("⚠️ SMS send timeout for \(phone), terminating process")
                    process.terminate()
                }
            }
            
            process.waitUntilExit()
            timeoutTask.cancel()
            
            let duration = Date().timeIntervalSince(startTime)
            
            if process.terminationStatus == 0 {
                logger.info("✅ SMS sent successfully to \(phone) (took \(String(format: "%.2f", duration))s)")
                return SendResult(success: true, error: nil, errorCategory: nil)
            } else if process.terminationStatus == 15 {
                logger.error("❌ SMS send timed out for \(phone)")
                return SendResult(success: false, error: "SMS send timed out after 30 seconds", errorCategory: .timeout)
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown SMS error"
                let category = MessageSendErrorCategory.categorize(error: errorString)
                
                logger.error("❌ SMS send failed for \(phone): \(errorString)")
                logger.error("   Category: \(category)")
                
                return SendResult(success: false, error: errorString, errorCategory: category)
            }
        } catch {
            logger.error("❌ Failed to execute SMS script for \(phone): \(error)")
            return SendResult(success: false, error: error.localizedDescription, errorCategory: .unknown)
        }
    }
    
    private func createiMessageScript(phone: String, message: String) -> String {
        let escapedMessage = message.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Messages"
            send "\(escapedMessage)" to buddy "\(phone)"
        end tell
        """
    }
    
    private func createSMSScript(phone: String, message: String) -> String {
        let escapedMessage = message.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Messages"
            send "\(escapedMessage)" to buddy "\(phone)"
        end tell
        """
    }
    
    // MARK: - Message Template Processing
    
    private func processMessageTemplate(_ template: String, with fieldValues: [String: String]) -> String {
        var processedMessage = template
        
        // Replace @field references with actual values
        for (field, value) in fieldValues {
            let fieldPattern = "@\(field)"
            processedMessage = processedMessage.replacingOccurrences(of: fieldPattern, with: value)
        }
        
        return processedMessage
    }

    // MARK: - Shared Template Processor (for preview and send paths)
    static func processTemplate(_ template: String, with fieldValues: [String: String]) -> String {
        var processedMessage = template
        // Replace tokens based on the actual fieldValues map to avoid divergence
        for (field, value) in fieldValues {
            let fieldPattern = "@\(field)"
            processedMessage = processedMessage.replacingOccurrences(of: fieldPattern, with: value)
        }

        // Log any unmatched tokens to help diagnose missing fields
        do {
            let regex = try NSRegularExpression(pattern: "@\\w+", options: [])
            let range = NSRange(location: 0, length: processedMessage.utf16.count)
            let matches = regex.matches(in: processedMessage, options: [], range: range)
            if !matches.isEmpty {
                let remaining = matches.compactMap { match -> String? in
                    guard let swiftRange = Range(match.range, in: processedMessage) else { return nil }
                    return String(processedMessage[swiftRange])
                }
                LogManager.shared.warning("⚠️ Unmatched tokens after processing: \(remaining)")
            }
        } catch {
            LogManager.shared.error("❌ Regex error when checking unmatched tokens: \(error)")
        }

        return processedMessage
    }
    
    // MARK: - Notifications
    
    private func sendCompletionNotification(sentCount: Int, failedCount: Int, totalCount: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Quick Send Complete"
        
        if failedCount == 0 {
            content.body = "Successfully sent \(sentCount) messages"
            content.sound = .default
        } else {
            content.body = "Sent \(sentCount) messages, \(failedCount) failed"
            content.sound = .defaultCritical
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Send immediately
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logger.error("Failed to send notification: \(error)")
        }
    }
    
    // MARK: - Public Interface
    
    func sendBatchMessageNow(_ batchMessage: BatchMessage) async {
        await processBatchMessage(batchMessage)
    }
    
    func cancelBatchMessage(_ messageId: UUID) async {
        // Find and cancel the message
        if let index = dataProvider.batchMessages.firstIndex(where: { $0.id == messageId }) {
            var message = dataProvider.batchMessages[index]
            
            if message.status == .scheduled || message.status == .pending {
                message.status = .cancelled
                await dataProvider.saveBatchMessage(message)
                logger.info("🚫 Cancelled batch message: \(messageId)")
            }
        }
    }
}

// MARK: - Supporting Types

struct SendResult {
    let success: Bool
    let error: String?
    let errorCategory: MessageSendErrorCategory?
}
