import SwiftUI
import SQLite3
import Contacts
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @StateObject private var settingsManager = SettingsManager.shared
    @State private var chatGPTService = ChatGPTService()
    
    @State private var showingFilePicker = false
    @State private var showingContactPicker = false
    @State private var isSwitchingDatabase = false
    
    private let densityOptions = ["Compact", "Normal", "Relaxed"]
    
    var body: some View {
        let _ = print("🔧 SettingsView: body computed")
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") {
                    appState.showingSettings = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Settings Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Database Settings
                    SettingsSection(title: "Database") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Database Path")
                                .font(.headline)
                            
                            HStack {
                                TextField("Path to my_crm.db", text: $settingsManager.settings.database.path)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: settingsManager.settings.database.path) { _, newValue in
                                        settingsManager.updateDatabasePath(newValue)
                                    }
                                    .disabled(isSwitchingDatabase)
                                
                                if isSwitchingDatabase {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 20, height: 20)
                                }
                                
                                Button("Browse") {
                                    showingFilePicker = true
                                }
                                .buttonStyle(.bordered)
                                .disabled(isSwitchingDatabase)
                            }
                            
                            Text("Path to your SQLite database file")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // Connection Status
                            HStack {
                                Circle()
                                    .fill(dataProvider.isConnected() ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                
                                Text(dataProvider.isConnected() ? "Connected" : "Not Connected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                            }
                        }
                    }
                    
                    // VCF Settings
                    SettingsSection(title: "VCF Import") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Profile VCF Path")
                                .font(.headline)
                            
                            HStack {
                                TextField("Selected Contact", text: $settingsManager.settings.user.phone)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(true)
                                    .onChange(of: settingsManager.settings.user.phone) { _, newValue in
                                        settingsManager.updateVCFPath(newValue)
                                    }
                                
                                Button("Browse") {
                                    showingContactPicker = true
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            Text("Select a contact from your macOS Contacts app")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    
                    // UI Settings
                    SettingsSection(title: "Interface") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("UI Density")
                                .font(.headline)
                            
                            Picker("Density", selection: $settingsManager.settings.preferences.uiDensity) {
                                ForEach(densityOptions, id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: settingsManager.settings.preferences.uiDensity) { _, newValue in
                                settingsManager.updateUIDensity(newValue)
                            }
                            
                            Text("Adjust the spacing and size of UI elements")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // AI Integration Section
                    SettingsSection(title: "AI Integration") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ChatGPT Connection")
                                .font(.headline)
                            
                            HStack {
                                Circle()
                                    .fill(chatGPTService.isConnected ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                
                                Text(chatGPTService.connectionStatus)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                if chatGPTService.isConnected {
                                    Button("Disconnect") {
                                        Task {
                                            await chatGPTService.disconnectFromChatGPT()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    VStack(spacing: 8) {
                                        Button("Log in to ChatGPT") {
                                            print("🔧 SettingsView: 'Log in to ChatGPT' button clicked")
                                            NSLog("🔧 SettingsView: 'Log in to ChatGPT' button clicked")
                                            // Visual feedback
                                            chatGPTService.connectionStatus = "Connecting..."
                                            chatGPTService.lastError = "Button clicked - connecting..."
                                            Task {
                                                print("🔧 SettingsView: Starting async connectToChatGPT task")
                                                NSLog("🔧 SettingsView: Starting async connectToChatGPT task")
                                                await chatGPTService.connectToChatGPT()
                                                print("🔧 SettingsView: connectToChatGPT task completed")
                                                NSLog("🔧 SettingsView: connectToChatGPT task completed")
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        
                                        Text("API key configuration coming soon")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            if let error = chatGPTService.lastError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            
                            Text("Connect to ChatGPT to enable AI-powered invite analysis and task suggestions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Debug Section
                    SettingsSection(title: "Debug") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Debug Points")
                                .font(.headline)
                            
                            Toggle("Enable Debug Points", isOn: $settingsManager.settings.developer.debugPoints)
                                .toggleStyle(.switch)
                                .onChange(of: settingsManager.settings.developer.debugPoints) { _, newValue in
                                    settingsManager.updateDebugPoints(newValue)
                                }
                            
                            Text("Enable debug point logging for troubleshooting")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Divider()
                                .padding(.vertical, 8)
                            
                            Toggle("Show Canvas Element Points", isOn: $settingsManager.settings.developer.showCanvasElementPoints)
                                .toggleStyle(.switch)
                                .onChange(of: settingsManager.settings.developer.showCanvasElementPoints) { _, newValue in
                                    settingsManager.updateCanvasElementPoints(newValue)
                                }
                            
                            Text("Display debug points for canvas elements")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Divider()
                                .padding(.vertical, 8)
                            
                            Text("Settings File")
                                .font(.headline)
                            
                            Button("Open Settings File in Text Editor") {
                                settingsManager.openSettingsFileInEditor()
                            }
                            .buttonStyle(.bordered)
                            
                            Text("Opens the settings file at: \(settingsManager.getSettingsFilePath())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
        .onAppear {
            // Settings are automatically loaded by SettingsManager
            print("🔧 SettingsView: onAppear - settings loaded from file")
            
            // Check ChatGPT connection status
            print("🔧 SettingsView: onAppear - about to check ChatGPT connection status")
            Task {
                print("🔧 SettingsView: onAppear - starting checkConnectionStatus task")
                await chatGPTService.checkConnectionStatus()
                print("🔧 SettingsView: onAppear - checkConnectionStatus task completed")
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "db") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleDatabaseFileSelection(result)
        }
        .sheet(isPresented: $showingContactPicker) {
            ContactPickerView(selectedContact: $settingsManager.settings.user.phone)
        }
    }
    
    private func handleDatabaseFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                // Validate that the file exists and is readable
                guard FileManager.default.fileExists(atPath: url.path) else {
                    appState.showError("Selected file does not exist")
                    return
                }
                
                // Check if it's a valid SQLite database by trying to open it
                var tempDb: OpaquePointer?
                let result = sqlite3_open(url.path, &tempDb)
                
                if result == SQLITE_OK {
                    sqlite3_close(tempDb)
                    
                    // Show loading indicator
                    isSwitchingDatabase = true
                    appState.showMessage("Switching to new database...")
                    
                    // Switch to the new database
                    Task {
                        do {
                            try await dataProvider.switchDatabase(to: url.path)
                            await MainActor.run {
                                isSwitchingDatabase = false
                                appState.showMessage("Successfully switched to new database. Loaded \(dataProvider.contacts.count) contacts and \(dataProvider.groups.count) groups.")
                            }
                        } catch {
                            await MainActor.run {
                                isSwitchingDatabase = false
                                appState.showError("Failed to switch database: \(error.localizedDescription)")
                            }
                        }
                    }
                } else {
                    appState.showError("Selected file is not a valid SQLite database")
                }
            }
        case .failure(let error):
            appState.showError("Failed to select database file: \(error.localizedDescription)")
        }
    }
    
    
}

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            content
                .padding()
                .background(Color(NSColor.controlColor))
                .cornerRadius(8)
        }
    }
}

struct ContactPickerView: View {
    @Binding var selectedContact: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select Contact")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Choose a contact from your macOS Contacts app")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Open Contacts App") {
                openContactsApp()
            }
            .buttonStyle(.borderedProminent)
            
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 300, height: 200)
    }
    
    private func openContactsApp() {
        // Open the Contacts app
        if let url = URL(string: "x-apple-addressbook://") {
            NSWorkspace.shared.open(url)
        }
        dismiss()
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(SQLiteDataProvider())
}
