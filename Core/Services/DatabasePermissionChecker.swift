import Foundation
import AppKit

enum PermissionStatus {
    case authorized
    case denied
    case cloudSynced
    case unknown
}

struct RunningInstance {
    let pid: pid_t
    let bundlePath: String
    let launchDate: Date?
}

@MainActor
class DatabasePermissionChecker {
    static let shared = DatabasePermissionChecker()
    private let logger = LogManager.shared
    
    private init() {}
    
    /// Check if the database path has write permissions
    func checkDatabaseWritePermission(path: String) -> PermissionStatus {
        let fileManager = FileManager.default
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        
        // Check if directory exists
        if !fileManager.fileExists(atPath: directory.path) {
            // Try to create it
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                logger.info("✅ Created database directory: \(directory.path)")
            } catch {
                logger.error("❌ Cannot create database directory: \(error.localizedDescription)")
                return .denied
            }
        }
        
        // Test write by creating a temporary file
        let testFile = directory.appendingPathComponent(".write_test_\(UUID().uuidString).tmp")
        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try fileManager.removeItem(at: testFile)
            logger.info("✅ Write permission verified for: \(directory.path)")
            return .authorized
        } catch {
            logger.error("❌ Write permission denied for: \(directory.path) - \(error.localizedDescription)")
            return .denied
        }
    }
    
    /// Check if the path is in a cloud-synced location
    func isPathCloudSynced(_ path: String) -> (isSynced: Bool, service: String?) {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: path)
        
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]),
           values.isUbiquitousItem == true {
            return (true, "iCloud Drive")
        }
        
        if let parentValues = try? url.deletingLastPathComponent().resourceValues(forKeys: [.isUbiquitousItemKey]),
           parentValues.isUbiquitousItem == true {
            return (true, "iCloud Drive")
        }
        
        // Check for Google Drive paths
        if path.contains("Google Drive") || path.contains("GoogleDrive") || path.contains("Library/CloudStorage/GoogleDrive") {
            return (true, "Google Drive")
        }
        
        // Check for Dropbox paths
        if path.contains("Dropbox") {
            return (true, "Dropbox")
        }
        
        // Check for OneDrive paths
        if path.contains("OneDrive") {
            return (true, "OneDrive")
        }
        
        // Check if in Documents folder (only flag if actually synced)
        if path.contains("Library/Mobile Documents") {
            return (true, "iCloud Drive")
        }
        
        if let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.path {
            if path.hasPrefix(documentsPath) {
                // Only warn if iCloud is actually enabled for Documents
                let iCloudPath = NSHomeDirectory() + "/Library/Mobile Documents"
                if fileManager.fileExists(atPath: iCloudPath) {
                    // Check if Documents is actually being synced to iCloud
                    // Real iCloud sync would have extended attributes, but for now just check containers
                    if let attrs = try? fileManager.attributesOfItem(atPath: documentsPath),
                       attrs[.size] != nil {
                        // More sophisticated check would use extended attributes
                        // For now, only flag if iCloud Mobile Documents exists and is non-empty
                        let iCloudContents = (try? fileManager.contentsOfDirectory(atPath: iCloudPath)) ?? []
                        if !iCloudContents.isEmpty {
                            return (true, "iCloud Drive")
                        }
                    }
                }
                // Documents folder exists but no clear iCloud sync indicators
                return (false, nil)
            }
        }
        
        // Check Desktop folder
        if let desktopPath = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first?.path {
            if path.hasPrefix(desktopPath) {
                return (true, "Desktop (potentially cloud-synced)")
            }
        }
        
        return (false, nil)
    }
    
    /// Show alert for permission issues
    func showPermissionAlert(status: PermissionStatus) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        
        switch status {
        case .denied:
            alert.messageText = "Database Permission Required"
            alert.informativeText = """
            My CRM cannot write to the database location. This may be because:
            
            • The app needs Full Disk Access permission
            • The database folder is read-only
            • Insufficient disk space
            
            Please grant Full Disk Access in System Settings:
            System Settings → Privacy & Security → Full Disk Access
            """
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open System Settings to Privacy & Security
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            
        case .cloudSynced:
            alert.messageText = "Database in Cloud-Synced Location"
            alert.informativeText = """
            The database is located in a folder that may be synced to the cloud. This can cause write conflicts and data corruption.
            
            It's recommended to move the database to:
            ~/Library/Application Support/My_CRM/
            
            You can change the database location in Settings.
            """
            alert.addButton(withTitle: "OK")
            alert.runModal()
            
        default:
            break
        }
    }
    
    /// Show informational alert about cloud sync (warning, not blocking)
    func showCloudSyncWarning(service: String, path: String) {
        logger.warning("⚠️ Database is in \(service) folder: \(path)")
        logger.warning("💡 This may cause I/O errors. Consider moving to ~/Library/Application Support/My_CRM/")
        
        // Don't show UI alert for cloud sync - just log it
        // The user chose option 1c: just log warning but continue
    }
    
    /// Get diagnostic information about I/O error
    func getDiagnosticInfo(path: String) -> [String] {
        var diagnostics: [String] = []
        
        let fileManager = FileManager.default
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        
        // 1. Check permissions
        let permissionStatus = checkDatabaseWritePermission(path: path)
        switch permissionStatus {
        case .denied:
            diagnostics.append("❌ Write permission denied")
        case .authorized:
            diagnostics.append("✅ Write permission OK")
        default:
            diagnostics.append("⚠️ Permission status unknown")
        }
        
        // 2. Check cloud sync
        let (isSynced, service) = isPathCloudSynced(path)
        if isSynced {
            diagnostics.append("⚠️ Database in cloud-synced location (\(service ?? "unknown"))")
        } else {
            diagnostics.append("✅ Database not in cloud-synced location")
        }
        
        // 3. Check disk space
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: directory.path)
            if let freeSpace = attributes[.systemFreeSize] as? Int64 {
                let freeSpaceGB = Double(freeSpace) / 1_000_000_000
                if freeSpaceGB < 1.0 {
                    diagnostics.append("❌ LOW DISK SPACE: \(String(format: "%.2f", freeSpaceGB)) GB free")
                } else {
                    diagnostics.append("✅ Disk space OK: \(String(format: "%.2f", freeSpaceGB)) GB free")
                }
            }
        } catch {
            diagnostics.append("⚠️ Could not check disk space")
        }
        
        // 4. Check if temp directory is writable
        let tmpDir = FileManager.default.temporaryDirectory
        let testTmpFile = tmpDir.appendingPathComponent(".test_\(UUID().uuidString)")
        do {
            try "test".write(to: testTmpFile, atomically: true, encoding: .utf8)
            try fileManager.removeItem(at: testTmpFile)
            diagnostics.append("✅ Temp directory writable")
        } catch {
            diagnostics.append("❌ Temp directory NOT writable (SQLite needs this for journals)")
        }
        
        // 5. Check for file locks
        if fileManager.fileExists(atPath: path) {
            let journalPath = path + "-journal"
            let walPath = path + "-wal"
            
            if fileManager.fileExists(atPath: journalPath) {
                diagnostics.append("⚠️ Found rollback journal (may indicate interrupted transaction)")
            }
            if fileManager.fileExists(atPath: walPath) {
                diagnostics.append("ℹ️ Found WAL file (normal for WAL mode)")
            }
        }
        
        return diagnostics
    }
}


