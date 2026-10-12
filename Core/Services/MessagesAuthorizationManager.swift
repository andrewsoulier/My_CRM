import Foundation
import AppKit
import ApplicationServices
import Carbon

enum MessagesAuthorizationStatus {
    case authorized
    case denied
    case notDetermined
    case messagesNotRunning
    case messagesNotInstalled
    
    var description: String {
        switch self {
        case .authorized:
            return "Authorized"
        case .denied:
            return "Access Denied"
        case .notDetermined:
            return "Not Yet Requested"
        case .messagesNotRunning:
            return "Messages App Not Running"
        case .messagesNotInstalled:
            return "Messages App Not Found"
        }
    }
    
    var canSendMessages: Bool {
        return self == .authorized
    }
}

@MainActor
class MessagesAuthorizationManager: ObservableObject {
    static let shared = MessagesAuthorizationManager()
    
    @Published var authorizationStatus: MessagesAuthorizationStatus = .notDetermined
    @Published var lastCheckTime: Date?
    
    private let logger = LogManager.shared
    
    private init() {}
    
    // MARK: - Authorization Checking

    private let automationEventClass = AEEventClass(typeWildCard)
    private let automationEventID = AEEventID(typeWildCard)
    
    /// Determines the current automation permission state for controlling the Messages app without triggering a new prompt.
    private func determineAutomationPermissionStatus(promptUserIfNeeded: Bool) -> MessagesAuthorizationStatus {
        let bundleIdentifier = "com.apple.MobileSMS"
        logger.info("🛡️ Starting automation permission check (promptUser=\(promptUserIfNeeded)) for bundle: \(bundleIdentifier)")
        
        guard let bundleData = bundleIdentifier.data(using: .utf8) else {
            logger.error("❌ Failed to encode bundle identifier for automation permission check")
            return .denied
        }
        
        var addressDescriptor = AEAddressDesc()
        let createStatus: OSStatus = bundleData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return OSStatus(errAECoercionFail)
            }
            let result = AECreateDesc(DescType(typeApplicationBundleID), baseAddress, bundleData.count, &addressDescriptor)
            return OSStatus(Int32(result))
        }
        
        guard createStatus == noErr else {
            logger.error("❌ Failed to create AEAddressDesc for Messages automation check (status: \(createStatus))")
            return .denied
        }
        
        defer {
            AEDisposeDesc(&addressDescriptor)
        }
        
        let status = withUnsafePointer(to: &addressDescriptor) { descriptorPointer in
            AEDeterminePermissionToAutomateTarget(
                descriptorPointer,
                automationEventClass,
                automationEventID,
                promptUserIfNeeded
            )
        }
        logger.info("🛡️ Automation permission raw status: \(status)")
        
        switch status {
        case noErr:
            logger.info("📬 Automation permission check result: granted")
            return .authorized
        case OSStatus(errAEEventWouldRequireUserConsent):
            logger.warning("⚠️ Automation permission requires user consent (not determined)")
            return .notDetermined
        case OSStatus(errAEEventNotPermitted):
            logger.warning("⚠️ Automation permission explicitly denied by user")
            return .denied
        case OSStatus(procNotFound):
            logger.warning("⚠️ Automation permission check failed: Messages process not found")
            return .messagesNotRunning
        default:
            logger.error("❌ Unexpected status (\(status)) while checking automation permission")
            return .denied
        }
    }
    
    /// Performs a comprehensive check of all Messages-related permissions and availability
    func checkAuthorizationStatus(promptUserIfNeeded: Bool = false) async -> MessagesAuthorizationStatus {
        logger.info("🔍 Checking Messages authorization status (promptUser=\(promptUserIfNeeded))...")
        
        // 1. Check if Messages app is installed
        guard isMessagesAppInstalled() else {
            logger.error("❌ Messages app is not installed")
            authorizationStatus = .messagesNotInstalled
            lastCheckTime = Date()
            return .messagesNotInstalled
        }
        
        // 2. Check if Messages app is running (required for AppleScript)
        guard await isMessagesAppRunning() else {
            logger.warning("⚠️ Messages app is not running")
            authorizationStatus = .messagesNotRunning
            lastCheckTime = Date()
            return .messagesNotRunning
        }
        
        // 3. Check automation permission without prompting
        let automationStatus = determineAutomationPermissionStatus(promptUserIfNeeded: promptUserIfNeeded)
        authorizationStatus = automationStatus
        logger.info("🔍 Authorization status after automation check: \(authorizationStatus)")
        
        lastCheckTime = Date()
        return authorizationStatus
    }
    
    /// Explicitly prompts for automation permission when needed so the app appears in System Settings.
    func requestAutomationPermission() async -> MessagesAuthorizationStatus {
        logger.info("🙋 Requesting automation permission with user prompt")
        
        // 1. First, perform a silent check to avoid unnecessary prompts
        var status = await checkAuthorizationStatus(promptUserIfNeeded: false)
        if status == .authorized {
            logger.info("🙋 Automation already authorized – no prompt required")
            return status
        }
        
        // 2. Ask the system to prompt the user if it thinks consent is still needed
        status = await checkAuthorizationStatus(promptUserIfNeeded: true)
        if status == .authorized {
            logger.info("🙋 Automation permission granted directly by system prompt")
            return status
        }
        
        // 3. If the system still reports ambiguous/denied status, attempt an AppleScript handshake
        if status == .notDetermined || status == .denied {
            logger.warning("🤝 System still reports status \(status). Attempting AppleScript handshake to reconcile TCC state...")
            let handshakeSucceeded = await performAutomationHandshake()
            if handshakeSucceeded {
                logger.info("🤝 AppleScript handshake succeeded. Re-checking authorization status...")
            } else {
                logger.warning("🤝 AppleScript handshake failed or was cancelled. Authorization may remain unresolved.")
            }
            
            // Re-check without prompting to capture the final state after handshake
            status = await checkAuthorizationStatus(promptUserIfNeeded: false)
        }
        
        logger.info("🙋 Automation permission request completed with status: \(status)")
        return status
    }
    
    private func performAutomationHandshake() async -> Bool {
        let messagesRunning = await isMessagesAppRunning()
        guard messagesRunning else {
            logger.warning("🤝 Handshake skipped because Messages is not running")
            return false
        }
        
        logger.info("🤝 Performing automation handshake via AppleScript...")
        let scriptSource = """
        tell application "Messages"
            try
                set _count to count of services
                return _count
            on error errMsg number errNum
                error errMsg number errNum
            end try
        end tell
        """
        
        guard let appleScript = NSAppleScript(source: scriptSource) else {
            logger.error("🤝 Failed to create AppleScript instance for automation handshake")
            return false
        }
        
        var errorDictionary: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&errorDictionary)
        
        if let errorDictionary = errorDictionary {
            let message = (errorDictionary[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
            let number = (errorDictionary[NSAppleScript.errorNumber] as? Int) ?? 0
            logger.error("🤝 Automation handshake AppleScript failed: \(message) (\(number))")
            return false
        }
        
        if let stringValue = descriptor.stringValue, !stringValue.isEmpty {
            logger.info("🤝 Automation handshake succeeded. AppleScript returned: \(stringValue)")
        } else {
            logger.info("🤝 Automation handshake succeeded without returning additional data")
        }
        return true
    }
    
    // MARK: - Messages App Availability
    
    func isMessagesAppInstalled() -> Bool {
        let messagesPath = "/System/Applications/Messages.app"
        let exists = FileManager.default.fileExists(atPath: messagesPath)
        logger.info("📱 Messages app installed: \(exists)")
        return exists
    }
    
    func isMessagesAppRunning() async -> Bool {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        let isRunning = runningApps.contains { $0.bundleIdentifier == "com.apple.MobileSMS" }
        logger.info("📱 Messages app running: \(isRunning)")
        return isRunning
    }
    
    func launchMessagesApp() async -> Bool {
        logger.info("🚀 Attempting to launch Messages app...")
        
        guard let messagesURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS") else {
            logger.error("❌ Could not find Messages app")
            return false
        }
        
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false // Don't steal focus
            
            try await NSWorkspace.shared.openApplication(at: messagesURL, configuration: configuration)
            
            // Wait a bit for Messages to launch
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            let isRunning = await isMessagesAppRunning()
            if isRunning {
                logger.info("✅ Messages app launched successfully")
            } else {
                logger.warning("⚠️ Messages app may not have launched properly")
            }
            
            return isRunning
        } catch {
            logger.error("❌ Failed to launch Messages app: \(error)")
            return false
        }
    }
    
    // MARK: - Full Disk Access Check
    
    func hasFullDiskAccess() -> Bool {
        // Check if we can access the Messages database
        let chatDB = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Messages")
            .appendingPathComponent("chat.db")
        
        let hasAccess = FileManager.default.fileExists(atPath: chatDB.path) &&
                        FileManager.default.isReadableFile(atPath: chatDB.path)
        
        logger.info("💾 Full Disk Access (Messages DB): \(hasAccess)")
        return hasAccess
    }
    
    // MARK: - System Settings Integration
    
    func openSystemSettingsToAutomation() {
        logger.info("🔧 Opening System Settings to Automation preferences...")
        
        // macOS 13+ (Ventura and later)
        if #available(macOS 13.0, *) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        } else {
            // Fallback for earlier macOS versions
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    func openSystemSettingsToFullDiskAccess() {
        logger.info("🔧 Opening System Settings to Full Disk Access...")
        
        if #available(macOS 13.0, *) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        } else {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // MARK: - User Guidance
    
    func getAuthorizationGuidanceMessage() -> String {
        switch authorizationStatus {
        case .authorized:
            return "You're all set! My CRM has permission to send messages."
            
        case .denied, .notDetermined:
            return """
            My CRM needs your permission to send messages through the Messages app.
            
            To grant permission:
            1. Open System Settings
            2. Go to Privacy & Security → Automation
            3. Find "My CRM" in the list
            4. Enable the checkbox for "Messages"
            5. Return to My CRM and try again
            
            The Messages app must be running for My CRM to send messages.
            """
            
        case .messagesNotRunning:
            return """
            The Messages app must be running for My CRM to send messages.
            
            Would you like to launch Messages now?
            """
            
        case .messagesNotInstalled:
            return """
            The Messages app could not be found on your system.
            
            Please ensure macOS Messages is installed at:
            /System/Applications/Messages.app
            """
        }
    }
    
    func getQuickFixInstructions() -> [String] {
        switch authorizationStatus {
        case .authorized:
            return ["You're ready to send messages!"]
            
        case .denied, .notDetermined:
            return [
                "Click 'Request Permission' below",
                "Approve the macOS permission prompt for My CRM",
                "If needed, click 'Open System Settings' to enable Messages for My CRM",
                "Return here and click 'Check Again'"
            ]
            
        case .messagesNotRunning:
            return [
                "Click 'Launch Messages' below",
                "Wait for Messages to open",
                "Return here and try sending again"
            ]
            
        case .messagesNotInstalled:
            return [
                "Ensure macOS Messages is installed",
                "Check /System/Applications/Messages.app",
                "Contact support if the issue persists"
            ]
        }
    }
    
    // MARK: - Comprehensive Pre-Send Validation
    
    struct ValidationResult {
        let canSend: Bool
        let issues: [ValidationIssue]
        
        var isValid: Bool { canSend && issues.isEmpty }
    }
    
    struct ValidationIssue {
        let severity: Severity
        let title: String
        let description: String
        let action: (() -> Void)?
        
        enum Severity {
            case error
            case warning
            case info
        }
    }
    
    func validateCanSendMessages() async -> ValidationResult {
        var issues: [ValidationIssue] = []
        var canSend = true
        
        // Check 1: Messages app installed
        if !isMessagesAppInstalled() {
            issues.append(ValidationIssue(
                severity: .error,
                title: "Messages Not Installed",
                description: "The Messages app could not be found on your system.",
                action: nil
            ))
            canSend = false
        }
        
        // Check 2: Messages app running
        if canSend {
            let messagesRunning = await isMessagesAppRunning()
            if !messagesRunning {
                issues.append(ValidationIssue(
                    severity: .error,
                    title: "Messages Not Running",
                    description: "The Messages app must be running to send messages.",
                    action: { Task { try? await self.launchMessagesApp() } }
                ))
                canSend = false
            }
        }
        
        // Check 3: AppleScript authorization
        let status = await checkAuthorizationStatus()
        if status != .authorized {
            issues.append(ValidationIssue(
                severity: .error,
                title: "Authorization Required",
                description: "My CRM needs permission to control the Messages app.",
                action: { self.openSystemSettingsToAutomation() }
            ))
            canSend = false
        }
        
        // Check 4: Full Disk Access (warning, not blocking)
        if !hasFullDiskAccess() {
            issues.append(ValidationIssue(
                severity: .warning,
                title: "Full Disk Access Recommended",
                description: "Granting Full Disk Access allows My CRM to read message history and improve features.",
                action: { self.openSystemSettingsToFullDiskAccess() }
            ))
            // Don't block sending for this
        }
        
        return ValidationResult(canSend: canSend, issues: issues)
    }
}

