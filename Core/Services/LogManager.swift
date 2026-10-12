import Foundation
import os.log

class LogManager: ObservableObject {
    static let shared = LogManager()
    
    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    private let fileHandle: FileHandle?
    
    private init() {
        // Create log file in Application Support
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not access Application Support directory")
        }
        let myCRMAppSupport = appSupport.appendingPathComponent("My_CRM")
        let logsDirectory = myCRMAppSupport.appendingPathComponent("Logs")
        
        // Create logs directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            print("✅ LogManager: Created logs directory at \(logsDirectory.path)")
        } catch {
            print("❌ LogManager: Failed to create logs directory: \(error)")
        }
        
        self.logFileURL = logsDirectory.appendingPathComponent("crm_debug.log")
        
        // Create date formatter for timestamps
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // Create log file if it doesn't exist
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            do {
                try "=== My CRM Debug Log Started ===\n".write(to: logFileURL, atomically: true, encoding: .utf8)
                print("✅ LogManager: Created debug log file at \(logFileURL.path)")
            } catch {
                print("❌ LogManager: Failed to create debug log file: \(error)")
            }
        }
        
        // Open file handle for appending
        do {
            self.fileHandle = try FileHandle(forWritingTo: logFileURL)
            print("✅ LogManager: Successfully opened file handle for \(logFileURL.path)")
        } catch {
            print("❌ LogManager: Failed to open file handle: \(error)")
            self.fileHandle = nil
        }
        
        // Log initialization - this will test if logging works
        log("LogManager initialized", level: .info)
    }
    
    deinit {
        fileHandle?.closeFile()
    }
    
    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }
    
    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function): \(message)\n"
        
        // Print to console
        print(logMessage, terminator: "")
        
        // Write to file using a more reliable approach
        if let data = logMessage.data(using: .utf8) {
            do {
                // Always write directly to file to ensure it's flushed
                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    // Append to existing file
                    let tempFileHandle = try FileHandle(forWritingTo: logFileURL)
                    tempFileHandle.seekToEndOfFile()
                    tempFileHandle.write(data)
                    tempFileHandle.synchronizeFile()
                    tempFileHandle.closeFile()
                } else {
                    // Create new file
                    try data.write(to: logFileURL)
                }
            } catch {
                print("❌ LogManager: Failed to write to log file: \(error)")
            }
        }
    }
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
    
    func getLogFilePath() -> String {
        return logFileURL.path
    }
    
    func clearLog() {
        try? "=== My CRM Debug Log Cleared ===\n".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("Log cleared", level: .info)
    }
    
    func testLogging() {
        log("LogManager test - this should appear in debug log", level: .info)
        debug("LogManager debug test - this should appear in debug log")
        warning("LogManager warning test - this should appear in debug log")
        error("LogManager error test - this should appear in debug log")
    }
}
