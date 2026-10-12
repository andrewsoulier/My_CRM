import SwiftUI

struct ContactCreationModal: View {
    let initialName: String
    @Binding var isPresented: Bool
    let onContactCreated: (Contact) -> Void
    
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var appState: AppState
    
    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var email: String = ""
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var business: String = ""
    @State private var address: String = ""
    @State private var notes: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    
    private let logger = LogManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Create New Contact")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Form
            Form {
                Section(header: Text("Required Information")) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Phone Number", text: $phone)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section(header: Text("Optional Information")) {
                    TextField("First Name", text: $firstName)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Last Name", text: $lastName)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Business", text: $business)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Address", text: $address)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Notes", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)
            
            // Error message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: createContact) {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Create Contact")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || phone.isEmpty || isCreating)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .onAppear {
            // Pre-fill name if provided
            if !initialName.isEmpty {
                name = initialName
                // Try to parse phone number if it looks like one
                if initialName.allSatisfy({ $0.isNumber || $0 == "+" || $0 == "-" || $0 == "(" || $0 == ")" || $0 == " " }) {
                    phone = initialName
                    name = ""
                }
            }
        }
    }
    
    private func createContact() {
        guard !name.isEmpty && !phone.isEmpty else {
            errorMessage = "Name and phone number are required"
            return
        }
        
        // Check if contact with this phone already exists
        if dataProvider.contacts.contains(where: { $0.phone == phone }) {
            errorMessage = "A contact with this phone number already exists"
            return
        }
        
        isCreating = true
        errorMessage = nil
        
        Task {
            do {
                // Parse name into first/last if not provided separately
                var finalFirstName = firstName
                var finalLastName = lastName
                
                if finalFirstName.isEmpty && finalLastName.isEmpty && !name.isEmpty {
                    let nameParts = name.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
                    if nameParts.count >= 2 {
                        finalFirstName = nameParts.first ?? ""
                        finalLastName = nameParts.dropFirst().joined(separator: " ")
                    } else if nameParts.count == 1 {
                        finalFirstName = nameParts[0]
                    }
                }
                
                // Create contact
                let contact = Contact(
                    phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: name.isEmpty ? (finalFirstName + " " + finalLastName).trimmingCharacters(in: .whitespacesAndNewlines) : name,
                    firstName: finalFirstName.isEmpty ? nil : finalFirstName,
                    lastName: finalLastName.isEmpty ? nil : finalLastName,
                    email: email.isEmpty ? nil : email,
                    address: address.isEmpty ? nil : address,
                    notes: notes.isEmpty ? nil : notes,
                    business: business.isEmpty ? nil : business
                )
                
                // Save to database (refresh happens automatically in createContact)
                try await dataProvider.createContact(contact)
                
                // Find the created contact (it should now have a database ID)
                if let createdContact = dataProvider.contacts.first(where: { $0.phone == contact.phone }) {
                    logger.info("✅ ContactCreationModal: Created contact: \(createdContact.displayName) (\(createdContact.phone))")
                    
                    await MainActor.run {
                        isCreating = false
                        onContactCreated(createdContact)
                        isPresented = false
                    }
                } else {
                    throw NSError(domain: "ContactCreationModal", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to retrieve created contact"])
                }
            } catch {
                logger.error("❌ ContactCreationModal: Error creating contact: \(error.localizedDescription)")
                await MainActor.run {
                    isCreating = false
                    errorMessage = "Failed to create contact: \(error.localizedDescription)"
                }
            }
        }
    }
}

