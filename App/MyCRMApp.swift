import SwiftUI
import AppKit
import Combine
import SQLite3

@available(macOS 11.0, *)
final class AppModel: ObservableObject {
    @Published var isBackendConnected: Bool = false
    @Published var dbURL: URL? = nil
    @Published var isRunning: Bool = false
    @Published var lastUpdate: String = "Never"
    @Published var isMainWindowOpen: Bool = false
    
    private weak var mainWindow: NSWindow?
    private var mainWindowCloseObserver: NSObjectProtocol?
    
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var timer: Timer?
    private var updateTimer: Timer?
    private var dataCheckTimer: Timer?
    
    // File to track last run time
    private var lastRunTimeFile: URL {
        let appSupportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("My_CRM")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        
        return appSupportDir.appendingPathComponent("last_run_time.txt")
    }
    
    // DEPRECATED: Python script references (not used in production)
    // App uses pure Swift implementation via StartOrchestrator
    private var startScriptPath: URL? {
        guard let scriptPath = ScriptPathResolver.resolveScriptPath("start.py") else {
            return nil
        }
        print("✅ Found start.py at: \(scriptPath)")
        return URL(fileURLWithPath: scriptPath)
    }
    
    func startBackend() {
        guard !isRunning else { 
            print("Backend is already running")
            return 
        }
        
        // Get the path to Launch_Server.sh
        guard let bundlePath = Bundle.main.resourcePath else {
            print("Could not get bundle resource path")
            return
        }
        
        // Try multiple possible locations for the script
        let possibleScriptPaths = [
            "\(bundlePath)/Feature Groups/iMessage Server Scraper/MacOS/Launch_Server.sh",
            "\(bundlePath)/Launch_Server.sh",
            "\(bundlePath)/iMessage Server Scraper/MacOS/Launch_Server.sh"
        ]
        
        var scriptPath: String?
        for path in possibleScriptPaths {
            if FileManager.default.fileExists(atPath: path) {
                scriptPath = path
                print("✅ Found Launch_Server.sh at: \(path)")
                break
            }
        }
        
        // Check if script exists
        guard let scriptPath = scriptPath else {
            print("⚠️ Launch_Server.sh not found in any expected location")
            print("Searched in:")
            for path in possibleScriptPaths {
                print("  - \(path)")
            }
            print("Backend will not start - this is normal when running from Swift Package Manager")
            // Don't return, just continue without the backend
            return
        }
        
        // Make script executable
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        } catch {
            print("Could not set executable permissions: \(error)")
        }
        
        process = Process()
        process?.executableURL = URL(fileURLWithPath: "/bin/bash")
        process?.arguments = [scriptPath]
        
        // Set working directory
        process?.currentDirectoryURL = URL(fileURLWithPath: "\(bundlePath)/Feature Groups/iMessage Server Scraper/MacOS")
        
        // Setup pipes for output
        outputPipe = Pipe()
        errorPipe = Pipe()
        process?.standardOutput = outputPipe
        process?.standardError = errorPipe
        
