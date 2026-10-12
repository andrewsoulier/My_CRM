import SwiftUI
import AppKit

// Settings view ONLY. Do not declare @main or MyCRMApp here.
struct AppSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var aiService = AIServiceManager.shared
    @State private var showingFilePicker = false
    @State private var showingAISetup: AIProviderType?
    @State private var manualAPIKey: [AIProviderType: String] = [:]
    @State private var showManualEntry: [AIProviderType: Bool] = [:]
    @State private var showingResetConfirmation = false
    
    var body: some View {
        Form {
            Section("Database") {
                HStack {
                    Text(settingsManager.settings.database.path.isEmpty ? "No database selected" : settingsManager.settings.database.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { 
                        showingFilePicker = true
                    }
                }
            }

            Section("User Information") {
                HStack {
                    Text("Name:")
                    TextField("Enter your name", text: $settingsManager.settings.user.name)
                        .onChange(of: settingsManager.settings.user.name) { _ in
                            settingsManager.saveSettings()
                        }
                }
                
                HStack {
                    Text("Phone:")
                    TextField("Enter your phone", text: $settingsManager.settings.user.phone)
                        .onChange(of: settingsManager.settings.user.phone) { _ in
                            settingsManager.saveSettings()
                        }
                }
                
                HStack {
                    Text("Email:")
                    TextField("Enter your email", text: $settingsManager.settings.user.email)
                        .onChange(of: settingsManager.settings.user.email) { _ in
                            settingsManager.saveSettings()
                        }
                }
            }

            Section("Preferences") {
                Toggle("Notifications", isOn: $settingsManager.settings.preferences.notifications)
                    .onChange(of: settingsManager.settings.preferences.notifications) { _ in
                        settingsManager.saveSettings()
                    }
                
                Toggle("Auto Sync", isOn: $settingsManager.settings.preferences.autoSync)
                    .onChange(of: settingsManager.settings.preferences.autoSync) { _ in
                        settingsManager.saveSettings()
                    }
                
                Toggle("Run at Login", isOn: $settingsManager.settings.preferences.runAtLogin)
                    .onChange(of: settingsManager.settings.preferences.runAtLogin) { _ in
                        settingsManager.saveSettings()
                    }
                
                Picker("Theme", selection: $settingsManager.settings.preferences.theme) {
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("Auto").tag("auto")
                }
                .onChange(of: settingsManager.settings.preferences.theme) { _ in
                    settingsManager.saveSettings()
                }
                
                Picker("Log Level", selection: $settingsManager.settings.preferences.logLevel) {
                    Text("Debug").tag("debug")
                    Text("Info").tag("info")
                    Text("Warning").tag("warning")
                    Text("Error").tag("error")
                }
                .onChange(of: settingsManager.settings.preferences.logLevel) { _ in
                    settingsManager.saveSettings()
                }
            }

            Section("AI Integration") {
                Text("Connect to AI services to enable intelligent features")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                ForEach(AIProviderType.allCases, id: \.self) { provider in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(provider.displayName)
                                    .font(.headline)
                                Text(provider.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if aiService.hasAPIKey(for: provider) {
                                // Provider is configured
                                statusBadge(for: provider)
                                
                                Menu {
                                    Button("Test Connection") {
                                        Task {
                                            await aiService.testConnection(for: provider)
                                        }
                                    }
                                    
                                    Button("Change Key") {
                                        showingAISetup = provider
                                    }
                                    
                                    Divider()
                                    
                                    Button("Remove Key", role: .destructive) {
                                        _ = aiService.removeAPIKey(for: provider)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .frame(width: 24)
                            } else {
                                // Provider not configured
                                Button("Connect") {
                                    showingAISetup = provider
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                
                                Button("Manual") {
                                    showManualEntry[provider] = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        
                        // Manual entry field (collapsed by default)
                        if showManualEntry[provider] == true {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    SecureField("Enter API Key", text: Binding(
                                        get: { manualAPIKey[provider] ?? "" },
                                        set: { manualAPIKey[provider] = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.caption, design: .monospaced))
                                    
                                    Button("Save") {
                                        if let key = manualAPIKey[provider], !key.isEmpty {
                                            let saved = aiService.saveAPIKey(key, for: provider)
                                            if saved {
                                                Task {
                                                    await aiService.testConnection(for: provider)
                                                    await MainActor.run {
                                                        manualAPIKey[provider] = ""
                                                        showManualEntry[provider] = false
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .disabled(manualAPIKey[provider]?.isEmpty ?? true)
                                    
                                    Button("Cancel") {
                                        showManualEntry[provider] = false
                                        manualAPIKey[provider] = ""
                                    }
                                }
                                
                                Link("Get API Key →", destination: URL(string: provider.apiKeyURL)!)
                                    .font(.caption2)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                if !aiService.getConfiguredProviders().isEmpty {
                    Divider()
                    
                    Picker("Active Provider", selection: Binding(
                        get: { aiService.selectedProvider ?? AIProviderType.allCases.first! },
                        set: { aiService.selectProvider($0) }
                    )) {
                        ForEach(aiService.getConfiguredProviders(), id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                }
            }
            
            Section("Developer") {
                Toggle("Developer Mode", isOn: Binding(
                    get: { settingsManager.settings.developer.developerMode },
                    set: { settingsManager.updateDeveloperMode($0) }
                ))
                
                Toggle("Debug Points", isOn: $settingsManager.settings.developer.debugPoints)
                    .onChange(of: settingsManager.settings.developer.debugPoints) { _ in
                        settingsManager.updateDebugPoints(settingsManager.settings.developer.debugPoints)
                    }
                
                Toggle("Show Element Coordinates", isOn: $settingsManager.settings.developer.showElementCoordinates)
                    .onChange(of: settingsManager.settings.developer.showElementCoordinates) { _ in
                        settingsManager.saveSettings()
                    }
                
                Toggle("Show Canvas Element Points", isOn: $settingsManager.settings.developer.showCanvasElementPoints)
                    .onChange(of: settingsManager.settings.developer.showCanvasElementPoints) { _ in
                        settingsManager.updateCanvasElementPoints(settingsManager.settings.developer.showCanvasElementPoints)
                    }
            }

            Section("Settings File") {
                HStack {
                    Text("Location:")
                    Text(settingsManager.getSettingsFilePath())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Open in Editor") {
                        settingsManager.openSettingsFileInEditor()
                    }
                }
            }
            
            Section("Troubleshooting") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("If you're experiencing issues, you can reset settings to defaults.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button("Reset to Defaults") {
                            showingResetConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Open Database Location") {
                            openDatabaseLocation()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            Section("About") {
                HStack {
                    Text("Version:")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Build:")
                    Spacer()
                    Text(buildNumber)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Bundle ID:")
                    Spacer()
                    Text(bundleIdentifier)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .frame(minWidth: 520)
        .padding()
        .alert("Reset to Defaults?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their default values. Your database and contacts will not be affected.")
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            handleDatabaseFileSelection(result)
        }
        .sheet(item: $showingAISetup) { provider in
            AIProviderSetupView(provider: provider, isPresented: Binding(
                get: { showingAISetup != nil },
                set: { if !$0 { showingAISetup = nil } }
            ))
        }
    }
    
    @ViewBuilder
    private func statusBadge(for provider: AIProviderType) -> some View {
        let status = aiService.getConnectionStatus(for: provider)
        
        HStack(spacing: 4) {
            switch status {
            case .connected(let modelInfo):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .testing:
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text("Testing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Error")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .disconnected:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
                Text("Not connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                
                // Update the settings with the new database path
                settingsManager.updateDatabasePath(url.path)
                appState.showMessage("Database file selected successfully")
            }
        case .failure(let error):
            appState.showError("Failed to select database file: \(error.localizedDescription)")
        }
    }
    
    private func resetToDefaults() {
        settingsManager.settings = UserSettings()
        settingsManager.saveSettings()
        appState.showMessage("Settings reset to defaults")
    }
    
    private func openDatabaseLocation() {
        let dbPath = settingsManager.settings.database.path
        let dbURL = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
        NSWorkspace.shared.open(dbURL)
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    private var bundleIdentifier: String {
        Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String ?? "Unknown"
    }
}
