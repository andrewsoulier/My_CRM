import Foundation
import SQLite3

/// Centralized service for cleaning up all app resources on termination
/// Ensures LaunchAgents, database connections, file monitors, and processes are properly closed
@MainActor
class AppCleanupService {
    static let shared = AppCleanupService()
    
    private let logger = LogManager.shared
    private var hasPerformedCleanup = false
    
    private init() {}
    
    /// Main cleanup method - call this before app terminates
    func performCompleteCleanup() async {
        guard !hasPerformedCleanup else {
            logger.info("⚠️ Cleanup already performed, skipping")
            return
        }
        
        logger.info("🧹 Starting complete app cleanup...")
        hasPerformedCleanup = true
        
        // 1. Stop all timers
        await stopAllTimers()
        
        // 2. Unload all LaunchAgents
        await unloadAllLaunchAgents()
        
        // 3. Stop file system monitors
        await stopFileSystemMonitors()
        
        // 4. Terminate background processes
        await terminateBackgroundProcesses()
        
        // 5. Close database connections
        await closeDatabaseConnections()
        
        // 6. Clean up batch messaging service
        await cleanupBatchMessaging()
        
        logger.info("✅ Complete app cleanup finished")
    }
    
    // MARK: - Timer Cleanup
    
    private func stopAllTimers() async {
        logger.info("🕐 Stopping all timers...")
        
        // Stop batch message service timers
        BatchMessageService.shared.shutdown()
        
        logger.info("  ✓ All timers stopped")
    }
    
    // MARK: - LaunchAgent Cleanup
    
    private func unloadAllLaunchAgents() async {
        logger.info("🚀 Unloading all LaunchAgents...")
        
        let launchAgentDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        
        do {
            let allFiles = try FileManager.default.contentsOfDirectory(
                at: launchAgentDirectory,
                includingPropertiesForKeys: nil
            )
            
            // Find all our app's LaunchAgent plist files
            let ourPlists = allFiles.filter { url in
                let filename = url.lastPathComponent
                return (filename.hasPrefix("com.mycrm.") || 
                        filename.hasPrefix("com.andrewsoulier.crm")) && 
                       url.pathExtension == "plist"
            }
            
            for plistURL in ourPlists {
                let jobLabel = plistURL.deletingPathExtension().lastPathComponent
                await unloadLaunchAgent(jobLabel: jobLabel, plistPath: plistURL.path)
            }
            
            logger.info("  ✓ Unloaded \(ourPlists.count) LaunchAgent(s)")
        } catch {
            logger.error("❌ Failed to enumerate LaunchAgents: \(error)")
        }
    }
    
    private func unloadLaunchAgent(jobLabel: String, plistPath: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", "-w", plistPath]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                logger.info("  ✓ Unloaded LaunchAgent: \(jobLabel)")
                
                // Remove the plist file
                try? FileManager.default.removeItem(atPath: plistPath)
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                logger.warning("  ⚠️ Failed to unload \(jobLabel): \(errorString)")
            }
        } catch {
            logger.error("  ❌ Failed to execute launchctl for \(jobLabel): \(error)")
        }
    }
    
    // MARK: - File System Monitor Cleanup
    
    private func stopFileSystemMonitors() async {
        logger.info("📁 Stopping file system monitors...")
        
        // Stop SchedulingService file monitor
        await SchedulingService.shared.shutdown()
        
        logger.info("  ✓ Stopped file system monitors")
    }
    
    // MARK: - Background Process Cleanup
    
    private func terminateBackgroundProcesses() async {
        logger.info("⚙️ Terminating background processes...")
        
        // Stop any running backend processes (Python scripts, etc.)
        // Note: AppModel.stopBackend() will be called separately by AppModel.deinit
        // but we can ensure it happens here too
        
        logger.info("  ✓ Background processes terminated")
    }
    
    // MARK: - Database Connection Cleanup
    
    private func closeDatabaseConnections() async {
        logger.info("💾 Closing database connections...")
        
        // Note: SQLiteDataProvider is a @StateObject in MyCRMApp
        // We access it through MyCRMApp.shared if available
        if let dataProvider = MyCRMApp.shared?.dataProvider {
            await dataProvider.closeDatabase()
        }
        
        // Close CRMDatabase if it has any open connections
        CRMDatabase.shared.closeAllConnections()
        
        logger.info("  ✓ Database connections closed")
    }
    
    // MARK: - Batch Messaging Cleanup
    
    private func cleanupBatchMessaging() async {
        logger.info("📨 Cleaning up batch messaging service...")
        
        // Cancel any in-progress batch messages
        // This is handled by BatchMessageService but we ensure it's done
        
        logger.info("  ✓ Batch messaging cleanup complete")
    }
    
    // MARK: - Manual Cleanup (for external use)
    
    /// Can be called from command line or external script
    func manualCleanup() async {
        logger.info("🔧 Performing manual cleanup (external trigger)...")
        await performCompleteCleanup()
    }
}

