import SwiftUI
import AppKit

/// Guided setup view for connecting to an AI provider
struct AIProviderSetupView: View {
    let provider: AIProviderType
    @Binding var isPresented: Bool
    
    @StateObject private var aiService = AIServiceManager.shared
    @State private var apiKey: String = ""
    @State private var isValidating: Bool = false
    @State private var showSuccess: Bool = false
    @State private var errorMessage: String?
    @State private var monitoringClipboard: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Connect to \(provider.displayName)")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(provider.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)
            
            Divider()
            
            if showSuccess {
                // Success state
                successView
            } else {
                // Setup steps
                setupStepsView
            }
        }
        .frame(width: 500)
        .padding()
    }
    
    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text("Successfully Connected!")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Your \(provider.displayName) API key has been securely stored.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Done") {
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding(.vertical, 40)
    }
    
    private var setupStepsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Step 1: Get API Key
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "1.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Get Your API Key")
                        .font(.headline)
                }
                
                Text("Click the button below to open the \(provider.displayName) API key page in your browser.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Button(action: openAPIKeyPage) {
                    HStack {
                        Image(systemName: "key.fill")
                        Text("Get API Key from \(provider.displayName)")
                    }
                }
                .buttonStyle(.bordered)
            }
            
            Divider()
            
            // Step 2: Enter API Key
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "2.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Enter Your API Key")
                        .font(.headline)
                }
                
                Text("Copy your API key from the browser and paste it here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                SecureField("Paste your API key here", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: apiKey) { newValue in
                        // Clear any previous errors when user types
                        errorMessage = nil
                        
                        // Auto-detect if a valid-looking key was pasted
                        if isValidKeyFormat(newValue) && !isValidating {
                            Task {
                                await validateAndSave()
                            }
                        }
                    }
                
                if let errorMessage = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Divider()
            
            // Step 3: Test Connection
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "3.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Test Connection")
                        .font(.headline)
                }
                
                HStack {
                    Button(action: {
                        Task {
                            await validateAndSave()
                        }
                    }) {
                        if isValidating {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                                Text("Testing Connection...")
                            }
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                Text("Test & Save Connection")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.isEmpty || isValidating)
                    
                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            // Help text
            VStack(alignment: .leading, spacing: 8) {
                Text("Need Help?")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Text("• API keys are stored securely in your macOS Keychain")
                Text("• Keys are never logged or transmitted except to \(provider.displayName)")
                Text("• You can change or remove your key at any time")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func openAPIKeyPage() {
        if let url = URL(string: provider.apiKeyURL) {
            NSWorkspace.shared.open(url)
            monitoringClipboard = true
        }
    }
    
    private func validateAndSave() async {
        guard !apiKey.isEmpty else { return }
        
        isValidating = true
        errorMessage = nil
        
        // Save the API key
        let saved = aiService.saveAPIKey(apiKey, for: provider)
        
        if !saved {
            await MainActor.run {
                errorMessage = "Failed to save API key securely"
                isValidating = false
            }
            return
        }
        
        // Test the connection
        await aiService.testConnection(for: provider)
        
        await MainActor.run {
            let status = aiService.getConnectionStatus(for: provider)
            
            switch status {
            case .connected:
                // Success!
                showSuccess = true
                aiService.selectProvider(provider)
            case .error(let message):
                errorMessage = message
                // Remove the key if validation failed
                _ = aiService.removeAPIKey(for: provider)
            default:
                errorMessage = "Connection test failed"
                _ = aiService.removeAPIKey(for: provider)
            }
            
            isValidating = false
        }
    }
    
    private func isValidKeyFormat(_ key: String) -> Bool {
        // Basic validation - check if it looks like an API key
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch provider {
        case .openai:
            // OpenAI keys start with "sk-"
            return trimmed.hasPrefix("sk-") && trimmed.count > 20
        case .gemini:
            // Google API keys are typically 39 characters
            return trimmed.count > 30 && !trimmed.contains(" ")
        case .claude:
            // Anthropic keys start with "sk-ant-"
            return trimmed.hasPrefix("sk-ant-") && trimmed.count > 20
        }
    }
}



