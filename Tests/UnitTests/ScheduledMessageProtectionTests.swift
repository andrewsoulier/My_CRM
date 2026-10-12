import XCTest
@testable import My_CRM

/// Tests to verify that scheduled messages are properly marked as sent and cannot be resent
@MainActor
class ScheduledMessageProtectionTests: XCTestCase {
    
    var dataProvider: SQLiteDataProvider!
    var batchMessageService: BatchMessageService!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a fresh data provider for testing
        dataProvider = SQLiteDataProvider()
        await dataProvider.initializeDatabase()
        
        // Configure the batch message service
        batchMessageService = BatchMessageService.shared
        batchMessageService.configure(with: dataProvider)
    }
    
    override func tearDown() async throws {
        // Clean up test data
        dataProvider = nil
        try await super.tearDown()
    }
    
    // MARK: - Test Cases
    
    /// Test that a scheduled message changes status after being sent
    func testScheduledMessageStatusChangesAfterSending() async throws {
        // Create a scheduled message in the past (should be sent immediately)
        let pastTime = Date().addingTimeInterval(-60) // 1 minute ago
        let testRecipient = BatchRecipient(
            phone: "+15551234567",
            name: "Test User",
            email: "test@example.com",
            fieldValues: ["name": "Test User"]
        )
        
        let message = BatchMessage(
            messageTemplate: "Hello @name, this is a test message.",
            recipients: [testRecipient],
            scheduledTime: pastTime,
            notifyWhenSent: false
        )
        
        // Save the message to the database
        await dataProvider.saveBatchMessage(message)
        
        // Verify it's in scheduled status
        XCTAssertEqual(message.status, .scheduled, "Initial status should be .scheduled")
        
        // Check if it appears in scheduled messages query
        let scheduledMessages = dataProvider.getScheduledBatchMessages()
        XCTAssertTrue(
            scheduledMessages.contains(where: { $0.id == message.id }),
            "Message should appear in scheduled messages before sending"
        )
        
        // Process the message
        await batchMessageService.processBatchMessage(message)
        
        // Retrieve the updated message from the database
        let updatedMessage = dataProvider.batchMessages.first(where: { $0.id == message.id })
        
        // Verify the status changed
        XCTAssertNotEqual(updatedMessage?.status, .scheduled, "Status should no longer be .scheduled after sending")
        XCTAssertTrue(
            updatedMessage?.status == .completed || updatedMessage?.status == .failed,
            "Status should be either .completed or .failed after sending"
        )
        
        // Verify it has a completion time
        XCTAssertNotNil(updatedMessage?.completedTime, "Message should have a completion time")
    }
    
    /// Test that a completed message does NOT appear in scheduled messages query
    func testCompletedMessageNotReturnedByScheduledQuery() async throws {
        // Create a scheduled message
        let futureTime = Date().addingTimeInterval(3600) // 1 hour from now
        let testRecipient = BatchRecipient(
            phone: "+15551234567",
            name: "Test User",
            email: "test@example.com",
            fieldValues: ["name": "Test User"]
        )
        
        var message = BatchMessage(
            messageTemplate: "Hello @name, this is a test message.",
            recipients: [testRecipient],
            scheduledTime: futureTime,
            notifyWhenSent: false
        )
        
        // Save the message
        await dataProvider.saveBatchMessage(message)
        
        // Verify it appears in scheduled messages
        var scheduledMessages = dataProvider.getScheduledBatchMessages()
        XCTAssertTrue(
            scheduledMessages.contains(where: { $0.id == message.id }),
            "Message should appear in scheduled messages before completion"
        )
        
        // Manually mark as completed (simulating successful send)
        message.status = .completed
        message.completedTime = Date()
        await dataProvider.saveBatchMessage(message)
        
        // Verify it NO LONGER appears in scheduled messages
        scheduledMessages = dataProvider.getScheduledBatchMessages()
        XCTAssertFalse(
            scheduledMessages.contains(where: { $0.id == message.id }),
            "Completed message should NOT appear in scheduled messages query"
        )
    }
    
    /// Test that a failed message does NOT appear in scheduled messages query
    func testFailedMessageNotReturnedByScheduledQuery() async throws {
        // Create a scheduled message
        let futureTime = Date().addingTimeInterval(3600) // 1 hour from now
        let testRecipient = BatchRecipient(
            phone: "+15551234567",
            name: "Test User",
            email: "test@example.com",
            fieldValues: ["name": "Test User"]
        )
        
        var message = BatchMessage(
            messageTemplate: "Hello @name, this is a test message.",
            recipients: [testRecipient],
            scheduledTime: futureTime,
            notifyWhenSent: false
        )
        
        // Save the message
        await dataProvider.saveBatchMessage(message)
        
        // Verify it appears in scheduled messages
        var scheduledMessages = dataProvider.getScheduledBatchMessages()
        XCTAssertTrue(
            scheduledMessages.contains(where: { $0.id == message.id }),
            "Message should appear in scheduled messages before failure"
        )
        
        // Manually mark as failed (simulating send failure)
        message.status = .failed
        message.completedTime = Date()
        message.failedCount = 1
        message.failedContacts = ["+15551234567": "Test error"]
        await dataProvider.saveBatchMessage(message)
        
        // Verify it NO LONGER appears in scheduled messages
        scheduledMessages = dataProvider.getScheduledBatchMessages()
        XCTAssertFalse(
            scheduledMessages.contains(where: { $0.id == message.id }),
            "Failed message should NOT appear in scheduled messages query"
        )
    }
    
    /// Test that checkScheduledMessages only processes messages with .scheduled status
    func testCheckScheduledMessagesIgnoresNonScheduledStatuses() async throws {
        let pastTime = Date().addingTimeInterval(-60) // 1 minute ago
        let testRecipient = BatchRecipient(
            phone: "+15551234567",
            name: "Test User",
            email: "test@example.com",
            fieldValues: ["name": "Test User"]
        )
        
        // Create a message with scheduled time in the past but status = completed
        var completedMessage = BatchMessage(
            messageTemplate: "Hello @name",
            recipients: [testRecipient],
            scheduledTime: pastTime,
            notifyWhenSent: false
        )
        completedMessage.status = .completed
        completedMessage.completedTime = Date()
        
        await dataProvider.saveBatchMessage(completedMessage)
        
        // Get scheduled messages - should be empty
        let scheduledMessages = dataProvider.getScheduledBatchMessages()
        XCTAssertFalse(
            scheduledMessages.contains(where: { $0.id == completedMessage.id }),
            "Completed message should not be returned even if scheduled time has passed"
        )
    }
    
    /// Test recovery behavior for stuck messages that were partially sent
    func testStuckMessageRecoveryPreventsDuplicates() async throws {
        // Create a message that appears to be stuck in "sending" status
        let testRecipient = BatchRecipient(
            phone: "+15551234567",
            name: "Test User",
            email: "test@example.com",
            fieldValues: ["name": "Test User"]
        )
        
        var stuckMessage = BatchMessage(
            messageTemplate: "Hello @name",
            recipients: [testRecipient],
            scheduledTime: Date().addingTimeInterval(-60),
            notifyWhenSent: false
        )
        
        // Simulate a crash scenario: status is "sending" and some messages were sent
        stuckMessage.status = .sending
        stuckMessage.sentCount = 5  // Some messages were sent before crash
        
        await dataProvider.saveBatchMessage(stuckMessage)
        
        // Trigger recovery (normally happens on app startup)
        // This is done in BatchMessageService.configure -> recoverStuckMessages
        // We'll simulate it by re-initializing the service
        let newBatchService = BatchMessageService.shared
        newBatchService.configure(with: dataProvider)
        
        // Wait a moment for recovery to complete
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Retrieve the recovered message
        let recoveredMessage = dataProvider.batchMessages.first(where: { $0.id == stuckMessage.id })
        
        // Verify it was marked as failed to prevent duplicates
        XCTAssertEqual(
            recoveredMessage?.status,
            .failed,
            "Stuck message with sent messages should be marked as failed to prevent duplicates"
        )
        XCTAssertNotNil(recoveredMessage?.completedTime, "Should have completion time")
    }
}