        // Handle output
        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    print("Backend output: \(output)")
                    self?.updateLastMessageTime()
                }
            }
        }
        
        errorPipe?.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    print("Backend error: \(output)")
                }
            }
        }
        
        // Handle process termination
        process?.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.process = nil
                print("Backend process terminated with code: \(process.terminationStatus)")
            }
        }
        
        do {
            try process?.run()
            isRunning = true
            print("✅ Backend started successfully")
            startUpdateTimer()
            updateLastMessageTime() // Initial update
        } catch {
            print("❌ Failed to start backend: \(error)")
            print("ℹ️ App will continue without backend functionality")
            // Set a flag to indicate backend is not available
            isBackendConnected = false
        }
    }
    
    func stopBackend() {
        guard isRunning, let process = process else { return }
        
        stopUpdateTimer()
        process.terminate()
        
        // Force kill if it doesn't terminate gracefully
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.isRunning == true {
                process.interrupt()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if self?.isRunning == true {
                        process.terminate()
                    }
                }
            }
        }
    }
    
    // MARK: - Last Run Time Management
    
    func loadLastRunTime() -> Date? {
        // This method is deprecated - use getLastMessageTime() instead
        return getLastMessageTime()
    }
    
    func saveLastRunTime() {
        // This method is deprecated - timestamps are now based on actual message data
        // No need to save anything as we query the database directly
    }
    
    func getLastMessageTime() -> Date? {
        // Use Swift MessagesDAO instead of Python script
        return MessagesDAO().getLastMessageDate()
    }
    
    func updateLastMessageTime() {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        if let lastMessageTime = getLastMessageTime() {
            self.lastUpdate = formatter.string(from: lastMessageTime)
        } else {
            self.lastUpdate = "Never"
        }
    }
    
    // MARK: - Data Checking and Processing
    
    func checkForNewData() {
        print("🔍 Checking for new data...")
        Task { @MainActor in
            await ImportSyncCoordinator.shared.runIncrementalMessageSync()
            updateLastMessageTime()
        }
    }
    
    // DEPRECATED: Python script execution (not used in production)
    // App uses pure Swift implementation via StartOrchestrator
    func runStartScript() {
        guard let scriptPath = startScriptPath else {
            print("❌ start.py script not found")
            print("🔍 Checking bundle resources...")
            if let bundlePath = Bundle.main.resourcePath {
                print("📁 Bundle path: \(bundlePath)")
                let resourcesDir = "\(bundlePath)/Feature Groups/iMessage Server Scraper/Resources"
                if let files = try? FileManager.default.contentsOfDirectory(atPath: resourcesDir) {
                    print("📄 Available files in Resources directory:")
                    for file in files {
                        print("  - \(file)")
                    }
                }
            }
            return
        }
        
        print("🚀 Running start.py script: \(scriptPath.path)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptPath.path]
        
        // Set working directory to the script's directory
        process.currentDirectoryURL = scriptPath.deletingLastPathComponent()
        
        // Set environment variables
        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = scriptPath.deletingLastPathComponent().path
        process.environment = env
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Handle output
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    print("start.py output: \(output)")
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    print("start.py error: \(output)")
                }
            }
        }
        
        // Handle completion
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                print("✅ start.py completed with code: \(process.terminationStatus)")
                if process.terminationStatus == 0 {
                    // Update last message time display (now based on database)
                    self?.updateLastMessageTime()
                }
            }
        }
        
        do {
            try process.run()
        } catch {
            print("❌ Failed to run start.py: \(error)")
        }
    }
    
    func startUpdateTimer() {
        // Prevent multiple timers from being created
        stopUpdateTimer()
        
        // Update display every 90 seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: 90.0, repeats: true) { [weak self] _ in
            self?.updateLastMessageTime()
        }
    }
    
    func startDataCheckTimer() {
        // Prevent multiple timers from being created
        stopDataCheckTimer()
        
        // Check for new data every 90 seconds
        dataCheckTimer = Timer.scheduledTimer(withTimeInterval: 90.0, repeats: true) { [weak self] _ in
            self?.checkForNewData()
        }
        
        // Also check immediately on startup
        checkForNewData()
    }
    
    func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    func stopDataCheckTimer() {
        dataCheckTimer?.invalidate()
        dataCheckTimer = nil
    }
    
    func openMainWindow() {
        isMainWindowOpen = true
        updateActivationPolicyForMainWindow(isOpen: true)
        
        // Check if window already exists
        if let existingWindow = mainWindow ?? NSApp.windows.first(where: { $0.title == "My CRM - Note Book" }) {
            mainWindow = existingWindow
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create new window if it doesn't exist
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "My CRM - Note Book"
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.isReleasedWhenClosed = false
        
        // Load the full MainCRMView directly
        self.loadFullMainView(into: window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        mainWindow = window
        registerMainWindowObserver(for: window)
    }
    
    func closeMainWindow() {
        isMainWindowOpen = false
        updateActivationPolicyForMainWindow(isOpen: false)
        // Hide the main window
        if let window = mainWindow ?? NSApp.windows.first(where: { $0.title == "My CRM - Note Book" }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            if window.isVisible {
                window.performClose(nil)
            } else {
                window.orderOut(nil)
                finalizeMainWindowClosure()
            }
        }
    }
    
    func loadFullMainView(into window: NSWindow) {
        // Create the full MainCRMView with all environment objects
        // Access the original environment objects from MyCRMApp
        guard let app = MyCRMApp.shared else {
            print("MyCRMApp: No shared app instance found")
            return
        }
        
        // Create a wrapper view that properly manages the StateObjects
        let mainView = MainWindowWrapper(
            appState: app.appState,
            appModel: app.appModel,
            dataProvider: app.dataProvider,
            dragDropManager: app.dragDropManager,
            selectionManager: app.selectionManager,
            hotkeyManager: app.hotkeyManager,
            globalCanvasService: app.globalCanvasService
        )
        
        window.contentView = NSHostingView(rootView: mainView)
    }
    
    private func registerMainWindowObserver(for window: NSWindow) {
        if let observer = mainWindowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        mainWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.finalizeMainWindowClosure()
        }
    }
    
    private func finalizeMainWindowClosure() {
        isMainWindowOpen = false
        updateActivationPolicyForMainWindow(isOpen: false)
        if let observer = mainWindowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            mainWindowCloseObserver = nil
        }
        mainWindow = nil
    }
    
    private func updateActivationPolicyForMainWindow(isOpen: Bool) {
        DispatchQueue.main.async {
            let targetPolicy: NSApplication.ActivationPolicy = isOpen ? .regular : .accessory
            if NSApp.activationPolicy() != targetPolicy {
                NSApp.setActivationPolicy(targetPolicy)
            }
            if isOpen {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    deinit {
        stopBackend()
        stopUpdateTimer()
        stopDataCheckTimer()
    }
}

// MARK: - Main Window Wrapper

struct MainWindowWrapper: View {
    let appState: AppState
    let appModel: AppModel
    let dataProvider: SQLiteDataProvider
    let dragDropManager: DragDropManager
    let selectionManager: SelectionManager
    let hotkeyManager: HotkeyManager
    let globalCanvasService: GlobalCanvasService
    
    var body: some View {
        MainCRMView(appState: appState)
            .environmentObject(appModel)
            .environmentObject(dataProvider)
            .environmentObject(dragDropManager)
            .environmentObject(selectionManager)
            .environmentObject(hotkeyManager)
            .environmentObject(globalCanvasService)
    }
}

// MARK: - App Delegate for Cleanup

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        print("🛑 Application will terminate - starting cleanup...")
        
        // Perform synchronous cleanup
        let semaphore = DispatchSemaphore(value: 0)
        
        Task { @MainActor in
            await AppCleanupService.shared.performCompleteCleanup()
            semaphore.signal()
        }
        
        // Wait for cleanup to complete (max 10 seconds)
        _ = semaphore.wait(timeout: .now() + 10)
        
        print("✅ Cleanup complete - app terminating")
    }
}

