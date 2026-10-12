import SwiftUI

struct SchedulePickerModal: View {
    @Binding var selectedDate: Date
    let onSchedule: (Date) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var scheduleOption: ScheduleOption = .specific
    @State private var relativeAmount = 1
    @State private var relativeUnit: RelativeUnit = .hours
    
    enum ScheduleOption: String, CaseIterable {
        case specific = "Specific Date & Time"
        case relative = "Relative Time"
        
        var icon: String {
            switch self {
            case .specific: return "calendar"
            case .relative: return "clock"
            }
        }
    }
    
    enum RelativeUnit: String, CaseIterable {
        case minutes = "minutes"
        case hours = "hours"
        case days = "days"
        case weeks = "weeks"
        
        var timeInterval: TimeInterval {
            switch self {
            case .minutes: return 60
            case .hours: return 3600
            case .days: return 86400
            case .weeks: return 604800
            }
        }
    }
    
    private var calculatedDate: Date {
        switch scheduleOption {
        case .specific:
            return selectedDate
        case .relative:
            return Date().addingTimeInterval(TimeInterval(relativeAmount) * relativeUnit.timeInterval)
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Schedule Message")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
            }
            
            // Schedule option picker
            Picker("Schedule Option", selection: $scheduleOption) {
                ForEach(ScheduleOption.allCases, id: \.self) { option in
                    HStack {
                        Image(systemName: option.icon)
                        Text(option.rawValue)
                    }
                    .tag(option)
                }
            }
            .pickerStyle(.segmented)
            
            // Date/time selection
            Group {
                switch scheduleOption {
                case .specific:
                    specificDatePicker
                case .relative:
                    relativeDatePicker
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Scheduled for:")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(calculatedDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.body)
                            .fontWeight(.medium)
                        
                        Text(relativeTimeDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Schedule") {
                    onSchedule(calculatedDate)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(calculatedDate <= Date())
            }
            
            // Warning for past dates
            if calculatedDate <= Date() {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Cannot schedule messages in the past")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                }
            }
        }
        .padding()
        .frame(width: 400, height: 400)
    }
    
    private var specificDatePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Date & Time")
                .font(.headline)
                .fontWeight(.semibold)
            
            DatePicker(
                "Schedule Date",
                selection: $selectedDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
        }
    }
    
    private var relativeDatePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send In")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 12) {
                // Amount
                VStack(alignment: .leading, spacing: 4) {
                    Text("Amount")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Amount", value: $relativeAmount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                
                // Unit
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Unit", selection: $relativeUnit) {
                        ForEach(RelativeUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue.capitalized)
                                .tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                
                Spacer()
            }
        }
    }
    
    private var relativeTimeDescription: String {
        let now = Date()
        let timeInterval = calculatedDate.timeIntervalSince(now)
        
        if timeInterval < 60 {
            return "In less than a minute"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "In \(minutes) minute\(minutes == 1 ? "" : "s")"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "In \(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            let days = Int(timeInterval / 86400)
            return "In \(days) day\(days == 1 ? "" : "s")"
        }
    }
}
