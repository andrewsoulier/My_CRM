import Foundation
import Combine

/// Manages AI providers and routes requests to the active provider
class AIServiceManager: ObservableObject {
    static let shared = AIServiceManager()
    
    @Published var connectionStatus: [AIProviderType: AIConnectionStatus] = [:]
    @Published var selectedProvider: AIProviderType?
    
    private let settingsManager = SettingsManager.shared
    private let keychain = KeychainManager.shared
    
    private var providers: [AIProviderType: AIProvider] = [:]
    
    private init() {
        // Initialize all providers
        providers[.openai] = OpenAIProvider()
        providers[.gemini] = GeminiProvider()
        providers[.claude] = ClaudeProvider()
        
        // Initialize connection status
        for providerType in AIProviderType.allCases {
            connectionStatus[providerType] = .disconnected
        }
        
        // Load selected provider from settings
        if !settingsManager.settings.ai.selectedProvider.isEmpty,
           let providerType = AIProviderType(rawValue: settingsManager.settings.ai.selectedProvider) {
            selectedProvider = providerType
        }
        
        print("🤖 AIServiceManager: Initialized with \(providers.count) providers")
    }
    
    // MARK: - Provider Management
    
    /// Get a specific provider
    func getProvider(_ type: AIProviderType) -> AIProvider? {
        return providers[type]
    }
    
    /// Get the currently selected provider
    func getActiveProvider() -> AIProvider? {
        guard let selectedProvider = selectedProvider else {
            return nil
        }
        return providers[selectedProvider]
    }
    
    /// Select a provider as the active one
    func selectProvider(_ type: AIProviderType) {
        selectedProvider = type
        settingsManager.settings.ai.selectedProvider = type.rawValue
        settingsManager.saveSettings()
        print("🤖 AIServiceManager: Selected provider: \(type.displayName)")
    }
    
    // MARK: - API Key Management
    
    /// Save an API key for a provider
    func saveAPIKey(_ key: String, for providerType: AIProviderType) -> Bool {
        let success = keychain.saveAPIKey(key, for: providerType.rawValue)
        if success {
            // Add to enabled providers if not already present
            if !settingsManager.settings.ai.enabledProviders.contains(providerType.rawValue) {
                settingsManager.settings.ai.enabledProviders.append(providerType.rawValue)
                settingsManager.saveSettings()
            }
            print("🤖 AIServiceManager: Saved API key for \(providerType.displayName)")
        }
        return success
    }
    
    /// Remove an API key for a provider
    func removeAPIKey(for providerType: AIProviderType) -> Bool {
        let success = keychain.deleteAPIKey(for: providerType.rawValue)
        if success {
            // Remove from enabled providers
            settingsManager.settings.ai.enabledProviders.removeAll { $0 == providerType.rawValue }
            settingsManager.saveSettings()
            
            // Clear connection status
            connectionStatus[providerType] = .disconnected
            
            // If this was the selected provider, clear selection
            if selectedProvider == providerType {
                selectedProvider = nil
                settingsManager.settings.ai.selectedProvider = ""
                settingsManager.saveSettings()
            }
            
            print("🤖 AIServiceManager: Removed API key for \(providerType.displayName)")
        }
        return success
    }
    
    /// Check if a provider has an API key configured
    func hasAPIKey(for providerType: AIProviderType) -> Bool {
        return keychain.hasAPIKey(for: providerType.rawValue)
    }
    
    // MARK: - Connection Testing
    
    /// Test connection for a specific provider
    @MainActor
    func testConnection(for providerType: AIProviderType) async {
        guard let provider = providers[providerType] else {
            connectionStatus[providerType] = .error(message: "Provider not found")
            return
        }
        
        connectionStatus[providerType] = .testing
        print("🤖 AIServiceManager: Testing connection for \(providerType.displayName)...")
        
        let result = await provider.testConnection()
        
        switch result {
        case .success(let message):
            let models = provider.getAvailableModels()
            let modelInfo = models.first ?? "Unknown"
            connectionStatus[providerType] = .connected(modelInfo: modelInfo)
            print("✅ AIServiceManager: \(message)")
        case .failure(let error):
            connectionStatus[providerType] = .error(message: error.localizedDescription ?? "Connection failed")
            print("❌ AIServiceManager: Connection failed for \(providerType.displayName): \(error.localizedDescription ?? "Unknown error")")
        }
    }
    
    // MARK: - AI Queries
    
    /// Send a chat completion request to the active provider
    func sendChatCompletion(
        messages: [ChatMessage],
        temperature: Double = 0.7,
        maxTokens: Int? = nil
    ) async -> Result<String, AIProviderError> {
        guard let provider = getActiveProvider() else {
            return .failure(.notConfigured)
        }
        
        print("🤖 AIServiceManager: Sending chat completion to \(provider.providerType.displayName)")
        return await provider.sendChatCompletion(messages: messages, temperature: temperature, maxTokens: maxTokens)
    }
    
    /// Send a simple text query to the active provider
    func sendQuery(_ text: String, systemPrompt: String? = nil) async -> Result<String, AIProviderError> {
        var messages: [ChatMessage] = []
        
        if let systemPrompt = systemPrompt {
            messages.append(ChatMessage(role: "system", content: systemPrompt))
        }
        
        messages.append(ChatMessage(role: "user", content: text))
        
        return await sendChatCompletion(messages: messages)
    }
    
    // MARK: - Utility Methods
    
    /// Get list of configured providers
    func getConfiguredProviders() -> [AIProviderType] {
        return AIProviderType.allCases.filter { hasAPIKey(for: $0) }
    }
    
    /// Get connection status for a provider
    func getConnectionStatus(for providerType: AIProviderType) -> AIConnectionStatus {
        return connectionStatus[providerType] ?? .disconnected
    }
}



