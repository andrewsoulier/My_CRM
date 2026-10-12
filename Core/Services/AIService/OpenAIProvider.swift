import Foundation

/// OpenAI API provider implementation
class OpenAIProvider: AIProvider {
    let providerType: AIProviderType = .openai
    private let keychain = KeychainManager.shared
    
    private let baseURL = "https://api.openai.com/v1"
    private let defaultModel = "gpt-4o"
    
    var isConfigured: Bool {
        return keychain.hasAPIKey(for: providerType.rawValue)
    }
    
    func testConnection() async -> Result<String, AIProviderError> {
        guard let apiKey = keychain.retrieveAPIKey(for: providerType.rawValue) else {
            return .failure(.notConfigured)
        }
        
        // Test with a simple models list request
        guard let url = URL(string: "\(baseURL)/models") else {
            return .failure(.invalidResponse)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                return .success("Connected successfully to OpenAI")
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
    
    func sendChatCompletion(messages: [ChatMessage], temperature: Double = 0.7, maxTokens: Int? = nil) async -> Result<String, AIProviderError> {
        guard let apiKey = keychain.retrieveAPIKey(for: providerType.rawValue) else {
            return .failure(.notConfigured)
        }
        
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            return .failure(.invalidResponse)
        }
        
        var requestBody: [String: Any] = [
            "model": defaultModel,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "temperature": temperature
        ]
        
        if let maxTokens = maxTokens {
            requestBody["max_tokens"] = maxTokens
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.invalidResponse)
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                return parseOpenAIResponse(data: data)
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
        return ["gpt-4o", "gpt-4o-mini", "gpt-4", "gpt-3.5-turbo"]
    }
    
    // MARK: - Private Helpers
    
    private func parseOpenAIResponse(data: Data) -> Result<String, AIProviderError> {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return .success(content)
            }
            return .failure(.invalidResponse)
        } catch {
            return .failure(.invalidResponse)
        }
    }
}



