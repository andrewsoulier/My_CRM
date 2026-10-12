import SwiftUI

struct QuickSendView: View {
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var appState: AppState
    @StateObject private var batchMessageService = BatchMessageService.shared
    @StateObject private var schedulingService = SchedulingService.shared
    
    private let logger = LogManager.shared
    
    @State private var selectedRecipients: [RecipientChip] = []
    @State private var messageBody = ""
    @State private var chipMetadata: ChipMetadata?
    @State private var searchText = ""
    @State private var scheduledDate: Date?
    @State private var notifyWhenSent = false
    @State private var showingPreview = false
    @State private var showingSchedulePicker = false
    @State private var selectedTab: QuickSendTab = .compose
    
    // Edit modal state
    @State private var showingEditModal = false
    @State private var messageToEdit: BatchMessage?
    
    // Loading and error states
    @State private var isSaving = false
    @State private var isSending = false
    @State private var saveError: String?
    @State private var showSaveError = false
    
    // Authorization state
    @State private var showingAuthorizationView = false
    @StateObject private var authManager = MessagesAuthorizationManager.shared
    
    // Available contact fields for @field replacement (excluding safe fields)
    @State private var availableFields: [String] = []
    @State private var fieldSuggestions: [String] = []
    @State private var showingFieldSuggestions = false
    @State private var fieldInputRange: NSRange?
    
    enum QuickSendTab: String, CaseIterable {
        case compose = "Compose"
        case queued = "Queued"
        case history = "History"
        
