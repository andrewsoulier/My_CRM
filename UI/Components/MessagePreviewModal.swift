import SwiftUI

struct MessagePreviewModal: View {
    let recipients: [RecipientChip]
    let messageTemplate: String
    let chipMetadata: ChipMetadata?
    let availableFields: [String]
    let onSend: () -> Void
    let onSchedule: (Date) -> Void
    let initialScheduledDate: Date? // nil for immediate send, Date for scheduled send
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @State private var selectedRecipientIndex = 0
    @State private var showingSchedulePicker = false
    @State private var scheduledDate = Date().addingTimeInterval(3600) // Default to 1 hour from now
    @State private var isScheduling = false
    
    // Sample recipients for preview
    private var sampleRecipients: [BatchRecipient] {
        print("🔍 MessagePreviewModal: Computing sampleRecipients from \(recipients.count) recipient chips")
        var samples: [BatchRecipient] = []
        
        for recipientChip in recipients {
            switch recipientChip.type {
            case .contact:
                if let contact = recipientChip.contact {
                    print("🔍 MessagePreviewModal: Adding contact: \(contact.displayName)")
                    let fieldValues = createFieldValues(for: contact)
                    samples.append(BatchRecipient(
                        phone: contact.phone,
                        name: contact.displayName,
                        email: contact.email,
                        fieldValues: fieldValues,
                        sourceGroupId: nil
                    ))
                } else {
                    // Attempt to resolve contact by identifier (phone)
                    if let resolved = dataProvider.contacts.first(where: { $0.phone == recipientChip.identifier }) {
                        print("🔍 MessagePreviewModal: Resolved contact by phone: \(resolved.displayName)")
                        let fieldValues = createFieldValues(for: resolved)
                        samples.append(BatchRecipient(
                            phone: resolved.phone,
                            name: resolved.displayName,
                            email: resolved.email,
                            fieldValues: fieldValues,
                            sourceGroupId: nil
                        ))
                    } else {
                        print("⚠️ MessagePreviewModal: Could not resolve contact for identifier: \(recipientChip.identifier)")
                    }
                }
            case .group:
                if let group = recipientChip.group {
                    print("🔍 MessagePreviewModal: Adding group members from: \(group.name)")
                    // For preview, just show first few members
                    let memberPhones = Array(group.memberPhones.prefix(3))
                    for phone in memberPhones {
                        if let contact = dataProvider.contacts.first(where: { $0.phone == phone }) {
                            let fieldValues = createFieldValues(for: contact)
                            samples.append(BatchRecipient(
                                phone: contact.phone,
                                name: contact.displayName,
                                email: contact.email,
                                fieldValues: fieldValues,
                                sourceGroupId: group.id
                            ))
                        } else {
                            // Fallback if not found in DB
                            let fieldValues = [
                                "phone": phone,
                                "name": phone,
                                "first_name": "",
                                "last_name": ""
                            ]
                            samples.append(BatchRecipient(
                                phone: phone,
                                name: phone,
                                email: nil,
                                fieldValues: fieldValues,
                                sourceGroupId: group.id
                            ))
                        }
                    }
                }
            }
        }
        
        print("🔍 MessagePreviewModal: Total sample recipients: \(samples.count)")
        return samples
    }
    
    private var currentSampleRecipient: BatchRecipient? {
        guard selectedRecipientIndex < sampleRecipients.count else { return nil }
        return sampleRecipients[selectedRecipientIndex]
    }
    
