import Foundation
import AppKit

@MainActor
class AppInstanceManager {
    static let shared = AppInstanceManager()
    private let logger = LogManager.shared
    
    private init() {}
    
    /// Check for other running instances of My CRM
    func checkForOtherInstances() -> [RunningInstance] {
        var instances: [RunningInstance] = []
        let currentPID = ProcessInfo.processInfo.processIdentifier
        
        // Get all running applications
        let runningApps = NSWorkspace.shared.runningApplications
        
        // Filter for My CRM instances
        for app in runningApps {
            // Check bundle identifier and that it's not the current process
            if (app.bundleIdentifier?.contains("my-crm") == true || 
                app.bundleIdentifier?.contains("My-CRM") == true ||
                app.localizedName?.contains("My CRM") == true) &&
               app.processIdentifier != currentPID {
                
                let instance = RunningInstance(
                    pid: app.processIdentifier,
                    bundlePath: app.bundleURL?.path ?? "Unknown",
                    launchDate: app.launchDate
                )
                instances.append(instance)
                
                logger.warning("⚠️ Found other My CRM instance: PID \(app.processIdentifier), Path: \(instance.bundlePath)")
            }
        }
        
        return instances
    }
    
    /// Show alert about multiple instances and offer to quit them
    func showMultiInstanceAlert(instances: [RunningInstance]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Multiple Instances Detected"
        
        var infoText = "Another instance of My CRM is already running:\n\n"
        for instance in instances {
            let launchTime = instance.launchDate.map { 
                DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium)
            } ?? "Unknown"
            infoText += "• PID \(instance.pid) - Started at \(launchTime)\n"
        }
        infoText += """
        \n\nRunning multiple instances can cause database lock conflicts and I/O errors.
        
        Would you like to quit the other instance(s)?
        """
        
        alert.informativeText = infoText
        alert.addButton(withTitle: "Quit Other Instance(s)")
        alert.addButton(withTitle: "Continue Anyway")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // User chose to quit other instances
            quitOtherInstances(instances)
            logger.info("✅ Quit \(instances.count) other instance(s)")
            return true
        } else if response == .alertSecondButtonReturn {
            // User chose to continue anyway
            logger.warning("⚠️ User chose to continue with multiple instances running")
            return true
        } else {
            // User cancelled
            logger.info("ℹ️ User cancelled app launch due to multiple instances")
            return false
        }
    }
    
    /// Terminate other app instances
    func quitOtherInstances(_ instances: [RunningInstance]) {
        let runningApps = NSWorkspace.shared.runningApplications
        
        for instance in instances {
            // Find the running application by PID
            if let app = runningApps.first(where: { $0.processIdentifier == instance.pid }) {
                logger.info("🛑 Terminating instance with PID: \(instance.pid)")
                
                // Try graceful termination first
                let terminated = app.terminate()
                
                if !terminated {
                    // Force quit if graceful termination fails
                    logger.warning("⚠️ Graceful termination failed, forcing quit for PID: \(instance.pid)")
                    app.forceTerminate()
                }
                
                // Wait a moment for the process to exit
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }
    
    /// Check and handle multiple instances before connecting to database
    func checkAndHandleMultipleInstances() async -> Bool {
        let instances = checkForOtherInstances()
        
        if instances.isEmpty {
            logger.info("✅ No other My CRM instances detected")
            return true
        }
        
        logger.warning("⚠️ Found \(instances.count) other My CRM instance(s)")
        return showMultiInstanceAlert(instances: instances)
    }
}


