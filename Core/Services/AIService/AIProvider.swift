import Foundation

/// Protocol defining the interface for AI provider implementations
protocol AIProvider {
    /// The provider's unique identifier
    var providerType: AIProviderType { get }
    
    /// Check if the provider is configured with an API key
    var isConfigured: Bool { get }
    
    /// Test the connection and validate the API key
    /// - Returns: Success/failure with optional error message
    func testConnection() async -> Result<String, AIProviderError>
    
    /// Send a chat completion request
    /// - Parameters:
    ///   - messages: Array of chat messages
    ///   - temperature: Sampling temperature (0-1)
    ///   - maxTokens: Maximum tokens to generate
    /// - Returns: The AI response or error
    func sendChatCompletion(messages: [ChatMessage], temperature: Double, maxTokens: Int?) async -> Result<String, AIProviderError>
    
    /// Get available models for this provider
    /// - Returns: Array of model identifiers
    func getAvailableModels() -> [String]
}

// MARK: - Chat Message
struct ChatMessage: Codable {
    let role: String // "system", "user", or "assistant"
    let content: String
    
    init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - AI Provider Error
enum AIProviderError: Error, LocalizedError {
    case notConfigured
    case invalidAPIKey
    case networkError(String)
    case invalidResponse
    case rateLimitExceeded
    case serverError(String)
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Provider is not configured. Please add an API key."
        case .invalidAPIKey:
            return "Invalid API key. Please check your credentials."
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid response from AI provider."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .serverError(let message):
            return "Server error: \(message)"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}

// MARK: - Connection Status
enum AIConnectionStatus {
    case disconnected
    case testing
    case connected(modelInfo: String)
    case error(message: String)
    
    var displayText: String {
        switch self {
        case .disconnected:
            return "Not Connected"
        case .testing:
            return "Testing Connection..."
        case .connected(let modelInfo):
            return "Connected (\(modelInfo))"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}