    private var previewMessage: String {
        guard let recipient = currentSampleRecipient else {
            print("🔍 MessagePreviewModal: No current sample recipient, returning template")
            return messageTemplate
        }
        print("🔍 MessagePreviewModal: Processing template for recipient: \(recipient.name)")
        print("🔍 MessagePreviewModal: Template: '\(messageTemplate)'")
        print("🔍 MessagePreviewModal: ChipMetadata: \(chipMetadata?.chips.count ?? 0) chips")
        print("🔍 MessagePreviewModal: Field keys: \(Array(recipient.fieldValues.keys))")
        let processed = TemplateEngine.process(
            template: messageTemplate,
            chipMetadata: chipMetadata,
            fieldValues: recipient.fieldValues
        )
        let previewSnippet = String(processed.prefix(120))
        print("🔍 MessagePreviewModal: Processed snippet: '\(previewSnippet)'")
        return processed
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Message Preview")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding(.horizontal)
            
            // Recipient selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview for:")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if sampleRecipients.count > 1 {
                    Picker("Recipient", selection: $selectedRecipientIndex) {
                        ForEach(0..<sampleRecipients.count, id: \.self) { index in
                            Text(sampleRecipients[index].name)
                                .tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let recipient = sampleRecipients.first {
                    Text(recipient.name)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                } else {
                    Text("No recipients available")
                        .font(.body)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            
            // Message preview
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Message Preview")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text("\(totalRecipientCount) recipients")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Template view
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Template:")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            SmartChipPreviewView(
                                text: messageTemplate,
                                availableFields: availableFields,
                                isTemplate: true
                            )
                            .frame(height: 80)
                            .cornerRadius(8)
                        }
                        
                        // Arrow
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.down")
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        
                        // Preview view
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Preview for \(currentSampleRecipient?.name ?? "Unknown"):")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            SmartChipPreviewView(
                                text: previewMessage,
                                availableFields: availableFields,
                                isTemplate: false
                            )
                            .frame(height: 80)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                if initialScheduledDate != nil {
                    // Scheduling mode
                    Button("Change Time") {
                        showingSchedulePicker = true
                    }
                    
                    Button("Schedule Send") {
                        onSchedule(scheduledDate)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                } else {
                    // Immediate send mode
                    Button("Schedule Instead") {
                        showingSchedulePicker = true
                    }
                    
                    Button("Send Now") {
                        onSend()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .frame(width: 600, height: 500)
        .sheet(isPresented: $showingSchedulePicker) {
            SchedulePickerModal(selectedDate: $scheduledDate) { date in
                onSchedule(date)
                dismiss()
            }
        }
        .onAppear {
            if let initialDate = initialScheduledDate {
                scheduledDate = initialDate
                isScheduling = true
            } else {
                isScheduling = false
            }
        }
    }
    
    private var totalRecipientCount: Int {
        var count = 0
        for recipientChip in recipients {
            switch recipientChip.type {
            case .contact:
                count += 1
            case .group:
                if let group = recipientChip.group {
                    count += group.memberPhones.count
                }
            }
        }
        return count
    }
    
    private func createFieldValues(for contact: Contact) -> [String: String] {
        var fieldValues: [String: String] = [:]
        
        fieldValues["phone"] = contact.phone
        fieldValues["name"] = contact.displayName
        // Derive first/last names from displayName if missing
        let first = (contact.firstName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let last = (contact.lastName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        if let first = first, let last = last {
            fieldValues["first_name"] = first
            fieldValues["last_name"] = last
        } else {
            let parts = contact.displayName.split(separator: " ")
            if parts.count >= 2 {
                fieldValues["first_name"] = String(parts.first!)
                fieldValues["last_name"] = String(parts.last!)
            } else if parts.count == 1 {
                fieldValues["first_name"] = String(parts[0])
                fieldValues["last_name"] = ""
            } else {
                fieldValues["first_name"] = ""
                fieldValues["last_name"] = ""
            }
        }
        fieldValues["email"] = contact.email ?? ""
        fieldValues["address"] = contact.address ?? ""
        fieldValues["notes"] = contact.notes ?? ""
        fieldValues["business"] = contact.business ?? ""
        fieldValues["contact_group"] = contact.contactGroup ?? ""
        fieldValues["birthday"] = contact.birthday?.formatted(date: .abbreviated, time: .omitted) ?? ""
        
        return fieldValues
    }
    
    private func processMessageTemplate(_ template: String, with fieldValues: [String: String]) -> String {
        var processedMessage = template
        
        // Replace @field references with actual values
        for field in availableFields {
            let fieldPattern = "@\(field)"
            let fieldValue = fieldValues[field] ?? ""
            processedMessage = processedMessage.replacingOccurrences(of: fieldPattern, with: fieldValue)
        }
        
        return processedMessage
    }
}
