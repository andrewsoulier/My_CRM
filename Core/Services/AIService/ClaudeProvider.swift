import Foundation

/// Anthropic Claude API provider implementation
class ClaudeProvider: AIProvider {
    let providerType: AIProviderType = .claude
    private let keychain = KeychainManager.shared
    
    private let baseURL = "https://api.anthropic.com/v1"
    private let defaultModel = "claude-3-5-sonnet-20241022"
    private let apiVersion = "2023-06-01"
    
    var isConfigured: Bool {
        return keychain.hasAPIKey(for: providerType.rawValue)
    }
    
    func testConnection() async -> Result<String, AIProviderError> {
        guard let apiKey = keychain.retrieveAPIKey(for: providerType.rawValue) else {
            return .failure(.notConfigured)
        }
        
        // Test with a simple message request
        let testMessages = [ChatMessage(role: "user", content: "Hello")]
        let result = await sendChatCompletion(messages: testMessages, temperature: 0.1, maxTokens: 10)
        
        switch result {
        case .success:
            return .success("Connected successfully to Anthropic Claude")
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func sendChatCompletion(messages: [ChatMessage], temperature: Double = 0.7, maxTokens: Int? = 1024) async -> Result<String, AIProviderError> {
        guard let apiKey = keychain.retrieveAPIKey(for: providerType.rawValue) else {
            return .failure(.notConfigured)
        }
        
        guard let url = URL(string: "\(baseURL)/messages") else {
            return .failure(.invalidResponse)
        }
        
        // Separate system messages from user/assistant messages
        let systemMessage = messages.first(where: { $0.role == "system" })?.content
        let conversationMessages = messages.filter { $0.role != "system" }
        
        var requestBody: [String: Any] = [
            "model": defaultModel,
            "messages": conversationMessages.map { ["role": $0.role, "content": $0.content] },
            "max_tokens": maxTokens ?? 1024,
            "temperature": temperature
        ]
        
        if let systemMessage = systemMessage {
            requestBody["system"] = systemMessage
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                return parseClaudeResponse(data: data)
            case 401:
                return .failure(.invalidAPIKey)
            case 429:
                return .failure(.rateLimitExceeded)
            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                return .failure(.serverError(errorMessage))
            }
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }
    
    func getAvailableModels() -> [String] {
        return ["claude-3-5-sonnet-20241022", "claude-3-opus-20240229", "claude-3-sonnet-20240229", "claude-3-haiku-20240307"]
    }
    
    // MARK: - Private Helpers
    
    private func parseClaudeResponse(data: Data) -> Result<String, AIProviderError> {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? [[String: Any]],
               let firstContent = content.first,
               let text = firstContent["text"] as? String {
                return .success(text)
            }
            return .failure(.invalidResponse)
        } catch {
            return .failure(.invalidResponse)
        }
    }
}



