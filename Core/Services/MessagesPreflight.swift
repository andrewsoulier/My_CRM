import Foundation
import AppKit

@MainActor
enum MessagesPreflight {
    private static let logger = LogManager.shared
    private static let authorizationManager = MessagesAuthorizationManager.shared
    
    /// Returns the most recently known automation status. This is a lightweight wrapper so callers do not need to reach
    /// into `MessagesAuthorizationManager` directly when performing synchronous checks.
    static func currentAutomationStatus() -> MessagesAuthorizationStatus {
        authorizationManager.authorizationStatus
    }
    
    /// Performs an on-demand automation status refresh. The result is cached on `MessagesAuthorizationManager`.
    static func refreshAutomationStatus(promptUserIfNeeded: Bool = false) async -> MessagesAuthorizationStatus {
        await authorizationManager.checkAuthorizationStatus(promptUserIfNeeded: promptUserIfNeeded)
    }
    
    /// Convenience helper used by legacy callers that only need a boolean success/failure.
    static func hasMessagesAccess() -> Bool {
        let status = authorizationManager.authorizationStatus
        let hasAccess = status == .authorized && authorizationManager.hasFullDiskAccess()
        logger.info("📬 MessagesPreflight: Automation authorized = \(hasAccess)")
        return hasAccess
    }
    
    /// Full Disk Access proxy – relies on `MessagesAuthorizationManager` single source of truth.
    static func hasFullDiskAccess() -> Bool {
        let hasAccess = authorizationManager.hasFullDiskAccess()
        logger.info("💾 MessagesPreflight: Full Disk Access = \(hasAccess)")
        return hasAccess
    }
    
    /// Whether the Messages application bundle exists on the current system.
    static func isMessagesAppInstalled() -> Bool {
        let installed = authorizationManager.isMessagesAppInstalled()
        logger.info("📱 MessagesPreflight: Messages installed = \(installed)")
        return installed
    }
    
    /// Detects if the Messages process is currently running.
    static func isMessagesAppRunning() -> Bool {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        let isRunning = runningApps.contains { $0.bundleIdentifier == "com.apple.MobileSMS" }
        logger.info("📱 MessagesPreflight: Messages running = \(isRunning)")
        return isRunning
    }
}

