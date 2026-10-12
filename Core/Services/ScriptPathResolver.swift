import Foundation

// DEPRECATED: This file contains Python script resolution logic
// Python is no longer used in My CRM (100% Swift implementation)
// This code remains for reference only and will be removed in a future cleanup
// See: PORTABILITY_VERIFICATION.md for details on Swift migration

/// Utility class for resolving Python script paths in both development and production environments
@available(*, deprecated, message: "Python scripts are no longer used. App is 100% Swift.")
class ScriptPathResolver {
    
    /// Resolves the path to a Python script by trying multiple possible locations
    /// - Parameter scriptName: The name of the Python script (e.g., "canvas_manager.py")
    /// - Returns: The resolved path if found, nil otherwise
    static func resolveScriptPath(_ scriptName: String) -> String? {
        guard let bundlePath = Bundle.main.resourcePath else {
            print("Could not get bundle resource path")
            return nil
        }
        
        // Try multiple possible locations for the script
        let possiblePaths = [
            // Production path (in app bundle)
            "\(bundlePath)/Feature Groups/iMessage Server Scraper/Resources/\(scriptName)",
            // Development path (source directory)
            "\(bundlePath)/App/Feature Groups/iMessage Server Scraper/Resources/\(scriptName)",
            // Alternative development path
            "\(bundlePath)/../App/Feature Groups/iMessage Server Scraper/Resources/\(scriptName)",
            // Current working directory path
            "App/Feature Groups/iMessage Server Scraper/Resources/\(scriptName)",
            // Absolute path fallback
            "/Users/andrewsoulier/My_CRM Project/My CRM/App/Feature Groups/iMessage Server Scraper/Resources/\(scriptName)"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        print("\(scriptName) not found. Tried paths:")
        for path in possiblePaths {
            print("  - \(path)")
        }
        return nil
    }
    
    /// Resolves the path to a Python script and returns both the script path and its directory
    /// - Parameter scriptName: The name of the Python script (e.g., "canvas_manager.py")
    /// - Returns: Tuple containing (scriptPath, scriptDirectory) if found, nil otherwise
    static func resolveScriptPathAndDirectory(_ scriptName: String) -> (scriptPath: String, scriptDirectory: String)? {
        guard let scriptPath = resolveScriptPath(scriptName) else {
            return nil
        }
        
        let scriptDirectory = (scriptPath as NSString).deletingLastPathComponent
        return (scriptPath: scriptPath, scriptDirectory: scriptDirectory)
    }
    
    /// Creates a Process configured to run a Python script with proper environment setup
    /// - Parameters:
    ///   - scriptName: The name of the Python script to run
    ///   - arguments: Additional arguments to pass to the script
    /// - Returns: Configured Process if script is found, nil otherwise
    static func createPythonProcess(scriptName: String, arguments: [String]) -> Process? {
        let callStack = DatabaseLogger.shared.getCallStack()
        let details = "Creating Python process for script: \(scriptName) with arguments: \(arguments.joined(separator: " "))"
        
        guard let (scriptPath, scriptDirectory) = resolveScriptPathAndDirectory(scriptName) else {
            DatabaseLogger.shared.logDatabaseOperation(
                operation: "PYTHON_PROCESS_CREATE",
                details: details + " - Script not found",
                success: false,
                callStack: callStack
            )
            return nil
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptPath] + arguments
        
        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = scriptDirectory
        process.environment = env
        
        DatabaseLogger.shared.logDatabaseOperation(
            operation: "PYTHON_PROCESS_CREATE",
            details: details + " - Script path: \(scriptPath)",
            success: true,
            callStack: callStack
        )
        
        return process
    }
}
