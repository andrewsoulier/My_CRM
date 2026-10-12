import Foundation

/// Google Gemini API provider implementation
class GeminiProvider: AIProvider {
    let providerType: AIProviderType = .gemini
    private let keychain = KeychainManager.shared
    
    private let baseURL = "https://generativelanguage.googleapis.com/v1"
    private let defaultModel = "gemini-pro"
    
    var isConfigured: Bool {
        return keychain.hasAPIKey(for: providerType.rawValue)
    }
    
    func testConnection() async -> Result<String, AIProviderError> {
        guard let apiKey = keychain.retrieveAPIKey(for: providerType.rawValue) else {
            return .failure(.notConfigured)
        }
        
        // Test with a simple generate request
        let testMessages = [ChatMessage(role: "user", content: "Hello")]
        let result = await sendChatCompletion(messages: testMessages, temperature: 0.1, maxTokens: 10)
        
        switch result {
        case .success:
            return .success("Connected successfully to Google Gemini")
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func sendChatCompletion(messages: [ChatMessage], temperature: Double = 0.7, maxTokens: Int? = nil) async -> Result<String, AIProviderError> {
        guard let apiKey = keychain.retrieveAPIKey(for: providerType.rawValue) else {
            return .failure(.notConfigured)
        }
        
        guard let url = URL(string: "\(baseURL)/models/\(defaultModel):generateContent?key=\(apiKey)") else {
            return .failure(.invalidResponse)
        }
        
        // Convert messages to Gemini format
        let contents = messages.map { message in
            return [
                "role": message.role == "assistant" ? "model" : "user",
                "parts": [["text": message.content]]
            ]
        }
        
        var requestBody: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": temperature
            ]
        ]
        
        if let maxTokens = maxTokens {
            if var config = requestBody["generationConfig"] as? [String: Any] {
                config["maxOutputTokens"] = maxTokens
                requestBody["generationConfig"] = config
            }
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                return parseGeminiResponse(data: data)
            case 401, 403:
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
        return ["gemini-pro", "gemini-1.5-pro", "gemini-1.5-flash"]
    }
    
    // MARK: - Private Helpers
    
    private func parseGeminiResponse(data: Data) -> Result<String, AIProviderError> {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let content = firstCandidate["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let firstPart = parts.first,
               let text = firstPart["text"] as? String {
                return .success(text)
            }
            return .failure(.invalidResponse)
        } catch {
            return .failure(.invalidResponse)
        }
    }
}



