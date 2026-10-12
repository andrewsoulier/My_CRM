import Foundation

// MARK: - Filter Operator

enum FilterOperator: String, Codable, CaseIterable {
    // Text operators
    case contains
    case equals
    case startsWith
    case endsWith
    case isEmpty
    case isNotEmpty
    
    // Number operators
    case greaterThan
    case lessThan
    case between
    
    // Date operators
    case `is`
    case before
    case after
    case onOrBefore
    case onOrAfter
    case lastNDaysAgo
    case lastWeek
    case lastMonth
    case lastYear
    
    // Record linking operators
    case containsAnyOf
    case containsNoneOf
    
    var displayName: String {
        switch self {
        case .contains: return "contains"
        case .equals: return "equals"
        case .startsWith: return "starts with"
        case .endsWith: return "ends with"
        case .isEmpty: return "is empty"
        case .isNotEmpty: return "is not empty"
        case .greaterThan: return "greater than"
        case .lessThan: return "less than"
        case .between: return "between"
        case .`is`: return "is"
        case .before: return "before"
        case .after: return "after"
        case .onOrBefore: return "on or before"
        case .onOrAfter: return "on or after"
        case .lastNDaysAgo: return "last N [unit] ago"
        case .lastWeek: return "last week"
        case .lastMonth: return "last month"
        case .lastYear: return "last year"
        case .containsAnyOf: return "contains any of"
        case .containsNoneOf: return "contains none of"
        }
    }
    
    var requiresValue: Bool {
        switch self {
        case .isEmpty, .isNotEmpty:
            return false
        case .containsAnyOf, .containsNoneOf:
            return true // These require selectedValues, not value
        default:
            return true
        }
    }
    
    var requiresMultiSelect: Bool {
        switch self {
        case .containsAnyOf, .containsNoneOf:
            return true
        default:
            return false
        }
    }
    
    var requiresSecondValue: Bool {
        return self == .between
    }
    
    var isRelativeDate: Bool {
        switch self {
        case .lastNDaysAgo, .lastWeek, .lastMonth, .lastYear:
            return true
        default:
            return false
        }
    }
}

// MARK: - Filter Condition

enum DateValueType: String, Codable, CaseIterable {
    case absolute
    case relative
    
    var displayName: String {
        switch self {
        case .absolute: return "Absolute"
        case .relative: return "Relative"
        }
    }
}

struct FilterCondition: Codable, Identifiable, Equatable {
    var id: UUID
    var field: String
    var `operator`: FilterOperator
    var value: String?
    var secondValue: String? // For "between" operator
    var relativeDateValue: RelativeDateValue? // For relative date operators
    var dateValueType: DateValueType? // For date fields: absolute or relative
    var selectedValues: [String]? // For "contains any of" and "contains none of" operators
    
    init(
        id: UUID = UUID(),
        field: String,
        operator op: FilterOperator,
        value: String? = nil,
        secondValue: String? = nil,
        relativeDateValue: RelativeDateValue? = nil,
        dateValueType: DateValueType? = nil,
        selectedValues: [String]? = nil
    ) {
        self.id = id
        self.field = field
        self.`operator` = op
        self.value = value
        self.secondValue = secondValue
        self.relativeDateValue = relativeDateValue
        self.dateValueType = dateValueType
        self.selectedValues = selectedValues
    }
}

// MARK: - Relative Date Value

struct RelativeDateValue: Codable, Equatable {
    var amount: Int? // For "last N [unit] ago"
    var unit: RelativeDateUnit? // hours, days, weeks, months, years
    
    enum RelativeDateUnit: String, Codable, CaseIterable {
        case hours
        case days
        case weeks
        case months
        case years
        
        var displayName: String {
            return rawValue.capitalized
        }
    }
    
    init(amount: Int? = nil, unit: RelativeDateUnit? = nil) {
        self.amount = amount
        self.unit = unit
    }
}

// MARK: - Filter Group Conjunction

enum FilterConjunction: String, Codable, CaseIterable {
    case and
    case or
    
    var displayName: String {
        switch self {
        case .and: return "AND"
        case .or: return "OR"
        }
    }
}

// MARK: - Filter Group

struct FilterGroup: Codable, Identifiable, Equatable {
    var id: UUID
    var conjunction: FilterConjunction
    var conditions: [FilterCondition]
    var nestedGroups: [FilterGroup]
    
    init(
        id: UUID = UUID(),
        conjunction: FilterConjunction = .and,
        conditions: [FilterCondition] = [],
        nestedGroups: [FilterGroup] = []
    ) {
        self.id = id
        self.conjunction = conjunction
        self.conditions = conditions
        self.nestedGroups = nestedGroups
    }
    
    var isEmpty: Bool {
        return conditions.isEmpty && nestedGroups.isEmpty
    }
}

// MARK: - Filter Model

struct FilterModel: Codable, Equatable {
    var rootGroup: FilterGroup
    var entityType: GridEntityType
    
    init(rootGroup: FilterGroup = FilterGroup(), entityType: GridEntityType) {
        self.rootGroup = rootGroup
        self.entityType = entityType
    }
    
    var isEmpty: Bool {
        return rootGroup.isEmpty
    }
}

// MARK: - Migration Helpers

extension FilterModel {
    /// Migrate from old dictionary-based filter format to new FilterModel
    static func fromLegacyDictionary(_ dict: [String: AnyCodable], entityType: GridEntityType) -> FilterModel {
        guard !dict.isEmpty else {
            return FilterModel(entityType: entityType)
        }
        
        var conditions: [FilterCondition] = []
        
        for (columnId, value) in dict {
            let filterOperator: FilterOperator
            var filterValue: String?
            
            if let stringValue = value.value as? String, !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                filterOperator = .contains
                filterValue = stringValue
            } else if let arrayValue = value.value as? [String], !arrayValue.isEmpty {
                // For array values, create OR conditions for each value
                // This is a simplified migration - in practice, we'd want to preserve the original intent
                filterOperator = .contains
                filterValue = arrayValue.first
            } else {
                continue
            }
            
            conditions.append(FilterCondition(
                field: columnId,
                operator: filterOperator,
                value: filterValue
            ))
        }
        
        let rootGroup = FilterGroup(
            conjunction: .and,
            conditions: conditions,
            nestedGroups: []
        )
        
        return FilterModel(rootGroup: rootGroup, entityType: entityType)
    }
    
    /// Convert to legacy dictionary format for backward compatibility
    func toLegacyDictionary() -> [String: AnyCodable] {
        var result: [String: AnyCodable] = [:]
        
        func processGroup(_ group: FilterGroup) {
            for condition in group.conditions {
                if let value = condition.value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result[condition.field] = AnyCodable(value)
                }
            }
            
            for nestedGroup in group.nestedGroups {
                processGroup(nestedGroup)
            }
        }
        
        processGroup(rootGroup)
        return result
    }
}

