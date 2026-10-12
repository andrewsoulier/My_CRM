import SwiftUI

struct BatchMessageTableView: View {
    let messages: [BatchMessage]
    let onEdit: ((BatchMessage) -> Void)?
    let onDelete: (BatchMessage) -> Void
    
    @State private var selectedMessage: BatchMessage?
    @State private var sortOrder: SortOrder = .newestFirst
    
    enum SortOrder: String, CaseIterable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
        case statusFirst = "By Status"
    }
    
    private var sortedMessages: [BatchMessage] {
        switch sortOrder {
        case .newestFirst:
            return messages.sorted { $0.createdTime > $1.createdTime }
        case .oldestFirst:
            return messages.sorted { $0.createdTime < $1.createdTime }
        case .statusFirst:
            return messages.sorted { message1, message2 in
                if message1.status != message2.status {
                    return message1.status.rawValue < message2.status.rawValue
                }
                return message1.createdTime > message2.createdTime
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with sort options
            HStack {
                Text("\(messages.count) Messages")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }
            
            // Table
            ScrollView {
                LazyVStack(spacing: 1) {
                    // Header row
                    BatchMessageHeaderRow()
                    
                    // Data rows
                    ForEach(sortedMessages, id: \.id) { message in
                        BatchMessageRow(
                            message: message,
                            isSelected: selectedMessage?.id == message.id,
                            onSelect: { selectedMessage = message },
                            onEdit: onEdit != nil ? { onEdit!(message) } : nil,
                            onDelete: { onDelete(message) }
                        )
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
    }
}

struct BatchMessageHeaderRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("Status")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text("Template")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("Recipients")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .center)
            
            Text("Progress")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .center)
            
            Text("Created")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
            
            Text("Actions")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlColor))
    }
}

struct BatchMessageRow: View {
    let message: BatchMessage
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: () -> Void
    
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Status
            StatusBadge(status: message.status)
                .frame(width: 80, alignment: .leading)
            
            // Message template (truncated)
            VStack(alignment: .leading, spacing: 2) {
                Text(truncatedTemplate)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if message.scheduledTime != nil {
                    Text("Scheduled: \(formattedScheduledTime)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Recipients count
            Text("\(message.totalRecipients)")
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 80, alignment: .center)
            
            // Progress
            VStack(spacing: 2) {
                if message.status == .sending || message.status == .completed {
                    Text("\(message.sentCount)/\(message.totalRecipients)")
                        .font(.caption2)
                        .fontWeight(.medium)
                    
                    ProgressView(value: Double(message.sentCount), total: Double(message.totalRecipients))
                        .progressViewStyle(.linear)
                        .frame(width: 60)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 80, alignment: .center)
            
            // Created time
            Text(formattedCreatedTime)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
            
            // Actions
            HStack(spacing: 4) {
                if let onEdit = onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(message.status == .sending)
                }
                
                Button(action: { showingDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .disabled(message.status == .sending)
            }
            .frame(width: 80, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .confirmationDialog(
            "Delete Message",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this message? This action cannot be undone.")
        }
    }
    
    private var truncatedTemplate: String {
        let maxLength = 50
        if message.messageTemplate.count <= maxLength {
            return message.messageTemplate
        } else {
            return String(message.messageTemplate.prefix(maxLength)) + "..."
        }
    }
    
    private var formattedCreatedTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: message.createdTime, relativeTo: Date())
    }
    
    private var formattedScheduledTime: String {
        guard let scheduledTime = message.scheduledTime else { return "" }
        return scheduledTime.formatted(date: .abbreviated, time: .shortened)
    }
}

struct StatusBadge: View {
    let status: BatchMessageStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(status.displayName)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var statusColor: Color {
        switch status {
        case .pending: return .orange
        case .scheduled: return .blue
        case .sending: return .purple
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}
