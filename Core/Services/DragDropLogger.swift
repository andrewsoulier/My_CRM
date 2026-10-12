import Foundation

class DragDropLogger {
    static let shared = DragDropLogger()
    
    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    
    private init() {
        // Create log file in Documents directory
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Could not access Documents directory")
        }
        logFileURL = documentsPath.appendingPathComponent("drag_drop.log")
        
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // Create log file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            try? "=== Drag and Drop Log Started ===\n".write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }
    
    func log(_ message: String, operation: String = "INFO", file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logEntry = "[\(timestamp)] [\(operation)] [\(fileName):\(line)] \(function): \(message)\n"
        
        // Append to log file
        if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
            fileHandle.seekToEndOfFile()
            if let data = logEntry.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            // If file handle fails, try to append using string write
            try? logEntry.write(to: logFileURL, atomically: false, encoding: .utf8)
        }
        
        // Also print to console for immediate feedback
        print("🔄 DragDrop: \(logEntry.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    
    func logDragStart(contact: Contact, source: String) {
        log("DRAG_START - Contact: \(contact.displayName) (\(contact.phone)) from \(source)", operation: "DRAG")
    }
    
    func logDragEnd(contact: Contact, source: String) {
        log("DRAG_END - Contact: \(contact.displayName) (\(contact.phone)) from \(source)", operation: "DRAG")
    }
    
    func logDropAttempt(target: String, contact: Contact) {
        log("DROP_ATTEMPT - Target: \(target), Contact: \(contact.displayName) (\(contact.phone))", operation: "DROP")
    }
    
    func logDropSuccess(target: String, contact: Contact, location: CGPoint) {
        log("DROP_SUCCESS - Target: \(target), Contact: \(contact.displayName) (\(contact.phone)) at \(location)", operation: "DROP")
    }
    
    func logDropRejected(target: String, contact: Contact, reason: String) {
        log("DROP_REJECTED - Target: \(target), Contact: \(contact.displayName) (\(contact.phone)), Reason: \(reason)", operation: "DROP")
    }
    
    func logUTTypeMismatch(expected: String, actual: String) {
        log("UTTYPE_MISMATCH - Expected: \(expected), Actual: \(actual)", operation: "ERROR")
    }
    
    func logProviderCreation(contact: Contact, typeIdentifier: String) {
        log("PROVIDER_CREATED - Contact: \(contact.displayName), Type: \(typeIdentifier)", operation: "PROVIDER")
    }
    
    func logProviderDecode(contact: Contact, typeIdentifier: String, success: Bool) {
        log("PROVIDER_DECODE - Contact: \(contact.displayName), Type: \(typeIdentifier), Success: \(success)", operation: "PROVIDER")
    }
    
    func logDropDestinationTriggered(destination: String, contactCount: Int) {
        log("DESTINATION_TRIGGERED - \(destination), Contacts: \(contactCount)", operation: "DESTINATION")
    }
    
    func logViewHierarchy(component: String, action: String) {
        log("VIEW_HIERARCHY - \(component): \(action)", operation: "VIEW")
    }
    
    func clearLog() {
        try? "=== Drag and Drop Log Cleared ===\n".write(to: logFileURL, atomically: true, encoding: .utf8)
    }
    
    func getLogContents() -> String {
        return (try? String(contentsOf: logFileURL)) ?? "Log file not found"
    }
}
