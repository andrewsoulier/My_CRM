import SwiftUI

struct WelcomeView: View {
    @Binding var isPresented: Bool
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 10) {
                Image(systemName: "person.crop.square.filled.and.at.rectangle")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Welcome to My CRM!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your personal relationship manager")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 30)
            
            Divider()
                .padding(.horizontal)
            
            // Setup steps
            VStack(alignment: .leading, spacing: 20) {
                SetupStep(
                    number: 1,
                    title: "Automatic Setup",
                    description: "Database and settings created automatically at:",
                    detail: "~/Documents/MY_CRM/my_crm.db"
                )
                
                SetupStep(
                    number: 2,
                    title: "Import Contacts",
                    description: "Contacts are imported from macOS Contacts app automatically"
                )
                
                SetupStep(
                    number: 3,
                    title: "iMessage Integration (Optional)",
                    description: "Grant Full Disk Access to view iMessage history:",
                    detail: "System Settings → Privacy & Security → Full Disk Access"
                )
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 12) {
                Button(action: {
                    hasSeenWelcome = true
                    isPresented = false
                }) {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Button(action: {
                    openSystemPreferences()
                }) {
                    Text("Open Privacy Settings")
                        .font(.subheadline)
                }
                
                Button(action: {
                    hasSeenWelcome = true
                    isPresented = false
                }) {
                    Text("Skip for Now")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
        .frame(width: 600, height: 550)
    }
    
    private func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
        hasSeenWelcome = true
        isPresented = false
    }
}

struct SetupStep: View {
    let number: Int
    let title: String
    let description: String
    var detail: String? = nil
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            // Number circle
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 35, height: 35)
                Text("\(number)")
                    .font(.headline)
                    .foregroundColor(.blue)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let detail = detail {
                    Text(detail)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
        }
    }
}

