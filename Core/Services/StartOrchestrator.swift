import Foundation
import SQLite3

@MainActor
final class StartOrchestrator: ObservableObject {
    static let shared = StartOrchestrator()
    
    // UserDefaults key to track if initial permission checks have been completed
    private let permissionsCheckedKey = "com.mycrm.permissionsInitialCheckCompleted"

    private init() {}

    // MARK: - Public Entry
    func run(usePythonFallback: Bool = true, useSwiftContactsImport: Bool = false, useSwiftMessagesImport: Bool = false, forcePermissionCheck: Bool = false) {
        FirstRunSetup.run()
        
        // Check and request permissions ONLY if:
        // 1. This is the first run (permissions not yet checked), OR
        // 2. Force check is requested, OR
        // 3. Permissions are actually missing
        let hasCompletedInitialCheck = UserDefaults.standard.bool(forKey: permissionsCheckedKey)
        
        if !hasCompletedInitialCheck || forcePermissionCheck {
            print("🔐 StartOrchestrator: Running initial permission checks...")
            Task { @MainActor in
                // Check Contacts permission
                let hasContacts = PermissionManager.shared.hasContactsAccess()
                print("🔐 StartOrchestrator: Contacts access = \(hasContacts)")
                if !hasContacts {
                    PermissionManager.shared.promptForContactsAccess()
                }
                
                // Check Full Disk Access
                let hasFullDisk = PermissionManager.shared.hasFullDiskAccess()
                print("🔐 StartOrchestrator: Full Disk Access = \(hasFullDisk)")
                if !hasFullDisk {
                    PermissionManager.shared.promptForFullDiskAccess()
                }
                
                // Mark permissions as checked (even if not all granted)
                // This prevents repeated prompts on every launch
                UserDefaults.standard.set(true, forKey: self.permissionsCheckedKey)
                print("✅ StartOrchestrator: Initial permission checks completed and flagged")
            }
        } else {
            print("✅ StartOrchestrator: Skipping permission checks (already completed on first launch)")
            
            // Still log the current status without prompting
            Task { @MainActor in
                let hasContacts = PermissionManager.shared.hasContactsAccess()
                let hasFullDisk = PermissionManager.shared.hasFullDiskAccess()
                print("📊 Current permissions status: Contacts=\(hasContacts), FullDiskAccess=\(hasFullDisk)")
            }
        }
        
        if usePythonFallback && !(useSwiftContactsImport || useSwiftMessagesImport) {
            let preSnapshot = IntegritySnapshot.collect()
            let preLogMarker = LogScanService.shared.currentLogFileSize()
            runPythonStartScript { [weak self] in
                self?.verifyCheckpoint(preSnapshot: preSnapshot, preLogMarker: preLogMarker)
            }
            return
        }

        Task { @MainActor in
            let preSnapshot = IntegritySnapshot.collect()
            let preLogMarker = LogScanService.shared.currentLogFileSize()

            await ImportSyncCoordinator.shared.runStartupImports(
                useContacts: useSwiftContactsImport,
                useMessages: useSwiftMessagesImport
            )

            self.verifyCheckpoint(preSnapshot: preSnapshot, preLogMarker: preLogMarker)
        }
    }

    // MARK: - Python Fallback (DEPRECATED - Not used in production)
    // Note: Python is completely disabled in this app (usePythonFallback: false)
    // This code remains for reference only and will be removed in a future version
    
    @available(*, deprecated, message: "Python fallback is disabled. App uses pure Swift implementation.")
    private func runPythonStartScript(completion: @escaping () -> Void) {
        guard let scriptPath = ScriptPathResolver.resolveScriptPath("start.py") else {
            print("❌ StartOrchestrator: start.py not found")
            completion()
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptPath]
        process.currentDirectoryURL = URL(fileURLWithPath: (scriptPath as NSString).deletingLastPathComponent)

        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = (scriptPath as NSString).deletingLastPathComponent
        process.environment = env

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                DispatchQueue.main.async { print("start.py output: \(line)") }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                DispatchQueue.main.async { print("start.py error: \(line)") }
            }
        }

        process.terminationHandler = { _ in
            DispatchQueue.main.async { completion() }
        }

        do {
            try process.run()
        } catch {
            print("❌ StartOrchestrator: failed to run start.py: \(error)")
            completion()
        }
    }

    // MARK: - Permission Management
    
    /// Reset the permission check flag to force re-checking on next launch
    /// Useful if user wants to re-grant permissions or after app reinstall
    func resetPermissionCheckFlag() {
        UserDefaults.standard.removeObject(forKey: permissionsCheckedKey)
        print("🔄 StartOrchestrator: Permission check flag reset - will prompt on next launch")
    }
    
    // MARK: - Verification
    private func verifyCheckpoint(preSnapshot: IntegritySnapshot, preLogMarker: UInt64) {
        let postSnapshot = IntegritySnapshot.collect()
        let diff = postSnapshot.diff(from: preSnapshot)
        if !diff.isEmpty {
            print("🔎 StartOrchestrator: DB snapshot diff: \(diff)")
        }

        let integrityReport = DBIntegrityChecks.run()
        if !integrityReport.isEmpty {
            print("🔎 StartOrchestrator: Integrity report: \(integrityReport)")
        }

        let logFindings = LogScanService.shared.scanSince(offset: preLogMarker)
        if !logFindings.errors.isEmpty || !logFindings.warnings.isEmpty {
            print("🔎 StartOrchestrator: Log findings — errors: \(logFindings.errors.count), warnings: \(logFindings.warnings.count)")
            if !logFindings.errors.isEmpty {
                print("🔎 StartOrchestrator: First error: \(logFindings.errors.first ?? "")")
            }
        }
    }
}



