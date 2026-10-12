# AI Integration Guide for My CRM

## Overview

This guide explains how to set up and use the AI integration features in My CRM. The system supports multiple AI providers including OpenAI (ChatGPT), Google Gemini, and Anthropic Claude for intelligent features throughout the application.

## New Multi-Provider System (Current Implementation)

### Architecture

The AI integration system consists of several key components:

1. **KeychainManager**: Securely stores API keys in macOS Keychain
2. **AIProvider Protocol**: Defines a common interface for all AI providers
3. **Provider Implementations**: OpenAI, Gemini, and Claude providers
4. **AIServiceManager**: Manages providers and routes requests
5. **Settings UI**: User-friendly interface for configuration

### Supported Providers

#### OpenAI (ChatGPT)
- **Models**: GPT-4o, GPT-4o-mini, GPT-4, GPT-3.5-turbo
- **API Key**: Get from [OpenAI Platform](https://platform.openai.com/api-keys)
- **Authentication**: Bearer token in Authorization header
- **Best For**: General-purpose chat, complex reasoning, code generation

#### Google Gemini
- **Models**: Gemini Pro, Gemini 1.5 Pro, Gemini 1.5 Flash
- **API Key**: Get from [Google AI Studio](https://aistudio.google.com/app/apikey)
- **Authentication**: API key in query parameter or header
- **Best For**: Multimodal tasks, fast responses, Google ecosystem

#### Anthropic Claude
- **Models**: Claude 3.5 Sonnet, Claude 3 Opus, Claude 3 Sonnet, Claude 3 Haiku
- **API Key**: Get from [Anthropic Console](https://console.anthropic.com/settings/keys)
- **Authentication**: x-api-key header
- **Best For**: Long-form content, safety-focused applications, detailed analysis

### Setup Instructions (New System)

#### Method 1: Guided Setup (Recommended)

1. **Open Settings**:
   - Launch My CRM
   - Go to Settings → AI Integration section

2. **Choose a Provider**:
   - You'll see cards for OpenAI, Gemini, and Claude
   - Each card shows a description and connection status

3. **Click "Connect"**:
   - A guided setup modal will appear
   - Follow the step-by-step instructions

4. **Get API Key**:
   - Click "Get API Key from [Provider]"
   - Your browser will open to the provider's API key page
   - Create and copy your API key

5. **Enter and Test**:
   - Paste your API key in the secure field
   - The system will automatically validate it
   - You'll see a success message when connected

#### Method 2: Manual Entry

1. **Open Settings** → AI Integration
2. **Click "Manual"** for your chosen provider
3. **Enter API Key** in the secure field
4. **Click "Save"** to test and save the connection
5. **Verify** the connection status shows "Connected"

### Security Features

#### Keychain Storage
- API keys are stored in macOS Keychain, never in JSON files
- Keys are encrypted at rest by macOS
- Each provider has a separate keychain entry
- Service identifier: `com.mycrm.apikeys`

#### Privacy Protections
- API keys are never logged
- Secure text fields hide key entry
- Keys can be removed at any time
- No credentials are transmitted except to the respective provider

### Using the AI Service in Code

#### Basic Query

```swift
// Get the AI service
let aiService = AIServiceManager.shared

// Send a simple query
let result = await aiService.sendQuery("What is the capital of France?")

switch result {
case .success(let response):
    print("AI Response: \(response)")
case .failure(let error):
    print("Error: \(error.localizedDescription)")
}
```

#### Chat Completion with Context

```swift
let messages = [
    ChatMessage(role: "system", content: "You are a helpful CRM assistant."),
    ChatMessage(role: "user", content: "Summarize this message: \(messageText)")
]

let result = await aiService.sendChatCompletion(
    messages: messages,
    temperature: 0.7,
    maxTokens: 500
)

switch result {
case .success(let response):
    // Handle the AI response
    print(response)
case .failure(let error):
    // Handle the error
    handleAIError(error)
}
```

#### Selecting a Provider

```swift
// Select OpenAI as the active provider
aiService.selectProvider(.openai)

// Or select Gemini
aiService.selectProvider(.gemini)

// Or select Claude
aiService.selectProvider(.claude)

// Get the current provider
if let currentProvider = aiService.selectedProvider {
    print("Using: \(currentProvider.displayName)")
}
```

#### Testing Connection

```swift
// Test a specific provider
await aiService.testConnection(for: .openai)

// Check the status
let status = aiService.getConnectionStatus(for: .openai)

switch status {
case .connected(let modelInfo):
    print("Connected to \(modelInfo)")
case .error(let message):
    print("Connection failed: \(message)")
case .testing:
    print("Testing connection...")
case .disconnected:
    print("Not connected")
}
```

### Managing API Keys Programmatically

```swift
// Save an API key
let success = aiService.saveAPIKey("sk-...", for: .openai)

// Check if a provider has a key
let hasKey = aiService.hasAPIKey(for: .gemini)

// Remove an API key
let removed = aiService.removeAPIKey(for: .claude)

// Get all configured providers
let configured = aiService.getConfiguredProviders()
```

### Error Handling

The system provides detailed error types:

```swift
enum AIProviderError: Error {
    case notConfigured          // No API key set
    case invalidAPIKey          // API key is invalid
    case networkError(String)   // Network issue
    case invalidResponse        // Unexpected response format
    case rateLimitExceeded      // Too many requests
    case serverError(String)    // Provider server error
    case unknown(String)        // Unknown error
}
```

Example error handling:

```swift
let result = await aiService.sendQuery("Hello")

switch result {
case .success(let response):
    displayResponse(response)
    
case .failure(let error):
    switch error {
    case .notConfigured:
        showSettingsPrompt()
    case .invalidAPIKey:
        showAPIKeyError()
    case .rateLimitExceeded:
        showRateLimitWarning()
    case .networkError(let message):
        showNetworkError(message)
    default:
        showGenericError(error)
    }
}
```

### Troubleshooting

#### Connection Issues

**Problem**: "Invalid API Key" error

**Solutions**:
1. Verify the API key is correct and complete
2. Check that the key is active in the provider's dashboard
3. Ensure you have sufficient credits/quota
4. Try removing and re-adding the key

**Problem**: "Network Error"

**Solutions**:
1. Check your internet connection
2. Verify the provider's service status
3. Check macOS firewall settings
4. Try testing from a different network

**Problem**: "Rate Limit Exceeded"

**Solutions**:
1. Wait before making more requests
2. Check your provider's rate limits
3. Consider upgrading your API plan
4. Implement request throttling in your code

#### Provider-Specific Issues

**OpenAI**:
- Ensure key starts with `sk-`
- Check billing and credits
- Verify organization ID if using one

**Google Gemini**:
- API key should be 39 characters
- Enable the Generative Language API in Google Cloud Console
- Check quota limits

**Anthropic Claude**:
- Key should start with `sk-ant-`
- Verify account is in good standing
- Check usage limits

### Best Practices

1. **API Key Management**:
   - Never hardcode API keys
   - Rotate keys periodically
   - Use separate keys for development and production

2. **Request Optimization**:
   - Cache responses when appropriate
   - Use lower temperature for consistent results
   - Set appropriate max token limits

3. **Error Handling**:
   - Always handle errors gracefully
   - Provide user-friendly error messages
   - Log errors for debugging (but not API keys)

4. **Provider Selection**:
   - Choose providers based on use case
   - Test with multiple providers
   - Have a fallback provider option

---

## Legacy Python-Based Implementation

> **Note**: The following sections describe the older Python-based ChatGPT integration system. This is maintained for backward compatibility but the new multi-provider system above is recommended for new features.

## Setup Instructions

### 1. Prerequisites

Before setting up AI integration, ensure you have:

- **OpenAI API Key**: Get one from [OpenAI Platform](https://platform.openai.com/api-keys)
- **Python 3.7+**: Required for the ChatGPT connection script
- **macOS Keychain Access**: For secure credential storage

### 2. Install Python Dependencies

Navigate to the script directory and install required packages:

```bash
cd "App/Feature Groups/iMessage Server Scraper/Resources"
pip install -r requirements.txt
```

Required packages:
- `requests>=2.31.0` - For API communication
- `keyring>=24.2.0` - For secure credential storage

### 3. Connect to ChatGPT

1. **Open My CRM Settings**:
   - Launch My CRM
   - Go to Settings (or use the settings shortcut)
   - Navigate to the "AI Integration" section

2. **Click "Log in to ChatGPT"**:
   - This will launch the connection script
   - Follow the interactive prompts

3. **Enter Your Credentials**:
   - **API Key**: Your OpenAI API key (required)
   - **Organization ID**: Your OpenAI organization ID (optional)

4. **Verify Connection**:
   - The script will test your credentials
   - You'll see a success message if everything works
   - The settings page will show "Connected to ChatGPT"

## Features

### Automatic Message Analysis

Once connected, the AI can automatically analyze incoming messages to:

- **Detect Invitations**: Identify potential meeting requests, task assignments, or action items
- **Extract Information**: Pull out titles, descriptions, due dates, and priorities
- **Suggest Categories**: Automatically categorize invites (meeting, task, event, etc.)
- **Assign Priorities**: Suggest priority levels based on urgency indicators

### Smart Task Management

The AI provides intelligent assistance for:

- **Task Suggestions**: Generate actionable next steps for existing tasks
- **Priority Recommendations**: Suggest appropriate priority levels
- **Categorization**: Automatically categorize tasks and invites
- **Context Analysis**: Understand the context and importance of tasks

### Integration with Invites System

The AI integration works seamlessly with the invites system:

- **Auto-creation**: Automatically create invites from analyzed messages
- **Smart Fields**: Populate invite fields with AI-extracted information
- **Suggestions**: Provide AI-generated suggestions for task completion
- **Learning**: Improve suggestions based on user behavior

## Usage Examples

### Analyzing a Message

```swift
// In your message processing code
let message = "Hey, can we meet tomorrow at 2pm to discuss the project?"
let contactName = "John Smith"

if let analysis = await chatGPTService.analyzeMessageForInvite(message, contactName: contactName) {
    if analysis.isInvite {
        let invite = Invite(
            title: analysis.title,
            description: analysis.description,
            sentReceived: .received,
            fromPhone: contactPhone,
            priority: analysis.suggestedPriority,
            category: analysis.suggestedCategory
        )
        try await dataProvider.createInvite(invite)
    }
}
```

### Getting Task Suggestions

```swift
// For an existing invite
let suggestions = await chatGPTService.generateTaskSuggestions(for: invite)
print("AI Suggestions:")
for suggestion in suggestions {
    print("- \(suggestion)")
}
```

### Categorizing an Invite

```swift
// Auto-categorize an invite
if let category = await chatGPTService.categorizeInvite(invite) {
    invite.category = category
    try await dataProvider.updateInvite(invite)
}
```

## Security and Privacy

### Credential Storage

- **macOS Keychain**: All API keys are stored securely in the macOS keychain
- **No Local Files**: Credentials are never stored in plain text files
- **Encrypted Storage**: Keychain provides encrypted, secure storage

### Data Privacy

- **Message Analysis**: Only message content is sent to OpenAI for analysis
- **No Personal Data**: Contact information and personal details are not transmitted
- **Local Processing**: All invite creation and management happens locally

### API Usage

- **Minimal Requests**: Only necessary data is sent to the API
- **Efficient Queries**: Requests are optimized to minimize API usage
- **Error Handling**: Failed requests don't expose sensitive information

## Troubleshooting

### Connection Issues

**Problem**: "Connection failed" error
**Solutions**:
1. Verify your API key is correct
2. Check your internet connection
3. Ensure you have sufficient OpenAI credits
4. Try running the script manually: `python connectToChatGPT.py status`

**Problem**: "Script execution failed"
**Solutions**:
1. Ensure Python 3.7+ is installed
2. Install required packages: `pip install -r requirements.txt`
3. Check script permissions
4. Verify the script path is correct

### API Issues

**Problem**: "API request failed"
**Solutions**:
1. Check your OpenAI account status
2. Verify API key permissions
3. Check rate limits and usage quotas
4. Ensure your organization ID is correct (if using one)

### Performance Issues

**Problem**: Slow AI responses
**Solutions**:
1. Check your internet connection
2. Monitor OpenAI API status
3. Consider upgrading your OpenAI plan for higher rate limits
4. Optimize prompt length and complexity

## Advanced Configuration

### Custom Prompts

You can customize the AI prompts by modifying the `ChatGPTService.swift` file:

```swift
private func createInviteAnalysisPrompt(message: String, contactName: String?) -> String {
    // Customize this prompt for your specific needs
    return """
    Your custom prompt here...
    """
}
```

### Organization Settings

If you're using OpenAI with an organization:

1. Get your Organization ID from the OpenAI dashboard
2. Enter it during the connection setup
3. The script will store it securely in the keychain

### Rate Limiting

To manage API usage:

1. Monitor your OpenAI dashboard for usage statistics
2. Implement caching for repeated analyses
3. Consider batching multiple requests
4. Set up usage alerts in your OpenAI account

## Future Enhancements

### Planned Features

1. **Batch Processing**: Analyze multiple messages at once
2. **Custom Models**: Support for fine-tuned models
3. **Learning System**: Improve suggestions based on user feedback
4. **Integration APIs**: REST endpoints for external integrations
5. **Advanced Analytics**: Usage statistics and performance metrics

### API Improvements

1. **Streaming Responses**: Real-time AI responses
2. **Function Calling**: Direct API function execution
3. **Multi-modal Analysis**: Support for images and attachments
4. **Context Awareness**: Better understanding of conversation history

## Support

### Getting Help

1. **Check Logs**: Review the application logs for detailed error information
2. **Test Script**: Run the connection script manually to isolate issues
3. **Verify Setup**: Ensure all prerequisites are met
4. **API Status**: Check OpenAI's status page for service issues

### Common Commands

```bash
# Test connection
python connectToChatGPT.py status

# Reconnect
python connectToChatGPT.py connect

# Disconnect
python connectToChatGPT.py disconnect

# Test API
python connectToChatGPT.py test
```

## Conclusion

The AI integration provides powerful capabilities for intelligent task management and invite analysis. With proper setup and configuration, it can significantly enhance your productivity by automatically processing and categorizing incoming messages and providing smart suggestions for task management.

The system is designed to be secure, efficient, and user-friendly, with comprehensive error handling and troubleshooting capabilities. As the AI technology continues to evolve, the integration will be updated to take advantage of new features and capabilities.
