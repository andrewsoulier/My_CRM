import SwiftUI
import AppKit

struct MessagesAuthorizationView: View {
    @StateObject private var authManager = MessagesAuthorizationManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var isChecking = false
    @State private var showFullDetails = false
    
    var onAuthorized: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.system(size: 60))
                    .foregroundColor(statusColor)
                
                Text(statusTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(authManager.getAuthorizationGuidanceMessage())
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 20)
            
            Divider()
            
            // Quick Fix Instructions
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Fix")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                ForEach(Array(authManager.getQuickFixInstructions().enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 28, height: 28)
                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                        
                        Text(instruction)
                            .font(.body)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer()
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 12) {
                // Primary action button
                primaryActionButton
                
                // Secondary actions
                HStack(spacing: 12) {
                    Button("Check Again") {
                        checkAuthorization()
                    }
                    .disabled(isChecking)
                    
                    if authManager.authorizationStatus == .denied || authManager.authorizationStatus == .notDetermined {
                        Button("Open System Settings") {
                            authManager.openSystemSettingsToAutomation()
                        }
                        .disabled(isChecking)
                    }
                    
                    if authManager.authorizationStatus == .messagesNotRunning {
                        Button("Launch Messages") {
                            Task {
                                try? await authManager.launchMessagesApp()
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                checkAuthorization()
                            }
                        }
                        .disabled(isChecking)
                    }
                    
                    Button("Show Details") {
                        showFullDetails.toggle()
                    }
                }
                
                // Close button (only if authorized or user wants to dismiss)
                if authManager.authorizationStatus == .authorized {
                    Button("Continue") {
                        onAuthorized?()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding()
        }
        .frame(width: 550, height: showFullDetails ? 700 : 500)
        .onAppear {
            checkAuthorization()
        }
        .sheet(isPresented: $showFullDetails) {
            detailsView
        }
    }
    
    // MARK: - Status Computed Properties
    
    private var statusIcon: String {
        switch authManager.authorizationStatus {
        case .authorized:
            return "checkmark.circle.fill"
        case .denied, .notDetermined:
            return "exclamationmark.shield.fill"
        case .messagesNotRunning:
            return "app.badge"
        case .messagesNotInstalled:
            return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch authManager.authorizationStatus {
        case .authorized:
            return .green
        case .denied, .notDetermined:
            return .orange
        case .messagesNotRunning:
            return .blue
        case .messagesNotInstalled:
            return .red
        }
    }
    
    private var statusTitle: String {
        switch authManager.authorizationStatus {
        case .authorized:
            return "All Set!"
        case .denied, .notDetermined:
            return "Authorization Required"
        case .messagesNotRunning:
            return "Messages Not Running"
        case .messagesNotInstalled:
            return "Messages Not Found"
        }
    }
    
    // MARK: - Primary Action Button
    
    @ViewBuilder
    private var primaryActionButton: some View {
        switch authManager.authorizationStatus {
        case .authorized:
            Button(action: {
                onAuthorized?()
                dismiss()
            }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Ready to Send")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
        case .denied, .notDetermined:
            Button(action: {
                Task { @MainActor in
                    _ = await authManager.requestAutomationPermission()
                }
            }) {
                HStack {
                    Image(systemName: "person.badge.key")
                    Text("Request Permission")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            
        case .messagesNotRunning:
            Button(action: {
                Task {
                    try? await authManager.launchMessagesApp()
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    checkAuthorization()
                }
            }) {
                HStack {
                    Image(systemName: "app.badge.fill")
                    Text("Launch Messages")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isChecking)
            
        case .messagesNotInstalled:
            Button(action: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane")!)
            }) {
                HStack {
                    Image(systemName: "questionmark.circle")
                    Text("Get Help")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Details View
    
    private var detailsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Authorization Details")
                .font(.title2)
                .fontWeight(.bold)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status Section
                    detailSection(
                        title: "Current Status",
                        icon: "info.circle",
                        items: [
                            ("Authorization", authManager.authorizationStatus.description),
                            ("Last Checked", authManager.lastCheckTime?.formatted() ?? "Never"),
                            ("Messages App", authManager.isMessagesAppInstalled() ? "Installed" : "Not Found")
                        ]
                    )
                    
                    // Requirements Section
                    detailSection(
                        title: "Requirements",
                        icon: "checklist",
                        items: [
                            ("Messages App Installed", checkmark(authManager.isMessagesAppInstalled())),
                            ("Messages App Running", checkmark(MessagesPreflight.isMessagesAppRunning())),
                            ("Automation Permission", checkmark(authManager.authorizationStatus == .authorized)),
                            ("Full Disk Access", checkmark(authManager.hasFullDiskAccess()) + " (Optional)")
                        ]
                    )
                    
                    // Troubleshooting
                    detailSection(
                        title: "Troubleshooting",
                        icon: "wrench.and.screwdriver",
                        items: [
                            ("1. Ensure Messages is running", ""),
                            ("2. Grant automation permission in System Settings", ""),
                            ("3. Restart My CRM after granting permissions", ""),
                            ("4. If issues persist, check macOS version compatibility", "")
                        ]
                    )
                }
                .padding()
            }
            
            Spacer()
            
            Button("Close") {
                showFullDetails = false
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .padding()
    }
    
    private func detailSection(title: String, icon: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.0) { item in
                    HStack {
                        Text(item.0)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(item.1)
                            .fontWeight(.medium)
                    }
                    .font(.body)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
    }
    
    private func checkmark(_ condition: Bool) -> String {
        condition ? "✅" : "❌"
    }
    
    // MARK: - Actions
    
    private func checkAuthorization() {
        isChecking = true
        Task {
            await authManager.checkAuthorizationStatus()
            isChecking = false
            
            if authManager.authorizationStatus == .authorized {
                // Automatically close and notify if now authorized
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    onAuthorized?()
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    MessagesAuthorizationView()
}

