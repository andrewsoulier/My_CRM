import SwiftUI

struct BatchMessageEditModal: View {
    let message: BatchMessage
    let availableFields: [String]
    let onSave: (BatchMessage) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    
    @State private var messageBody: String
    @State private var chipMetadata: ChipMetadata?
    @State private var scheduledDate: Date?
    @State private var notifyWhenSent: Bool
    @State private var fieldSuggestions: [String] = []
    @State private var showingFieldSuggestions = false
    @State private var showingSchedulePicker = false
    @State private var isSaving = false
    
    private let logger = LogManager.shared
    
    init(message: BatchMessage, availableFields: [String], onSave: @escaping (BatchMessage) -> Void) {
        self.message = message
        self.availableFields = availableFields
        self.onSave = onSave
        
        // Initialize state from message
        _messageBody = State(initialValue: message.messageTemplate)
        _chipMetadata = State(initialValue: message.chipMetadata)
        _scheduledDate = State(initialValue: message.scheduledTime)
        _notifyWhenSent = State(initialValue: message.notifyWhenSent)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Recipients section
                    recipientsView
                    
                    // Message body editor
                    messageBodyView
                    
                    // Schedule section
                    scheduleView
                    
                    // Notify checkbox
                    Toggle("Notify when sent", isOn: $notifyWhenSent)
                        .toggleStyle(.checkbox)
                }
                .padding()
            }
            
            Divider()
            
            // Footer with action buttons
            footerView
        }
        .frame(width: 600, height: 600)
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showingSchedulePicker) {
            SchedulePickerModal(
                selectedDate: Binding(
                    get: { scheduledDate ?? Date().addingTimeInterval(3600) },
                    set: { scheduledDate = $0 }
                ),
                onSchedule: { date in 
                    scheduledDate = date
                    showingSchedulePicker = false
                }
            )
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Text("Edit Message")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlColor))
    }
    
    // MARK: - Recipients View
    private var recipientsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recipients")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                if message.recipients.isEmpty {
                    Text("No recipients")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    // Group recipients by source group
                    let groupedRecipients = Dictionary(grouping: message.recipients) { $0.sourceGroupId }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Display groups first
                        if let sourceGroups = message.sourceGroups {
                            ForEach(sourceGroups, id: \.self) { groupId in
                                if let group = dataProvider.groups.first(where: { $0.id == groupId }) {
                                    GroupDisplayChip(
                                        group: group,
                                        memberCount: groupedRecipients[groupId]?.count ?? 0
                                    )
                                }
                            }
                        }
                        
                        // Display individual contacts (no source group)
                        if let individualRecipients = groupedRecipients[nil], !individualRecipients.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading, spacing: 8) {
                                ForEach(individualRecipients, id: \.phone) { recipient in
                                    RecipientDisplayChip(recipient: recipient)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            
            Text("Note: Group members will be recalculated when you save changes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Message Body View
    private var messageBodyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message")
                .font(.headline)
                .fontWeight(.semibold)
            
            ZStack(alignment: .topLeading) {
                if messageBody.isEmpty {
                    Text("Type your message here... Use @field to insert contact fields")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                
                MessageBodyEditor(
                    text: $messageBody,
                    chipMetadata: $chipMetadata,
                    availableFields: availableFields,
                    fieldSuggestions: $fieldSuggestions,
                    showingFieldSuggestions: $showingFieldSuggestions
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 200)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Schedule View
    private var scheduleView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack {
                if let scheduledDate = scheduledDate {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.blue)
                            
                            Text(scheduledDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        
                        Text(relativeTimeDescription(for: scheduledDate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    
                    Button(action: { showingSchedulePicker = true }) {
                        Text("Change")
                    }
                    
                    Button(action: { 
                        self.scheduledDate = nil 
                    }) {
                        Text("Clear")
                    }
                    .foregroundColor(.red)
                } else {
                    Text("Send immediately")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                    
                    Button(action: { 
                        scheduledDate = Date().addingTimeInterval(3600)
                        showingSchedulePicker = true
                    }) {
                        HStack {
                            Image(systemName: "clock")
                            Text("Schedule")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape)
            
            Spacer()
            
            Button(action: handleSave) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(isSaving ? "Saving..." : "Save Changes")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
            .disabled(messageBody.isEmpty || isSaving)
        }
        .padding()
        .background(Color(NSColor.controlColor))
    }
    
    // MARK: - Helper Methods
    private func relativeTimeDescription(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func handleSave() {
        logger.info("💾 BatchMessageEditModal: Saving changes to message \(message.id)")
        
        isSaving = true
        
        // Recalculate recipients if there are source groups
        var updatedRecipients: [BatchRecipient] = []
        
        if let sourceGroups = message.sourceGroups, !sourceGroups.isEmpty {
            logger.info("👥 BatchMessageEditModal: Recalculating recipients from \(sourceGroups.count) group(s)")
            
            // Recalculate group members
            for groupId in sourceGroups {
                if let group = dataProvider.groups.first(where: { $0.id == groupId }) {
                    logger.info("👥 BatchMessageEditModal: Processing group: \(group.name) with \(group.memberPhones.count) members")
                    
                    for phone in group.memberPhones {
                        if let contact = dataProvider.contacts.first(where: { $0.phone == phone }) {
                            let fieldValues = createFieldValues(for: contact)
                            let batchRecipient = BatchRecipient(
                                phone: contact.phone,
                                name: contact.displayName,
                                email: contact.email,
                                fieldValues: fieldValues,
                                sourceGroupId: groupId
                            )
                            // Skip duplicates
                            if !updatedRecipients.contains(where: { $0.phone == batchRecipient.phone }) {
                                updatedRecipients.append(batchRecipient)
                            }
                        } else {
                            logger.warning("⚠️ BatchMessageEditModal: Contact not found for phone: \(phone)")
                        }
                    }
                } else {
                    logger.warning("⚠️ BatchMessageEditModal: Group not found: \(groupId)")
                }
            }
            
            // Add individual recipients (those without source group)
            for recipient in message.recipients where recipient.sourceGroupId == nil {
                if !updatedRecipients.contains(where: { $0.phone == recipient.phone }) {
                    updatedRecipients.append(recipient)
                }
            }
            
            logger.info("✅ BatchMessageEditModal: Recalculated recipients: \(updatedRecipients.count) total")
        } else {
            // No groups, keep original recipients
            updatedRecipients = message.recipients
        }
        
        // Create new message with updated values
        let updatedMessage = BatchMessage(
            id: message.id,
            messageTemplate: messageBody,
            chipMetadata: chipMetadata,
            recipients: updatedRecipients,
            scheduledTime: scheduledDate,
            createdTime: message.createdTime,
            status: message.status,
            totalRecipients: updatedRecipients.count,
            sentCount: message.sentCount,
            failedCount: message.failedCount,
            failedContacts: message.failedContacts,
            completedTime: message.completedTime,
            notifyWhenSent: notifyWhenSent,
            errorLog: message.errorLog,
            sourceGroups: message.sourceGroups
        )
        
        logger.info("✅ BatchMessageEditModal: Calling onSave with updated message")
        onSave(updatedMessage)
        
        isSaving = false
        dismiss()
    }
    
    // Helper to create field values for a contact
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
}

// MARK: - Supporting Views
struct RecipientDisplayChip: View {
    let recipient: BatchRecipient
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.circle.fill")
                .font(.caption)
                .foregroundColor(.blue)
            
            Text(recipient.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

struct GroupDisplayChip: View {
    let group: ContactGroup
    let memberCount: Int
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.3.fill")
                .font(.caption)
                .foregroundColor(.white)
            
            Text(group.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            Text("(\(memberCount))")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(group.color)
        .cornerRadius(12)
    }
}