@available(macOS 11.0, *)
@main
struct MyCRMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject var appModel = AppModel()
    @StateObject var appState = AppState()
    @StateObject var dataProvider = SQLiteDataProvider()
    // DragDropManager is a singleton, don't use @StateObject
    var dragDropManager: DragDropManager { DragDropManager.shared }
    @StateObject var selectionManager = SelectionManager()
    @StateObject var hotkeyManager = HotkeyManager()
    // GlobalCanvasService is a singleton, don't use @StateObject
    var globalCanvasService: GlobalCanvasService { GlobalCanvasService.shared }
    
    // Static reference to access environment objects from AppModel
    static var shared: MyCRMApp?

    var body: some Scene {
        // Menu bar extra - pure menu bar app
        MenuBarExtra {
            Button("Open Note Book") {
                appModel.openMainWindow()
            }
            .keyboardShortcut("n", modifiers: [.command])
            
            Divider()
            
            if appModel.isRunning {
                Button("Stop Backend") {
                    appModel.stopBackend()
                }
            } else {
                Button("Start Backend") {
                    appModel.startBackend()
                }
            }
            
            Divider()
            
            Button("Settings") {
                appState.showingSettings = true
                appModel.openMainWindow() // Ensure main window is open to show settings
            }
            
            Divider()
            
            Button("Quit") {
                appModel.stopBackend()
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        } label: {
            // Use custom .icns file if it exists; otherwise fall back to an SF Symbol
            if let bundlePath = Bundle.main.path(forResource: "StatusBarIcon", ofType: "icns"),
               let nsImage = NSImage(contentsOfFile: bundlePath) {
                // Configure the image for menu bar display
                let configuredImage = nsImage
                configuredImage.isTemplate = true  // Set as template to adapt to menu bar color scheme
                configuredImage.size = NSSize(width: 18, height: 18) // Smaller size for menu bar
                
                return Image(nsImage: configuredImage)
                    .accessibilityLabel("My CRM")
            } else {
                return Image(systemName: "person.crop.square")
                    .accessibilityLabel("My CRM (fallback icon)")
            }
        }
        .menuBarExtraStyle(.menu)
    }
    
    init() {
        print("MyCRMApp: Initializing...")

        if CommandLine.arguments.contains("--import-messages") {
            let stats = MessagesImporter().run()
            let enrichment = ContactMessageEnrichmentService().run()
            print("💬 CLI import complete: importedNew=\(stats.importedNew) enrichmentUpdated=\(enrichment.contactsUpdated)")
            exit(Int32(stats.importedNew >= 0 ? 0 : 1))
        }
        
        // Set static reference for access from AppModel
        MyCRMApp.shared = self
        
        // Initialize app components with proper delays to avoid StateObject access during init
        print("MyCRMApp: Starting automatic initialization...")
        
        // Connect dataProvider to GlobalCanvasService for contact lookups
        let dataProviderRef = dataProvider
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("MyCRMApp: Connecting dataProvider to GlobalCanvasService...")
            GlobalCanvasService.shared.setDataProvider(dataProviderRef)
            print("MyCRMApp: Connected dataProvider to GlobalCanvasService")
        }
        
        // Kick off orchestrator - now using pure Swift implementation
        // Note: Permissions are handled by StartOrchestrator, no need to duplicate here
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            // Enable both Swift contacts and messages import - Python completely disabled!
            StartOrchestrator.shared.run(usePythonFallback: false, useSwiftContactsImport: true, useSwiftMessagesImport: true)
        }
        
        // Automatically open the main window when the app launches
        let appModel = self.appModel
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            print("MyCRMApp: Auto-opening main window...")
            appModel.openMainWindow()
        }

        // Monitor chat.db for new messages and run periodic sync fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            ChatDBMonitor.shared.start()
            appModel.startDataCheckTimer()
        }
    }
}


