import Foundation

/// Utility for calculating absolute dates from relative date expressions
@MainActor
struct RelativeDateCalculator {
    
    /// Calculate an absolute date from a relative date operator and optional value
    static func calculateDate(
        operator: FilterOperator,
        relativeValue: RelativeDateValue? = nil
    ) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        
        switch `operator` {
        case .lastWeek:
            return calendar.date(byAdding: .weekOfYear, value: -1, to: now)
            
        case .lastMonth:
            return calendar.date(byAdding: .month, value: -1, to: now)
            
        case .lastYear:
            return calendar.date(byAdding: .year, value: -1, to: now)
            
        case .lastNDaysAgo:
            guard let relativeValue = relativeValue,
                  let amount = relativeValue.amount,
                  let unit = relativeValue.unit else {
                return nil
            }
            
            let component: Calendar.Component
            switch unit {
            case .hours:
                component = .hour
            case .days:
                component = .day
            case .weeks:
                component = .weekOfYear
            case .months:
                component = .month
            case .years:
                component = .year
            }
            
            return calendar.date(byAdding: component, value: -amount, to: now)
            
        default:
            return nil
        }
    }
    
    /// Calculate start and end dates for a relative date range
    /// Returns (startDate, endDate) where startDate is the calculated relative date and endDate is now
    static func calculateDateRange(
        operator: FilterOperator,
        relativeValue: RelativeDateValue? = nil
    ) -> (start: Date, end: Date)? {
        guard let startDate = calculateDate(operator: `operator`, relativeValue: relativeValue) else {
            return nil
        }
        
        return (start: startDate, end: Date())
    }
    
    /// Parse a relative date string like "7 days ago" into a RelativeDateValue
    static func parseRelativeDateString(_ string: String) -> RelativeDateValue? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Handle "last week", "last month", "last year"
        if trimmed == "last week" {
            return RelativeDateValue(amount: 1, unit: .weeks)
        } else if trimmed == "last month" {
            return RelativeDateValue(amount: 1, unit: .months)
        } else if trimmed == "last year" {
            return RelativeDateValue(amount: 1, unit: .years)
        }
        
        // Handle "N [unit] ago" pattern
        let patterns = [
            (regex: #"(\d+)\s*(hour|hours)\s*ago"#, unit: RelativeDateValue.RelativeDateUnit.hours),
            (regex: #"(\d+)\s*(day|days)\s*ago"#, unit: RelativeDateValue.RelativeDateUnit.days),
            (regex: #"(\d+)\s*(week|weeks)\s*ago"#, unit: RelativeDateValue.RelativeDateUnit.weeks),
            (regex: #"(\d+)\s*(month|months)\s*ago"#, unit: RelativeDateValue.RelativeDateUnit.months),
            (regex: #"(\d+)\s*(year|years)\s*ago"#, unit: RelativeDateValue.RelativeDateUnit.years)
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern.regex, options: .caseInsensitive),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let amountRange = Range(match.range(at: 1), in: trimmed),
               let amount = Int(trimmed[amountRange]) {
                return RelativeDateValue(amount: amount, unit: pattern.unit)
            }
        }
        
        return nil
    }
}

