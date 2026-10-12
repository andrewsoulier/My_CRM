import SwiftUI
import Contacts
import Combine

struct PreferencesView: View {
    @State private var databasePath: String = ""
    @State private var databaseName: String = ""
    @State private var userName: String = ""
    @State private var userPhone: String = ""
    @State private var userEmail: String = ""
    @State private var theme: String = "light"
    @State private var notifications: Bool = true
    @State private var autoSync: Bool = true
    @State private var runAtLogin: Bool = true
    @State private var showingFilePicker = false
    @State private var showingContactPicker = false
    @State private var showingSaveAlert = false
    @State private var saveMessage = ""

    
    private let preferencesPath: String
    
    init() {
        // Use Application Support for writable storage, but also copy to app bundle for Python scripts
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let myCRMAppSupport = appSupport?.appendingPathComponent("My_CRM")
        self.preferencesPath = myCRMAppSupport?.appendingPathComponent("User_Preferences").path ?? ""
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("My CRM Preferences")
                .font(.title)
                .fontWeight(.bold)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Database Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Database Settings")
                            .font(.headline)
                            .padding(.bottom, 5)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Database Path:")
                                Spacer()
                                Button("Select File") {
                                    selectDatabaseFile()
                                }
                            }
                            TextField("Database path", text: $databasePath)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            HStack {
                                Text("Database Name:")
                                Spacer()
                            }
                            TextField("Database name", text: $databaseName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // User Information Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("User Information")
                            .font(.headline)
                            .padding(.bottom, 5)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Name:")
                                Spacer()
                                Button("Select Contact") {
                                    selectContactFromContactsApp()
                                }
                            }
                            TextField("Full name", text: $userName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            HStack {
                                Text("Phone:")
                                Spacer()
                            }
                            TextField("Phone number", text: $userPhone)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            HStack {
                                Text("Email:")
                                Spacer()
                            }
                            TextField("Email address", text: $userEmail)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Preferences Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Application Preferences")
                            .font(.headline)
                            .padding(.bottom, 5)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Theme:")
                                Spacer()
                                Picker("Theme", selection: $theme) {
                                    Text("Light").tag("light")
                                    Text("Dark").tag("dark")
                                    Text("System").tag("system")
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .frame(width: 200)
                            }
                            
                            HStack {
                                Text("Notifications:")
                                Spacer()
                                Toggle("", isOn: $notifications)
                            }
                            
                            HStack {
                                Text("Auto Sync:")
                                Spacer()
                                Toggle("", isOn: $autoSync)
                            }
                            
                            HStack {
                                Text("Run at Login:")
                                Spacer()
                                Toggle("", isOn: $runAtLogin)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            
            HStack {
                Spacer()
                
                Button("Save") {
                    savePreferences()
                    // Close the window after saving
                    if let window = NSApp.windows.first(where: { $0.title == "My CRM Preferences" }) {
                        window.close()
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .alert(isPresented: $showingSaveAlert) {
            Alert(
                title: Text("Preferences"),
                message: Text(saveMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            loadPreferences()
        }
    }
    
    private func selectDatabaseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.database]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                databasePath = url.path
                databaseName = url.lastPathComponent
            }
        }
    }
    
    private func selectContactFromContactsApp() {
        // Open Contacts app and let user select a contact
        let script = """
        tell application "Contacts"
            activate
        end tell
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            saveMessage = "Please select a contact in the Contacts app, then manually copy the information to the fields above."
            showingSaveAlert = true
        } catch {
            saveMessage = "Failed to open Contacts app: \(error.localizedDescription)"
            showingSaveAlert = true
        }
    }
    
    private func loadPreferences() {
        // First try to load from Application Support (writable location)
        if !preferencesPath.isEmpty && FileManager.default.fileExists(atPath: preferencesPath) {
            loadFromPath(preferencesPath)
            return
        }
        
        // If not found in Application Support, try to load from app bundle
        if let bundlePath = Bundle.main.resourcePath {
            let bundlePrefsPath = "\(bundlePath)/Feature Groups/iMessage Server Scraper/Resources/User_Preferences"
            if FileManager.default.fileExists(atPath: bundlePrefsPath) {
                loadFromPath(bundlePrefsPath)
                return
            }
        }
        
        print("No preferences file found")
    }
    
    private func loadFromPath(_ path: String) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let preferences = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let database = preferences?["database"] as? [String: Any] {
                databasePath = database["path"] as? String ?? ""
                databaseName = database["name"] as? String ?? ""
            }
            
            if let user = preferences?["user"] as? [String: Any] {
                userName = user["name"] as? String ?? ""
                userPhone = user["phone"] as? String ?? ""
                userEmail = user["email"] as? String ?? ""
            }
            
            if let prefs = preferences?["preferences"] as? [String: Any] {
                theme = prefs["theme"] as? String ?? "light"
                notifications = prefs["notifications"] as? Bool ?? true
                autoSync = prefs["auto_sync"] as? Bool ?? true
                runAtLogin = prefs["run_at_login"] as? Bool ?? true
            }
        } catch {
            print("Failed to load preferences from \(path): \(error)")
        }
    }
    

    
    private func savePreferences() {
        guard !preferencesPath.isEmpty else {
            saveMessage = "Error: Could not determine preferences file path"
            showingSaveAlert = true
            return
        }
        
        // Ensure the directory exists
        let preferencesURL = URL(fileURLWithPath: preferencesPath)
        let directoryURL = preferencesURL.deletingLastPathComponent()
        
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            saveMessage = "Failed to create preferences directory: \(error.localizedDescription)"
            showingSaveAlert = true
            return
        }
        
        let preferences: [String: Any] = [
            "database": [
                "path": databasePath,
                "name": databaseName
            ],
            "user": [
                "name": userName,
                "phone": userPhone,
                "email": userEmail
            ],
            "preferences": [
                "theme": theme,
                "notifications": notifications,
                "auto_sync": autoSync,
                "log_level": "info", // Skip log_level as requested
                "run_at_login": runAtLogin
            ]
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: preferences, options: .prettyPrinted)
            
            // Save to Application Support (writable location)
            try data.write(to: preferencesURL)
            
            // Also copy to app bundle location for Python scripts
            if let bundlePath = Bundle.main.resourcePath {
                let bundlePrefsPath = "\(bundlePath)/Feature Groups/iMessage Server Scraper/Resources/User_Preferences"
                try data.write(to: URL(fileURLWithPath: bundlePrefsPath))
            }
            
            saveMessage = "Preferences saved successfully!"
            showingSaveAlert = true
        } catch {
            saveMessage = "Failed to save preferences: \(error.localizedDescription)"
            showingSaveAlert = true
        }
    }
}

#Preview {
    PreferencesView()
}
