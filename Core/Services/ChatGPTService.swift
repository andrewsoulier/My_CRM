import Foundation
import SwiftUI

// MARK: - ChatGPT Service

@MainActor
class ChatGPTService: ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus = "Not connected"
    @Published var lastError: String?
    
    private let logger = LogManager.shared
    private let openAIProvider = OpenAIProvider()
    private let keychain = KeychainManager.shared
    
    init() {
        print("🔧 ChatGPTService: init() called")
        logger.info("🔧 ChatGPTService: init() called")
        
        // Check initial connection status
        Task {
            await checkConnectionStatus()
        }
    }
    
    // MARK: - Connection Management
    
    /// Set the OpenAI API key
    func setAPIKey(_ apiKey: String) async {
        logger.info("🔑 Setting OpenAI API key...")
        
        // Save to keychain
        let saved = keychain.saveAPIKey(apiKey, for: "openai")
        if saved {
            logger.info("✅ API key saved to keychain")
            // Test the connection
            await checkConnectionStatus()
        } else {
            isConnected = false
            connectionStatus = "Failed to save API key"
            lastError = "Could not save API key to secure storage"
            logger.error("❌ Failed to save API key to keychain")
        }
    }
    
    func connectToChatGPT() async {
        logger.info("🤖 Checking ChatGPT connection...")
        print("🔧 ChatGPTService: connectToChatGPT() called")
        
        await checkConnectionStatus()
        
        if !isConnected {
            lastError = "Please configure your OpenAI API key in Settings."
            logger.warning("⚠️ No API key configured")
        }
    }
    
    func disconnectFromChatGPT() async {
        logger.info("🔌 Disconnecting from ChatGPT...")
        
        let deleted = keychain.deleteAPIKey(for: "openai")
        if deleted {
            isConnected = false
            connectionStatus = "Disconnected"
            lastError = nil
            logger.info("✅ ChatGPT disconnected successfully")
        } else {
            lastError = "Failed to remove API key"
            logger.error("❌ ChatGPT disconnect failed")
        }
    }
    
    func checkConnectionStatus() async {
        logger.info("🔧 ChatGPTService: checkConnectionStatus() called")
        print("🔧 ChatGPTService: checkConnectionStatus() called")
        
        // Check if we have an API key
        if !openAIProvider.isConfigured {
            isConnected = false
            connectionStatus = "Not configured"
            lastError = "No API key found. Please configure your OpenAI API key in Settings."
            logger.info("ℹ️ ChatGPT not configured: No API key found")
            print("ℹ️ ChatGPTService: Not configured")
            return
        }
        
        // Test the connection
        let result = await openAIProvider.testConnection()
        
        switch result {
        case .success(let message):
            isConnected = true
            connectionStatus = "Connected to OpenAI"
            lastError = nil
            logger.info("✅ ChatGPT connection verified: \(message)")
            print("✅ ChatGPTService: Connection verified")
        case .failure(let error):
            isConnected = false
            switch error {
            case .notConfigured:
                connectionStatus = "Not configured"
                lastError = "No API key found"
            case .invalidAPIKey:
                connectionStatus = "Invalid API key"
                lastError = "The provided API key is invalid"
            case .rateLimitExceeded:
                connectionStatus = "Rate limit exceeded"
                lastError = "OpenAI rate limit exceeded. Please try again later."
            case .networkError(let message):
                connectionStatus = "Network error"
                lastError = "Network error: \(message)"
            case .serverError(let message):
                connectionStatus = "Server error"
                lastError = "Server error: \(message)"
            case .invalidResponse:
                connectionStatus = "Invalid response"
                lastError = "Received invalid response from OpenAI"
            case .unknown(let message):
                connectionStatus = "Unknown error"
                lastError = message
            }
            logger.error("❌ ChatGPT connection error: \(lastError ?? "Unknown error")")
            print("❌ ChatGPTService: Connection error: \(lastError ?? "Unknown error")")
        }
    }
    
    func openSettings() {
        logger.info("🔧 ChatGPTService: Opening app settings...")
        print("🔧 ChatGPTService: Opening app settings...")
        
        // Open the app settings window
        // This would typically trigger showing the settings view in your app
        NotificationCenter.default.post(name: NSNotification.Name("ShowSettings"), object: nil)
    }
    
    // MARK: - AI Analysis for Invites
    
    func analyzeMessageForInvite(_ message: String, contactName: String? = nil) async -> InviteAnalysis? {
        guard isConnected else {
            logger.warning("⚠️ Cannot analyze message: ChatGPT not connected")
            return nil
        }
        
        logger.info("🔍 Analyzing message for potential invite...")
        
        let prompt = createInviteAnalysisPrompt(message: message, contactName: contactName)
        
        do {
            let response = try await makeChatGPTRequest(prompt: prompt)
            return parseInviteAnalysis(response)
        } catch {
            logger.error("❌ Failed to analyze message: \(error.localizedDescription)")
            return nil
        }
    }
    
    func generateTaskSuggestions(for invite: Invite) async -> [String] {
        guard isConnected else {
            logger.warning("⚠️ Cannot generate suggestions: ChatGPT not connected")
            return []
        }
        
        logger.info("💡 Generating task suggestions for invite: \(invite.title)")
        
        let prompt = createTaskSuggestionPrompt(for: invite)
        
        do {
            let response = try await makeChatGPTRequest(prompt: prompt)
            return parseTaskSuggestions(response)
        } catch {
            logger.error("❌ Failed to generate suggestions: \(error.localizedDescription)")
            return []
        }
    }
    
    func categorizeInvite(_ invite: Invite) async -> String? {
        guard isConnected else {
            logger.warning("⚠️ Cannot categorize invite: ChatGPT not connected")
            return nil
        }
        
        logger.info("🏷️ Categorizing invite: \(invite.title)")
        
        let prompt = createCategorizationPrompt(for: invite)
        
        do {
            let response = try await makeChatGPTRequest(prompt: prompt)
            return parseCategorization(response)
        } catch {
            logger.error("❌ Failed to categorize invite: \(error.localizedDescription)")
            return nil
        }
    }
    
    func suggestPriority(for invite: Invite) async -> Priority? {
        guard isConnected else {
            logger.warning("⚠️ Cannot suggest priority: ChatGPT not connected")
            return nil
        }
        
        logger.info("⚡ Suggesting priority for invite: \(invite.title)")
        
        let prompt = createPrioritySuggestionPrompt(for: invite)
        
        do {
            let response = try await makeChatGPTRequest(prompt: prompt)
            return parsePrioritySuggestion(response)
        } catch {
            logger.error("❌ Failed to suggest priority: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func makeChatGPTRequest(prompt: String) async throws -> String {
        logger.info("📡 Making OpenAI API request...")
        
        let message = ChatMessage(role: "user", content: prompt)
        let result = await openAIProvider.sendChatCompletion(
            messages: [message],
            temperature: 0.7,
            maxTokens: 500
        )
        
        switch result {
        case .success(let response):
            logger.info("✅ OpenAI API request successful")
            return response
        case .failure(let error):
            logger.error("❌ OpenAI API request failed: \(error)")
            throw ChatGPTError.apiRequestFailed(error.errorDescription ?? "Unknown error")
        }
    }
    
    // MARK: - Prompt Creation
    
    private func createInviteAnalysisPrompt(message: String, contactName: String?) -> String {
        let contactInfo = contactName != nil ? " from \(contactName!)" : ""
        return """
        Analyze this message\(contactInfo) to determine if it contains an invitation, task, or action item:
        
        Message: "\(message)"
        
        Please provide:
        1. Is this an invitation/task? (yes/no)
        2. If yes, what is the title/subject?
        3. What is the description?
        4. Is there a due date mentioned?
        5. What priority level (1-5) would you suggest?
        6. What category would this fall under?
        7. Any additional context or suggestions?
        
        Format your response as JSON.
        """
    }
    
    private func createTaskSuggestionPrompt(for invite: Invite) -> String {
        return """
        Based on this task/invitation, suggest 3-5 actionable next steps or related tasks:
        
        Title: \(invite.title)
        Description: \(invite.description ?? "No description")
        Category: \(invite.category ?? "Not specified")
        Priority: \(invite.priority.displayName)
        
        Provide practical, actionable suggestions that would help complete this task.
        """
    }
    
    private func createCategorizationPrompt(for invite: Invite) -> String {
        return """
        Categorize this task/invitation into one of these categories:
        - meeting
        - task
        - event
        - reminder
        - follow-up
        - project
        - personal
        - work
        - other
        
        Title: \(invite.title)
        Description: \(invite.description ?? "No description")
        
        Return only the category name.
        """
    }
    
    private func createPrioritySuggestionPrompt(for invite: Invite) -> String {
        return """
        Suggest a priority level (1-5) for this task/invitation:
        1 = Low priority
        2 = Medium priority  
        3 = High priority
        4 = Urgent
        5 = Critical
        
        Title: \(invite.title)
        Description: \(invite.description ?? "No description")
        Due Date: \(invite.dueDate?.formatted() ?? "Not specified")
        
        Consider urgency, importance, and deadlines.
        Return only the number (1-5).
        """
    }
    
    // MARK: - Response Parsing
    
    private func parseInviteAnalysis(_ response: String) -> InviteAnalysis? {
        // Parse the ChatGPT response and extract invite information
        // This is a simplified version - in reality, you'd parse JSON or structured text
        
        return InviteAnalysis(
            isInvite: true, // Simplified for now
            title: "Extracted Title",
            description: "Extracted Description",
            suggestedPriority: .medium,
            suggestedCategory: "meeting",
            confidence: 0.8
        )
    }
    
    private func parseTaskSuggestions(_ response: String) -> [String] {
        // Parse suggestions from ChatGPT response
        return [
            "Follow up with contact",
            "Prepare materials",
            "Set reminder",
            "Schedule follow-up meeting"
        ]
    }
    
    private func parseCategorization(_ response: String) -> String? {
        // Extract category from response
        let categories = ["meeting", "task", "event", "reminder", "follow-up", "project", "personal", "work", "other"]
        return categories.first { response.lowercased().contains($0) }
    }
    
    private func parsePrioritySuggestion(_ response: String) -> Priority? {
        // Extract priority number from response
        let numbers = response.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
            .filter { 1...5 ~= $0 }
        
        if let priorityNumber = numbers.first {
            return Priority(rawValue: priorityNumber)
        }
        
        return nil
    }
}

// MARK: - Supporting Types

// Legacy struct - kept for compatibility but no longer used with Swift implementation
@available(*, deprecated, message: "No longer used - ChatGPT now uses OpenAIProvider directly")
struct ChatGPTScriptResult: Codable {
    let success: Bool
    let connected: Bool
    let message: String
    let hasApiKey: Bool?
    let hasOrganization: Bool?
    let organization: String?
    
    enum CodingKeys: String, CodingKey {
        case success, connected, message
        case hasApiKey = "has_api_key"
        case hasOrganization = "has_organization"
        case organization
    }
}

struct InviteAnalysis {
    let isInvite: Bool
    let title: String
    let description: String
    let suggestedPriority: Priority
    let suggestedCategory: String
    let confidence: Double
}

enum ChatGPTError: Error, LocalizedError {
    case scriptExecutionFailed(String)
    case invalidOutput
    case apiRequestFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .scriptExecutionFailed(let output):
            return "Script execution failed: \(output)"
        case .invalidOutput:
            return "Invalid script output"
        case .apiRequestFailed(let message):
            return "API request failed: \(message)"
        }
    }
}
