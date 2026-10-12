import Foundation
import AppKit
import Contacts
import SQLite3

/// Manages and checks system permissions required by the app
final class PermissionManager {
    static let shared = PermissionManager()
    
    private init() {}
    
    /// Check if the app has Full Disk Access by checking file access without opening database
    func hasFullDiskAccess() -> Bool {
        let chatDBPath = NSHomeDirectory() + "/Library/Messages/chat.db"
        
        // Simply check if the file is readable (less intrusive than opening database)
        let fileManager = FileManager.default
        return fileManager.isReadableFile(atPath: chatDBPath)
    }
    
    /// Check if the app has Contacts permission
    func hasContactsAccess() -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        return status == .authorized
    }
    
    /// Request Contacts permission (this will show system prompt)
    func requestContactsAccess(completion: @escaping (Bool) -> Void) {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, error in
            if let error = error {
                print("❌ PermissionManager: Error requesting contacts access: \(error)")
            }
            completion(granted)
        }
    }
    
    /// Show alert and open System Settings for Full Disk Access
    func promptForFullDiskAccess() {
        // Check if we already have Full Disk Access
        if hasFullDiskAccess() {
            print("✅ PermissionManager: Full Disk Access already granted, skipping prompt")
            return
        }
        
        print("⚠️ PermissionManager: Full Disk Access not granted, showing prompt")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Full Disk Access Required"
            alert.informativeText = """
            My CRM needs Full Disk Access to import your iMessages.
            
            Steps to enable:
            1. Click "Open System Settings" below
            2. Find "My CRM" in the list (or click + to add it from /Applications/)
            3. Enable the toggle next to My CRM
            4. Restart the app
            
            Note: After rebuilding the app, you may need to remove and re-add it to Full Disk Access.
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    
    /// Show alert and request Contacts permission
    func promptForContactsAccess() {
        let logger = LogManager.shared
        let status = CNContactStore.authorizationStatus(for: .contacts)
        logger.info("🔐 PermissionManager.promptForContactsAccess: status = \(status.rawValue)")
        print("🔐 PermissionManager.promptForContactsAccess: status = \(status.rawValue)")
        
        // If already authorized, no need to prompt
        if status == .authorized {
            logger.info("✅ PermissionManager: Contacts already authorized, skipping prompt")
            print("✅ PermissionManager: Contacts already authorized, skipping prompt")
            return
        }
        
        switch status {
        case .notDetermined:
            // First time - request permission (this will show system prompt)
            logger.info("🔐 PermissionManager: Requesting Contacts access (system prompt should appear)...")
            print("🔐 PermissionManager: Requesting Contacts access (system prompt should appear)...")
            
            DispatchQueue.main.async {
                let store = CNContactStore()
                store.requestAccess(for: .contacts) { granted, error in
                    if let error = error {
                        logger.error("❌ PermissionManager: Error requesting contacts access: \(error)")
                        print("❌ PermissionManager: Error requesting contacts access: \(error)")
                    }
                    if granted {
                        logger.info("✅ PermissionManager: Contacts access granted by user")
                        print("✅ PermissionManager: Contacts access granted by user")
                        // Re-run the contacts importer now that we have permission
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            let result = ContactsImporter().run()
                            print("👤 ContactsImporter (after permission): read=\(result.totalRead) inserted=\(result.totalInserted) updated=\(result.totalUpdated)")
                        }
                    } else {
                        logger.warning("⚠️ PermissionManager: User denied contacts access")
                        print("⚠️ PermissionManager: User denied contacts access")
                    }
                }
            }
        case .denied, .restricted:
            // User previously denied - show alert to open Settings
            logger.warning("🔐 PermissionManager: Contacts previously denied, showing settings alert...")
            print("🔐 PermissionManager: Contacts previously denied, showing settings alert...")
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Contacts Access Required"
                alert.informativeText = """
                My CRM needs access to your Contacts to sync and display contact information.
                
                Please enable Contacts access in System Settings.
                """
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Later")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        case .authorized:
            // Already authorized
            logger.info("✅ PermissionManager: Contacts already authorized")
            print("✅ PermissionManager: Contacts already authorized")
        @unknown default:
            break
        }
    }
    
    /// Check all required permissions and prompt if missing
    /// NOTE: This is now deprecated - permissions are requested directly in the importers
    @available(*, deprecated, message: "Permissions are now requested directly by ContactsImporter and MessagesImporter")
    func checkAndPromptForRequiredPermissions() {
        // No longer used - permissions are requested by the importers themselves
    }
    
    /// Force re-check all permissions on next launch
    /// This resets the initial permission check flag
    @MainActor
    func resetPermissionCheckFlag() {
        StartOrchestrator.shared.resetPermissionCheckFlag()
    }
}

