import Foundation

@MainActor
class SchedulingService: ObservableObject {
    static let shared = SchedulingService()
    
    private let logger = LogManager.shared
    private let launchAgentDirectory: URL
    private let helperScriptPath: URL
    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32?
    
    init() {
        // Set up paths
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.launchAgentDirectory = homeDirectory.appendingPathComponent("Library/LaunchAgents")
        
        // Get the helper script path from the app bundle's Resources directory
        if let bundledScriptPath = Bundle.main.url(forResource: "quick_send_helper", withExtension: "sh") {
            self.helperScriptPath = bundledScriptPath
            logger.info("✅ Found bundled helper script at: \(bundledScriptPath.path)")
        } else {
            // Fallback to a temporary location if bundle resource is not found
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let myCRMSupport = appSupport.appendingPathComponent("My_CRM")
            self.helperScriptPath = myCRMSupport.appendingPathComponent("quick_send_helper.sh")
            logger.warning("⚠️ Bundled helper script not found, falling back to: \(self.helperScriptPath.path)")
        }
        
        // Ensure LaunchAgents directory exists
        try? FileManager.default.createDirectory(at: launchAgentDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Scheduling Methods
    
    func scheduleMessage(_ batchMessage: BatchMessage) async -> Bool {
        guard let scheduledTime = batchMessage.scheduledTime else {
            logger.error("❌ Cannot schedule message without scheduled time")
            return false
        }
        
        let jobLabel = "com.mycrm.quicksend.\(batchMessage.id.uuidString)"
        let plistPath = launchAgentDirectory.appendingPathComponent("\(jobLabel).plist")
        
        // Create the launch agent plist
        let plistContent = createLaunchAgentPlist(
            jobLabel: jobLabel,
            messageId: batchMessage.id.uuidString,
            scheduledTime: scheduledTime
        )
        
        do {
            // Write the plist file
            try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)
            logger.info("✅ Created launch agent plist: \(plistPath.path)")
            
            // Load the launch agent
            let loadResult = await loadLaunchAgent(jobLabel: jobLabel)
            if loadResult {
                logger.info("✅ Successfully scheduled message for: \(scheduledTime)")
                return true
            } else {
                logger.error("❌ Failed to load launch agent")
                return false
            }
        } catch {
            logger.error("❌ Failed to create launch agent plist: \(error)")
            return false
        }
    }
    
    func cancelScheduledMessage(_ messageId: UUID) async -> Bool {
        let jobLabel = "com.mycrm.quicksend.\(messageId.uuidString)"
        let plistPath = launchAgentDirectory.appendingPathComponent("\(jobLabel).plist")
        
        // Unload the launch agent
        let unloadResult = await unloadLaunchAgent(jobLabel: jobLabel)
        
        // Remove the plist file
        do {
            try FileManager.default.removeItem(at: plistPath)
            logger.info("✅ Removed launch agent plist: \(plistPath.path)")
        } catch {
            logger.warning("⚠️ Failed to remove plist file: \(error)")
        }
        
        return unloadResult
    }
    
    // MARK: - Launch Agent Management
    
    private func loadLaunchAgent(jobLabel: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", "-w", launchAgentDirectory.appendingPathComponent("\(jobLabel).plist").path]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                logger.info("✅ Successfully loaded launch agent: \(jobLabel)")
                return true
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                logger.error("❌ Failed to load launch agent: \(errorString)")
                return false
            }
        } catch {
            logger.error("❌ Failed to execute launchctl load: \(error)")
            return false
        }
    }
    
    private func unloadLaunchAgent(jobLabel: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", "-w", launchAgentDirectory.appendingPathComponent("\(jobLabel).plist").path]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                logger.info("✅ Successfully unloaded launch agent: \(jobLabel)")
                return true
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                logger.error("❌ Failed to unload launch agent: \(errorString)")
                return false
            }
        } catch {
            logger.error("❌ Failed to execute launchctl unload: \(error)")
            return false
        }
    }
    
    // MARK: - Plist Creation
    
    private func createLaunchAgentPlist(jobLabel: String, messageId: String, scheduledTime: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledTime)
        
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(jobLabel)</string>
            
            <key>ProgramArguments</key>
            <array>
                <string>\(helperScriptPath.path)</string>
                <string>\(messageId)</string>
            </array>
            
            <key>StartCalendarInterval</key>
            <dict>
                <key>Year</key>
                <integer>\(components.year ?? 2024)</integer>
                <key>Month</key>
                <integer>\(components.month ?? 1)</integer>
                <key>Day</key>
                <integer>\(components.day ?? 1)</integer>
                <key>Hour</key>
                <integer>\(components.hour ?? 0)</integer>
                <key>Minute</key>
                <integer>\(components.minute ?? 0)</integer>
            </dict>
            
            <key>RunAtLoad</key>
            <false/>
            
            <key>StandardOutPath</key>
            <string>/tmp/mycrm_quicksend_\(messageId).out</string>
            
            <key>StandardErrorPath</key>
            <string>/tmp/mycrm_quicksend_\(messageId).err</string>
        </dict>
        </plist>
        """
    }
    
    // MARK: - Trigger File Monitoring
    
    func startTriggerFileMonitoring() {
        // Don't start if already monitoring
        guard fileMonitorSource == nil else {
            logger.warning("⚠️ File monitoring already active")
            return
        }
        
        let triggerDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("My_CRM/Triggers")
        
        // Create trigger directory if it doesn't exist
        try? FileManager.default.createDirectory(at: triggerDirectory, withIntermediateDirectories: true)
        
        // Open file descriptor for monitoring
        let fd = open(triggerDirectory.path, O_EVTONLY)
        guard fd >= 0 else {
            logger.error("❌ Failed to open trigger directory for monitoring")
            return
        }
        self.fileDescriptor = fd
        
        // Set up file system monitoring
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .background)
        )
        
        source.setEventHandler { [weak self] in
            self?.processTriggerFiles()
        }
        
        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor {
                close(fd)
                self?.fileDescriptor = nil
            }
        }
        
        source.resume()
        self.fileMonitorSource = source
        
        logger.info("✅ Started trigger file monitoring at: \(triggerDirectory.path)")
    }
    
    private func processTriggerFiles() {
        let triggerDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("My_CRM/Triggers")
        
        do {
            let triggerFiles = try FileManager.default.contentsOfDirectory(at: triggerDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "trigger" }
            
            for triggerFile in triggerFiles {
                let messageId = try String(contentsOf: triggerFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                
                logger.info("🎯 Processing trigger for message: \(messageId)")
                
                // Process the scheduled message
                Task { @MainActor in
                    await self.processScheduledMessage(messageId: messageId)
                }
                
                // Remove the trigger file
                try FileManager.default.removeItem(at: triggerFile)
            }
        } catch {
            logger.error("❌ Failed to process trigger files: \(error)")
        }
    }
    
    @MainActor
    private func processScheduledMessage(messageId: String) async {
        guard let messageUUID = UUID(uuidString: messageId) else {
            logger.error("❌ Invalid message UUID: \(messageId)")
            return
        }
        
        // Find the message in the database
        if let batchMessage = BatchMessageService.shared.dataProvider.batchMessages.first(where: { $0.id == messageUUID }) {
            logger.info("📨 Processing scheduled message: \(batchMessage.id)")
            await BatchMessageService.shared.processBatchMessage(batchMessage)
        } else {
            logger.error("❌ Scheduled message not found: \(messageId)")
        }
    }
    
    // MARK: - Shutdown
    
    func shutdown() async {
        logger.info("🛑 Shutting down SchedulingService...")
        
        // Cancel file system monitor
        if let source = fileMonitorSource {
            source.cancel()
            fileMonitorSource = nil
            logger.info("  ✓ Stopped file system monitor")
        }
        
        // Note: fileDescriptor will be closed by the cancel handler
        
        logger.info("✅ SchedulingService shutdown complete")
    }
    
    // MARK: - Cleanup
    
    func cleanupExpiredJobs() async {
        do {
            let plistFiles = try FileManager.default.contentsOfDirectory(at: launchAgentDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "plist" && $0.lastPathComponent.hasPrefix("com.mycrm.quicksend.") }
            
            for plistFile in plistFiles {
                // Extract message ID from filename
                let filename = plistFile.deletingPathExtension().lastPathComponent
                let messageIdString = String(filename.dropFirst("com.mycrm.quicksend.".count))
                
                if let messageUUID = UUID(uuidString: messageIdString) {
                    // Check if message still exists and is scheduled
                    let messageExists = await BatchMessageService.shared.dataProvider.batchMessages.contains { message in
                        message.id == messageUUID && message.status == .scheduled
                    }
                    
                    if !messageExists {
                        // Clean up orphaned launch agent
                        let jobLabel = "com.mycrm.quicksend.\(messageIdString)"
                        _ = await unloadLaunchAgent(jobLabel: jobLabel)
                        try FileManager.default.removeItem(at: plistFile)
                        logger.info("🧹 Cleaned up orphaned launch agent: \(jobLabel)")
                    }
                }
            }
        } catch {
            logger.error("❌ Failed to cleanup expired jobs: \(error)")
        }
    }
}
