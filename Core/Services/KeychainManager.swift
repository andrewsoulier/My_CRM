import Foundation
import Security

/// Manages secure storage of API keys and sensitive data in macOS Keychain
class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    // Service identifier for our app's keychain items
    private let serviceIdentifier = "com.mycrm.apikeys"
    
    // MARK: - Public API
    
    /// Save an API key for a specific provider
    /// - Parameters:
    ///   - key: The API key to store
    ///   - provider: The provider name (e.g., "openai", "gemini", "claude")
    /// - Returns: True if successful, false otherwise
    func saveAPIKey(_ key: String, for provider: String) -> Bool {
        // Delete existing key first to avoid duplicates
        deleteAPIKey(for: provider)
        
        guard let keyData = key.data(using: .utf8) else {
            print("❌ KeychainManager: Failed to convert key to data")
            return false
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: provider,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("🔐 KeychainManager: Successfully saved API key for \(provider)")
            return true
        } else {
            print("❌ KeychainManager: Failed to save API key for \(provider), status: \(status)")
            return false
        }
    }
    
    /// Retrieve an API key for a specific provider
    /// - Parameter provider: The provider name
    /// - Returns: The API key if found, nil otherwise
    func retrieveAPIKey(for provider: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: provider,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let keyData = result as? Data,
           let key = String(data: keyData, encoding: .utf8) {
            print("🔐 KeychainManager: Successfully retrieved API key for \(provider)")
            return key
        } else if status == errSecItemNotFound {
            print("🔐 KeychainManager: No API key found for \(provider)")
            return nil
        } else {
            print("❌ KeychainManager: Failed to retrieve API key for \(provider), status: \(status)")
            return nil
        }
    }
    
    /// Delete an API key for a specific provider
    /// - Parameter provider: The provider name
    /// - Returns: True if successful or item not found, false otherwise
    func deleteAPIKey(for provider: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: provider
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess || status == errSecItemNotFound {
            print("🔐 KeychainManager: Successfully deleted API key for \(provider)")
            return true
        } else {
            print("❌ KeychainManager: Failed to delete API key for \(provider), status: \(status)")
            return false
        }
    }
    
    /// Check if an API key exists for a provider
    /// - Parameter provider: The provider name
    /// - Returns: True if a key exists, false otherwise
    func hasAPIKey(for provider: String) -> Bool {
        return retrieveAPIKey(for: provider) != nil
    }
    
    /// List all providers that have stored API keys
    /// - Returns: Array of provider names
    func listProvidersWithKeys() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let items = result as? [[String: Any]] {
            let providers = items.compactMap { $0[kSecAttrAccount as String] as? String }
            return providers
        }
        
        return []
    }
}



