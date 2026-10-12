import SwiftUI
import UserNotifications

struct MainCRMView: View {
    @ObservedObject var appState: AppState
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var dragDropManager: DragDropManager
    @EnvironmentObject var selectionManager: SelectionManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    
    @State private var showingWelcome = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    
    // Initializer to accept injected AppState
    init(appState: AppState) {
        self.appState = appState
    }
    
    var body: some View {
        ContentView()
            .environmentObject(appState)
            .environmentObject(dataProvider)
            .environmentObject(dragDropManager)
            .environmentObject(selectionManager)
            .environmentObject(hotkeyManager)
            .environmentObject(globalCanvasService)
            .onAppear {
                // Initialize hotkey manager
                hotkeyManager.registerDefaultHotkeys()
                
                // Show welcome screen on first run
                if !hasSeenWelcome {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showingWelcome = true
                    }
                }
            }
            .task {
                // Connect to the actual database on app launch
                await connectToDatabase()
                
                // Request notification permissions for Quick Send
                await requestNotificationPermissions()
            }
            .sheet(isPresented: $showingWelcome) {
                WelcomeView(isPresented: $showingWelcome)
            }
    }
    
    private func connectToDatabase() async {
        // Get database path from user settings
        let proposedPath = dataProvider.getUserDatabasePath()
        
        // Ensure the path is valid, creating default location if needed
        let databasePath = dataProvider.ensureValidDatabasePath(proposedPath)
        
        do {
            // Connect to database and load data
            try await dataProvider.connectToDatabase(path: databasePath)
            print("✅ Successfully connected to database at: \(databasePath)")
            
            // NOW set up the observers (after data is loaded from database)
            print("🔌 Setting up ViewModels observers...")
            await globalCanvasService.contactsViewModel.setupDataProviderObserver(dataProvider, sortOption: appState.sortOption)
            await globalCanvasService.groupsViewModel.setupDataProviderObserver(dataProvider)
            print("✅ ViewModels observers setup complete")
            
            // Trigger initial sync from the loaded data
            print("🔄 Triggering initial sync from dataProvider to ViewModels...")
            await globalCanvasService.contactsViewModel.syncFromProvider(dataProvider, sortOption: appState.sortOption)
            await globalCanvasService.groupsViewModel.syncFromProvider(dataProvider)
            print("✅ Initial sync complete")
            
        } catch {
            print("❌ Failed to connect to database at: \(databasePath)")
            print("Error: \(error.localizedDescription)")
            
            // Show error to user
            await MainActor.run {
                appState.showError("Failed to connect to database at: \(databasePath). Please check the database path in Settings.")
            }
        }
    }
    
    private func requestNotificationPermissions() async {
        let center = UNUserNotificationCenter.current()
        
        // Check current authorization status first
        let settings = await center.notificationSettings()
        
        // Only request if not yet determined
        if settings.authorizationStatus == .authorized {
            print("✅ Notification permission already granted, skipping request")
            return
        } else if settings.authorizationStatus == .denied {
            print("⚠️ Notification permission previously denied, skipping request")
            return
        }
        
        // Status is .notDetermined, so request permission
        print("🔔 Requesting notification permission...")
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                print("✅ Notification permission granted")
            } else {
                print("⚠️ Notification permission denied")
            }
        } catch {
            print("❌ Error requesting notification permission: \(error)")
        }
    }
}

#Preview {
    MainCRMView(appState: AppState())
}
