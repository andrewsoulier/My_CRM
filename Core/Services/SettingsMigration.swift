import Foundation

/// One-time migration utility to transfer settings from old User_Preferences to User_Settings.json
enum SettingsMigration {
    
    /// Perform migration from old User_Preferences format to new User_Settings.json
    static func migrateIfNeeded() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let myCRMAppSupport = appSupport.appendingPathComponent("My_CRM")
        
        let oldPreferencesURL = myCRMAppSupport.appendingPathComponent("User_Preferences")
        let newSettingsURL = myCRMAppSupport.appendingPathComponent("User_Settings.json")
        
        // If new settings file already exists, no migration needed
        if FileManager.default.fileExists(atPath: newSettingsURL.path) {
            print("📁 SettingsMigration: User_Settings.json already exists, no migration needed")
            
            // Optional: Archive old preferences file for safety
            if FileManager.default.fileExists(atPath: oldPreferencesURL.path) {
                let archiveURL = myCRMAppSupport.appendingPathComponent("User_Preferences.backup")
                do {
                    if !FileManager.default.fileExists(atPath: archiveURL.path) {
                        try FileManager.default.copyItem(at: oldPreferencesURL, to: archiveURL)
                        print("📦 SettingsMigration: Backed up old User_Preferences to User_Preferences.backup")
                    }
                } catch {
                    print("⚠️ SettingsMigration: Failed to backup old preferences: \(error)")
                }
            }
            return
        }
        
        // Check if old preferences file exists
        guard FileManager.default.fileExists(atPath: oldPreferencesURL.path) else {
            print("📁 SettingsMigration: No old User_Preferences file found, skipping migration")
            return
        }
        
        print("🔄 SettingsMigration: Starting migration from User_Preferences to User_Settings.json")
        
        do {
            // Read old preferences
            let data = try Data(contentsOf: oldPreferencesURL)
            let oldPrefs = try JSONDecoder().decode(UserSettings.self, from: data)
            
            // Update SettingsManager with migrated data
            SettingsManager.shared.settings = oldPrefs
            SettingsManager.shared.saveSettings()
            
            print("✅ SettingsMigration: Successfully migrated settings to User_Settings.json")
            
            // Backup the old file
            let backupURL = myCRMAppSupport.appendingPathComponent("User_Preferences.migrated")
            try? FileManager.default.copyItem(at: oldPreferencesURL, to: backupURL)
            print("📦 SettingsMigration: Backed up old preferences as User_Preferences.migrated")
            
        } catch {
            print("❌ SettingsMigration: Failed to migrate settings: \(error)")
            print("   Will use default settings instead")
        }
    }
}

