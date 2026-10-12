import Foundation

class GroupBehaviorLogger: ObservableObject {
    static let shared = GroupBehaviorLogger()
    
    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    private let fileHandle: FileHandle?
    
    private init() {
        // Create logs directory in Application Support
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not access Application Support directory")
        }
        let logsDirectory = appSupportURL.appendingPathComponent("My_CRM/Logs")
        
        // Create logs directory if it doesn't exist
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        
        self.logFileURL = logsDirectory.appendingPathComponent("group_behavior.log")
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // Create or open log file
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        
        self.fileHandle = try? FileHandle(forWritingTo: logFileURL)
        
        // Write header
        log("=== Group Behavior Logger Started ===", level: "INFO")
    }
    
    deinit {
        fileHandle?.closeFile()
    }
    
    func log(_ message: String, level: String = "INFO", contact: ContactNode? = nil, group: GroupCircle? = nil, operation: String = "") {
        let timestamp = dateFormatter.string(from: Date())
        let contactInfo = if let contact = contact { " [Contact: \(contact.name) (\(contact.phone))]" } else { "" }
        let groupInfo = if let group = group { " [Group: \(group.name) (\(group.id))]" } else { "" }
        let operationInfo = operation.isEmpty ? "" : " [\(operation)]"
        
        let logMessage = "[\(timestamp)] [\(level)]\(contactInfo)\(groupInfo)\(operationInfo): \(message)\n"
        
        // Write to file
        if let data = logMessage.data(using: .utf8) {
            fileHandle?.write(data)
            fileHandle?.synchronizeFile()
        }
        
        // Also print to console for debugging
        print(logMessage.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    func logOverlapDetection(contact: ContactNode, group: GroupCircle, distance: CGFloat, isInside: Bool) {
        log("Overlap detection - Distance: \(String(format: "%.2f", distance)), Radius: \(String(format: "%.2f", group.radius)), Inside: \(isInside)", 
            level: "OVERLAP", 
            contact: contact, 
            group: group, 
            operation: "DETECTION")
    }
    
    func logMembershipChange(contact: ContactNode, group: GroupCircle, action: String, wasMember: Bool, isMember: Bool) {
        log("Membership change - Action: \(action), Was member: \(wasMember), Is member: \(isMember)", 
            level: "MEMBERSHIP", 
            contact: contact, 
            group: group, 
            operation: action.uppercased())
    }
    
    func logDatabaseUpdate(group: GroupCircle, participantCount: Int, participantPhones: [String]) {
        log("Database update - Participants: \(participantCount), Phones: [\(participantPhones.joined(separator: ", "))]", 
            level: "DATABASE", 
            group: group, 
            operation: "UPDATE")
    }
    
    func logRecalculationStart(contactCount: Int, groupCount: Int, specificContact: ContactNode? = nil) {
        let contactInfo = if let specificContact = specificContact { " for contact: \(specificContact.name)" } else { " for all contacts" }
        log("Starting membership recalculation\(contactInfo) - Total contacts: \(contactCount), Total groups: \(groupCount)", 
            level: "RECALCULATION", 
            contact: specificContact, 
            operation: "START")
    }
    
    func logRecalculationComplete(contactCount: Int, groupCount: Int) {
        log("Membership recalculation complete - Processed \(contactCount) contacts across \(groupCount) groups", 
            level: "RECALCULATION", 
            operation: "COMPLETE")
    }
    
    func getLogFilePath() -> String {
        return logFileURL.path
    }
    
    func clearLog() {
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== Group Behavior Log Cleared ===", level: "INFO")
    }
}