        var icon: String {
            switch self {
            case .compose: return "pencil.and.outline"
            case .queued: return "clock.fill"
            case .history: return "list.bullet.rectangle"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Main compose view
            composeView
            
            // Bottom section with tabs
            bottomSectionView
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            logger.info("🚀 QuickSendView: onAppear called")
            loadAvailableFields()
            batchMessageService.configure(with: dataProvider)
            schedulingService.startTriggerFileMonitoring()
            
            // Check authorization status on appear
            Task {
                await authManager.checkAuthorizationStatus()
            }
            
            logger.info("✅ QuickSendView: Initialization complete")
        }
        .sheet(isPresented: $showingPreview) {
            MessagePreviewModal(
                recipients: selectedRecipients,
                messageTemplate: convertRichTextToTemplate(messageBody, chipMetadata: chipMetadata),
                chipMetadata: chipMetadata,
                availableFields: availableFields,
                onSend: handleSend,
                onSchedule: { date in handleSchedule(date: date) },
                initialScheduledDate: scheduledDate
            )
        }
        .sheet(isPresented: $showingSchedulePicker) {
            SchedulePickerModal(
                selectedDate: Binding(
                    get: { scheduledDate ?? Date().addingTimeInterval(3600) },
                    set: { scheduledDate = $0 }
                ),
                onSchedule: { date in handleSchedule(date: date) }
            )
        }
        .sheet(isPresented: $showingEditModal) {
            if let messageToEdit = messageToEdit {
                BatchMessageEditModal(
                    message: messageToEdit,
                    availableFields: availableFields,
                    onSave: handleEditSave
                )
                .environmentObject(dataProvider)
            }
        }
        .alert("Save Error", isPresented: $showSaveError) {
            Button("OK") {
                showSaveError = false
                saveError = nil
            }
        } message: {
            Text(saveError ?? "An unknown error occurred while saving the message.")
        }
        .sheet(isPresented: $showingAuthorizationView) {
            MessagesAuthorizationView(onAuthorized: {
                // User has granted authorization, can now proceed
                logger.info("✅ Authorization granted, user can now send messages")
            })
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Text("Quick Send")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            // Status indicators
            HStack(spacing: 12) {
                // Authorization status indicator
                if authManager.authorizationStatus != .authorized {
                    Button(action: {
                        showingAuthorizationView = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.shield")
                                .foregroundColor(.orange)
                            Text("Setup Required")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                // Processing indicator
                if batchMessageService.isProcessingMessages {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Sending...")
                            .font(.caption)
                            .foregroundColor(.primary)
                        
                        if batchMessageService.processingProgress > 0 {
                            Text("\(Int(batchMessageService.processingProgress * 100))%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Queued messages indicator
                if !dataProvider.batchMessages.filter({ $0.status == .scheduled }).isEmpty {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("\(dataProvider.batchMessages.filter({ $0.status == .scheduled }).count) queued")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlColor))
    }
    
    // MARK: - Bottom Section
    private var bottomSectionView: some View {
        VStack(spacing: 0) {
            Divider()
            
            // Tab selection for bottom section
            HStack(spacing: 0) {
                ForEach([QuickSendTab.queued, QuickSendTab.history], id: \.self) { tab in
                    Button(action: {
                        logger.info("🔄 QuickSendView: Switching to tab: \(tab.rawValue)")
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.caption)
                            Text(tab.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(selectedTab == tab ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlColor))
            
            // Content based on selected tab
            switch selectedTab {
            case .compose:
                EmptyView() // Compose is handled above
            case .queued:
                queuedMessagesView
            case .history:
                historyView
            }
        }
        .frame(height: 300) // Fixed height for bottom section
    }
    
    // MARK: - Compose View
    private var composeView: some View {
        VStack(spacing: 16) {
            // To Field
            toFieldView
            
            // Message Body
            messageBodyView
            
            // Action Buttons
            actionButtonsView
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - To Field
    private var toFieldView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                // Selected recipients chips
                if !selectedRecipients.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading, spacing: 8) {
                        ForEach(selectedRecipients, id: \.id) { recipient in
                            RecipientChipView(recipient: recipient) {
                                removeRecipient(recipient)
                            }
                        }
                    }
                }
                
                // Search field with autocomplete
                RecipientSearchField(
                    searchText: $searchText,
                    dataProvider: dataProvider,
                    onContactSelected: { contact in
                        addContact(contact)
                    },
                    onGroupSelected: { group in
                        addGroup(group)
                    }
                )
            }
            .padding()
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            // Add drop destination for contacts
            .dropDestination(for: Contact.self) { contacts, location in
                logger.info("📥 QuickSendView: Dropped \(contacts.count) contact(s)")
                for contact in contacts {
                    logger.info("👤 QuickSendView: Dropped contact: \(contact.displayName) (\(contact.phone))")
                    addContact(contact)
                }
                return true
            }
            // Add drop destination for groups
            .dropDestination(for: ContactGroup.self) { groups, location in
                logger.info("📥 QuickSendView: Dropped \(groups.count) group(s)")
                for group in groups {
                    logger.info("👥 QuickSendView: Dropped group: \(group.name) with \(group.memberPhones.count) members")
                    addGroup(group)
                }
                return true
            }
        }
    }
    
    // MARK: - Message Body
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
            .frame(height: 120)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Action Buttons
    private var actionButtonsView: some View {
        HStack {
            // Notify checkbox
            Toggle("Notify when sent", isOn: $notifyWhenSent)
                .toggleStyle(.checkbox)
            
            Spacer()
            
            // Schedule button
            Button(action: {
                logger.info("🗓️ QuickSendView: Schedule Send button pressed")
                showingPreview = true
                scheduledDate = Date().addingTimeInterval(3600) // Default to 1 hour from now
            }) {
                HStack {
                    if isSaving || isSending {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(isSaving ? "Saving..." : isSending ? "Scheduling..." : "Schedule Send")
                }
            }
            .disabled(selectedRecipients.isEmpty || messageBody.isEmpty || isSaving || isSending)
            
            // Send button
            Button(action: {
                logger.info("📤 QuickSendView: Send Now button pressed")
                showingPreview = true
                scheduledDate = nil
            }) {
                HStack {
                    if isSaving || isSending {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text(isSaving ? "Saving..." : isSending ? "Sending..." : "Send Now")
                }
            }
            .disabled(selectedRecipients.isEmpty || messageBody.isEmpty || batchMessageService.isProcessingMessages || isSaving || isSending)
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Queued Messages View
    private var queuedMessagesView: some View {
        VStack {
            if dataProvider.batchMessages.filter({ $0.status == .scheduled }).isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No queued messages")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Scheduled messages will appear here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                BatchMessageTableView(
                    messages: dataProvider.batchMessages.filter({ $0.status == .scheduled }),
                    onEdit: { message in
                        logger.info("✏️ QuickSendView: Editing message: \(message.id)")
                        messageToEdit = message
                        showingEditModal = true
                    },
                    onDelete: { message in
                        handleDelete(message: message)
                    }
                )
            }
        }
        .padding()
    }
    
    // MARK: - History View
    private var historyView: some View {
        VStack {
            if dataProvider.batchMessages.filter({ $0.status == .completed || $0.status == .failed }).isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No message history")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Sent messages will appear here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                BatchMessageTableView(
                    messages: dataProvider.batchMessages.filter({ $0.status == .completed || $0.status == .failed }),
                    onEdit: nil, // No editing for completed messages
                    onDelete: { message in
                        handleDelete(message: message)
                    }
                )
            }
        }
        .padding()
    }
    
    // MARK: - Helper Methods
    private func loadAvailableFields() {
        // Get all column names from the contacts table, excluding the unsafe ones
        // In a real implementation, you'd query the database schema and filter out excluded fields
        availableFields = [
            "phone", "name", "first_name", "last_name", "email", 
            "address", "notes", "business", "contact_group", "birthday"
        ]
    }
    
    private func addContact(_ contact: Contact) {
        logger.info("👤 QuickSendView: Adding contact: \(contact.displayName) (\(contact.phone))")
        
        let recipient = RecipientChip(
            id: UUID(),
            type: .contact,
            displayName: contact.displayName,
            identifier: contact.phone,
            contact: contact
        )
        
        if !selectedRecipients.contains(where: { $0.identifier == recipient.identifier }) {
            selectedRecipients.append(recipient)
            logger.info("✅ QuickSendView: Contact added successfully. Total recipients: \(selectedRecipients.count)")
        } else {
            logger.warning("⚠️ QuickSendView: Contact already in recipients list")
        }
        searchText = ""
    }
    
    private func addGroup(_ group: ContactGroup) {
        logger.info("👥 QuickSendView: Adding group: \(group.name) with \(group.memberPhones.count) members")
        
        let recipient = RecipientChip(
            id: UUID(),
            type: .group,
            displayName: group.name,
            identifier: group.id.uuidString,
            group: group
        )
        
        if !selectedRecipients.contains(where: { $0.identifier == recipient.identifier }) {
            selectedRecipients.append(recipient)
            logger.info("✅ QuickSendView: Group added successfully. Total recipients: \(selectedRecipients.count)")
        } else {
            logger.warning("⚠️ QuickSendView: Group already in recipients list")
        }
        searchText = ""
    }
    
    private func removeRecipient(_ recipient: RecipientChip) {
        logger.info("🗑️ QuickSendView: Removing recipient: \(recipient.displayName)")
        selectedRecipients.removeAll { $0.id == recipient.id }
        logger.info("✅ QuickSendView: Recipient removed. Total recipients: \(selectedRecipients.count)")
    }
    
    private func handleSend() {
        print("🚀 DEBUG: handleSend() called")
        logger.info("🚀 QuickSendView: handleSend() called")
        Task {
            await sendMessage(scheduledTime: nil)
        }
    }
    
    private func handleSchedule(date: Date) {
        print("🚀 DEBUG: handleSchedule() called with date: \(date)")
        logger.info("🚀 QuickSendView: handleSchedule() called with date: \(date)")
        Task {
            await sendMessage(scheduledTime: date)
        }
    }
    
    private func sendMessage(scheduledTime: Date?) async {
        // Validate input before starting
        guard !selectedRecipients.isEmpty else {
            appState.showError("Please select at least one recipient.")
            return
        }
        
        guard !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appState.showError("Please enter a message.")
            return
        }
        
        // MARK: - Pre-Send Authorization Check
        logger.info("🔍 QuickSendView: Checking Messages authorization...")
        
        let validationResult = await authManager.validateCanSendMessages()
        
        if !validationResult.canSend {
            logger.warning("⚠️ QuickSendView: Authorization check failed")
            
            // Show authorization view to guide user
            showingAuthorizationView = true
            
            // Show error message
            let errorIssues = validationResult.issues.filter { $0.severity == .error }
            if let firstError = errorIssues.first {
                appState.showError(firstError.description)
            }
            
            return
        }
        
        logger.info("✅ QuickSendView: Authorization check passed")
        
        // Set loading state
        isSaving = true
        isSending = false
        saveError = nil
        showSaveError = false
        
        logger.info("📨 QuickSendView: Starting sendMessage")
        logger.info("📊 QuickSendView: Recipients count: \(selectedRecipients.count)")
        logger.info("📝 QuickSendView: Message body: '\(messageBody)'")
        logger.info("⏰ QuickSendView: Scheduled time: \(scheduledTime?.formatted() ?? "immediate")")
        
        do {
            // Convert recipients to BatchRecipients and track source groups
            var batchRecipients: [BatchRecipient] = []
            var sourceGroupIds: [UUID] = []
            
            for recipientChip in selectedRecipients {
                switch recipientChip.type {
                case .contact:
                    if let contact = recipientChip.contact {
                        logger.info("👤 QuickSendView: Processing contact: \(contact.displayName) (\(contact.phone))")
                        let fieldValues = createFieldValues(for: contact)
                        let batchRecipient = BatchRecipient(
                            phone: contact.phone,
                            name: contact.displayName,
                            email: contact.email,
                            fieldValues: fieldValues,
                            sourceGroupId: nil
                        )
                        // Skip duplicates
                        if !batchRecipients.contains(where: { $0.phone == batchRecipient.phone }) {
                            batchRecipients.append(batchRecipient)
                        } else {
                            logger.info("⚠️ QuickSendView: Skipping duplicate contact: \(contact.phone)")
                        }
                    } else {
                        logger.error("❌ QuickSendView: Contact is nil for recipient chip")
                        throw NSError(domain: "QuickSendView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid contact data"])
                    }
                case .group:
                    if let group = recipientChip.group {
                        logger.info("👥 QuickSendView: Processing group: \(group.name) with \(group.memberPhones.count) members")
                        // Track this group ID
                        sourceGroupIds.append(group.id)
                        
                        // Expand group members
                        for phone in group.memberPhones {
                            if let contact = dataProvider.contacts.first(where: { $0.phone == phone }) {
                                logger.info("👤 QuickSendView: Processing group member: \(contact.displayName) (\(phone))")
                                let fieldValues = createFieldValues(for: contact)
                                let batchRecipient = BatchRecipient(
                                    phone: contact.phone,
                                    name: contact.displayName,
                                    email: contact.email,
                                    fieldValues: fieldValues,
                                    sourceGroupId: group.id
                                )
                                // Skip duplicates
                                if !batchRecipients.contains(where: { $0.phone == batchRecipient.phone }) {
                                    batchRecipients.append(batchRecipient)
                                } else {
                                    logger.info("⚠️ QuickSendView: Skipping duplicate contact: \(phone)")
                                }
                            } else {
                                logger.warning("⚠️ QuickSendView: Contact not found for phone: \(phone)")
                            }
                        }
                    } else {
                        logger.error("❌ QuickSendView: Group is nil for recipient chip")
                        throw NSError(domain: "QuickSendView", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid group data"])
                    }
                }
            }
            
            logger.info("📊 QuickSendView: Final batch recipients count: \(batchRecipients.count)")
            
            if batchRecipients.isEmpty {
                throw NSError(domain: "QuickSendView", code: 3, userInfo: [NSLocalizedDescriptionKey: "No valid recipients found"])
            }
            
            // Convert rich text to plain text template
            let plainTextTemplate = convertRichTextToTemplate(messageBody, chipMetadata: chipMetadata)
            logger.info("📝 QuickSendView: Converted message body to template: '\(plainTextTemplate)'")
            
            // Create batch message with source groups
            let sourceGroups = sourceGroupIds.isEmpty ? nil : sourceGroupIds
            if let sourceGroups = sourceGroups {
                logger.info("👥 QuickSendView: Message created from \(sourceGroups.count) group(s)")
            }
            
            let batchMessage = BatchMessage(
                messageTemplate: plainTextTemplate,
                chipMetadata: chipMetadata,
                recipients: batchRecipients,
                scheduledTime: scheduledTime,
                notifyWhenSent: notifyWhenSent,
                sourceGroups: sourceGroups
            )
            
            logger.info("💾 QuickSendView: Created batch message with ID: \(batchMessage.id)")
            logger.info("💾 QuickSendView: Saving to database...")
            
            // Save to database with error handling
            await dataProvider.saveBatchMessage(batchMessage)
            
            logger.info("✅ QuickSendView: Batch message saved to database")
            
            // Switch to sending state
            isSaving = false
            isSending = true
            
            // Handle scheduling or immediate sending
            if let scheduledTime = scheduledTime {
                logger.info("⏰ QuickSendView: Scheduling message for: \(scheduledTime)")
                // Schedule the message using launchd
                let scheduled = await schedulingService.scheduleMessage(batchMessage)
                if scheduled {
                    logger.info("✅ QuickSendView: Message scheduled successfully")
                    appState.showMessage("Message scheduled successfully for \(scheduledTime.formatted(date: .abbreviated, time: .shortened))!")
                    selectedTab = .queued
                } else {
                    logger.error("❌ QuickSendView: Failed to schedule message")
                    throw NSError(domain: "QuickSendView", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to schedule message. Please try again."])
                }
            } else {
                logger.info("📤 QuickSendView: Sending message immediately")
                // Send immediately
                await batchMessageService.sendBatchMessageNow(batchMessage)
                logger.info("✅ QuickSendView: Message sending initiated")
                selectedTab = .history
            }
            
            // Clear form on success
            selectedRecipients.removeAll()
            messageBody = ""
            notifyWhenSent = false
            scheduledDate = nil
            chipMetadata = nil
            
        } catch {
            logger.error("❌ QuickSendView: Error in sendMessage: \(error.localizedDescription)")
            saveError = error.localizedDescription
            showSaveError = true
            appState.showError("Failed to send message: \(error.localizedDescription)")
        }
        
        // Clear loading states
        isSaving = false
        isSending = false
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
    
    private func handleEditSave(_ updatedMessage: BatchMessage) {
        logger.info("💾 QuickSendView: Saving edited message: \(updatedMessage.id)")
        
        Task {
            // Update the message in the database
            await dataProvider.updateBatchMessage(updatedMessage)
            
            // If the message is scheduled, update the schedule
            if let scheduledTime = updatedMessage.scheduledTime {
                logger.info("⏰ QuickSendView: Rescheduling message for: \(scheduledTime)")
                
                // Cancel existing schedule if any
                let _ = await schedulingService.cancelScheduledMessage(updatedMessage.id)
                
                // Reschedule with new time
                let scheduled = await schedulingService.scheduleMessage(updatedMessage)
                if scheduled {
                    logger.info("✅ QuickSendView: Message rescheduled successfully")
                    appState.showMessage("Message updated and rescheduled for \(scheduledTime.formatted(date: .abbreviated, time: .shortened))!")
                } else {
                    logger.error("❌ QuickSendView: Failed to reschedule message")
                    appState.showError("Failed to reschedule message. Please try again.")
                }
            } else {
                logger.info("✅ QuickSendView: Message updated successfully")
                appState.showMessage("Message updated successfully!")
            }
        }
    }
    
    private func handleDelete(message: BatchMessage) {
        logger.info("🗑️ QuickSendView: Deleting message: \(message.id)")
        
        Task {
            // If the message is scheduled, cancel the scheduled job first
            if message.status == .scheduled && message.scheduledTime != nil {
                logger.info("⏰ QuickSendView: Canceling scheduled job for message: \(message.id)")
                let cancelled = await schedulingService.cancelScheduledMessage(message.id)
                if cancelled {
                    logger.info("✅ QuickSendView: Scheduled job cancelled successfully")
                } else {
                    logger.warning("⚠️ QuickSendView: Failed to cancel scheduled job (may not exist)")
                }
            }
            
            // Delete from database (this also removes from memory array)
            await dataProvider.deleteBatchMessage(message.id)
            logger.info("✅ QuickSendView: Message deleted from database")
            
            // Show success message
            appState.showMessage("Message deleted successfully")
        }
    }
    
    /// Convert rich text with NSTextAttachment characters to plain text template with @field placeholders
    private func convertRichTextToTemplate(_ richText: String, chipMetadata: ChipMetadata?) -> String {
        logger.info("🔄 QuickSendView.convertRichTextToTemplate: Input text length: \(richText.count)")
        logger.info("🔄 QuickSendView.convertRichTextToTemplate: Input text: '\(richText)'")
        logger.info("🔄 QuickSendView.convertRichTextToTemplate: ChipMetadata: \(chipMetadata?.chips.count ?? 0) chips")
        
        guard let metadata = chipMetadata, !metadata.chips.isEmpty else {
            logger.warning("⚠️ QuickSendView.convertRichTextToTemplate: No chip metadata, stripping object replacement characters")
            // No chips, return as-is (but might still have object replacement characters)
            // Replace any orphan object replacement characters with empty string
            let cleaned = richText.replacingOccurrences(of: "\u{FFFC}", with: "")
            logger.info("🔄 QuickSendView.convertRichTextToTemplate: Result after cleanup: '\(cleaned)'")
            return cleaned
        }
        
        var result = richText
        
        // Sort chips by startIndex in reverse order to avoid index shifting
        let sortedChips = metadata.chips.sorted { $0.startIndex > $1.startIndex }
        
        logger.info("🔄 QuickSendView.convertRichTextToTemplate: Processing \(sortedChips.count) chips")
        for (index, chip) in sortedChips.enumerated() {
            logger.info("🔄 QuickSendView.convertRichTextToTemplate: Chip \(index): type=\(chip.type), field=\(chip.field ?? "nil"), range=\(chip.startIndex)-\(chip.endIndex)")
            
            if chip.type == .contactField, let fieldName = chip.field {
                let range = NSRange(location: chip.startIndex, length: chip.endIndex - chip.startIndex)
                if range.location + range.length <= result.count {
                    let before = result
                    result = (result as NSString).replacingCharacters(in: range, with: "@\(fieldName)")
                    logger.info("✅ QuickSendView.convertRichTextToTemplate: Replaced range \(range) with '@\(fieldName)'")
                    logger.info("   Before: '\(before)'")
                    logger.info("   After:  '\(result)'")
                } else {
                    logger.error("❌ QuickSendView.convertRichTextToTemplate: Invalid range \(range) for text length \(result.count)")
                }
            }
        }
        
        logger.info("✅ QuickSendView.convertRichTextToTemplate: Final result: '\(result)'")
        return result
    }
}

// MARK: - Supporting Types
struct RecipientChip: Identifiable {
    let id: UUID
    let type: RecipientType
    let displayName: String
    let identifier: String // phone for contact, UUID string for group
    let contact: Contact?
    let group: ContactGroup?
    
    init(id: UUID, type: RecipientType, displayName: String, identifier: String, contact: Contact? = nil, group: ContactGroup? = nil) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.identifier = identifier
        self.contact = contact
        self.group = group
    }
    
    enum RecipientType {
        case contact
        case group
    }
}
