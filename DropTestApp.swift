import SwiftUI
import UniformTypeIdentifiers
import AppKit

@main
struct DropTestApp: App {
    var body: some Scene {
        WindowGroup {
            DropTestWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

struct DropTestWindow: View {
    @State private var droppedItems: [String] = []
    @State private var logMessages: [String] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Drop Test Window")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Drag and drop anything here to test")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Drop zone
            Rectangle()
                .fill(Color.blue.opacity(0.1))
                .overlay(
                    Rectangle()
                        .stroke(Color.blue, lineWidth: 2)
                )
                .frame(width: 400, height: 300)
                .cornerRadius(12)
                .overlay(
                    VStack {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                        Text("Drop Zone")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                )
                .onDrop(of: [.text, .plainText, .fileURL, .vCard, UTType.crmContactList], isTargeted: nil) { providers in
                    logMessage("🎯 DROP RECEIVED with \(providers.count) providers")
                    
                    for (index, provider) in providers.enumerated() {
                        logMessage("📦 Provider \(index):")
                        logMessage("   Registered types: \(provider.registeredTypeIdentifiers)")
                        
                        // Try to load data for each registered type
                        for typeId in provider.registeredTypeIdentifiers {
                            logMessage("   🔍 Trying to load: \(typeId)")
                            
                            provider.loadDataRepresentation(forTypeIdentifier: typeId) { data, error in
                                if let error = error {
                                    logMessage("   ❌ Error loading \(typeId): \(error)")
                                    return
                                }
                                
                                guard let data = data else {
                                    logMessage("   ❌ No data for \(typeId)")
                                    return
                                }
                                
                                logMessage("   ✅ Successfully loaded \(typeId) (\(data.count) bytes)")
                                
                                // Try to decode as string
                                if let string = String(data: data, encoding: .utf8) {
                                    logMessage("   📝 String content: \(string)")
                                } else {
                                    logMessage("   📝 Binary data (not UTF-8 string)")
                                }
                                
                                // Try to decode as Contact if it's our custom type
                                if typeId == UTType.crmContactList.identifier {
                                    if let contact = try? JSONDecoder().decode(Contact.self, from: data) {
                                        logMessage("   👤 Decoded Contact: \(contact.name) (\(contact.phone))")
                                    } else {
                                        logMessage("   ❌ Failed to decode Contact from JSON")
                                    }
                                }
                                
                                // Try to decode as vCard
                                if typeId == UTType.vCard.identifier {
                                    let vCardString = String(data: data, encoding: .utf8) ?? ""
                                    let contact = Contact.fromVCardString(vCardString)
                                    if !contact.phone.isEmpty {
                                        logMessage("   👤 Decoded vCard Contact: \(contact.name) (\(contact.phone)) with UID: \(contact.id)")
                                    } else {
                                        logMessage("   ❌ Failed to decode vCard Contact")
                                    }
                                }
                            }
                        }
                    }
                    
                    return true
                }
            
            // Log display
            VStack(alignment: .leading, spacing: 8) {
                Text("Log:")
                    .font(.headline)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(logMessages, id: \.self) { message in
                            Text(message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .frame(height: 200)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Clear log button
            Button("Clear Log") {
                logMessages.removeAll()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 500, height: 600)
    }
    
    private func logMessage(_ message: String) {
        let timestamp = DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)] \(message)"
        logMessages.append(logEntry)
        print(logEntry) // Also print to console
    }
}

// Contact model (simplified version for testing)
struct Contact: Codable {
    var id: UUID
    var phone: String
    var name: String
    var firstName: String?
    var lastName: String?
    var email: String?
    var address: String?
    var notes: String?
    var business: String?
    
    static func fromVCardString(_ vCardString: String) -> Contact {
        let lines = vCardString.components(separatedBy: .newlines)
        var name = ""
        var firstName = ""
        var lastName = ""
        var phone = ""
        var email = ""
        var address = ""
        var notes = ""
        var business = ""
        
        for line in lines {
            if line.hasPrefix("FN:") {
                name = String(line.dropFirst(3))
            } else if line.hasPrefix("N:") {
                let parts = String(line.dropFirst(2)).components(separatedBy: ";")
                if parts.count >= 2 {
                    lastName = parts[0]
                    firstName = parts[1]
                }
            } else if line.hasPrefix("TEL;") {
                phone = String(line.components(separatedBy: ":").last ?? "")
            } else if line.hasPrefix("EMAIL:") {
                email = String(line.dropFirst(6))
            } else if line.hasPrefix("ADR:") {
                address = String(line.dropFirst(4))
            } else if line.hasPrefix("NOTE:") {
                notes = String(line.dropFirst(5))
            } else if line.hasPrefix("ORG:") {
                business = String(line.dropFirst(4))
            }
        }
        
        return Contact(
            id: UUID(),
            phone: phone,
            name: name.isEmpty ? "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) : name,
            firstName: firstName.isEmpty ? nil : firstName,
            lastName: lastName.isEmpty ? nil : lastName,
            email: email.isEmpty ? nil : email,
            address: address.isEmpty ? nil : address,
            notes: notes.isEmpty ? nil : notes,
            business: business.isEmpty ? nil : business
        )
    }
}

// Custom UTType for our contacts
extension UTType {
    static let crmContactList = UTType(exportedAs: "com.mycrm.contact-list")
}
