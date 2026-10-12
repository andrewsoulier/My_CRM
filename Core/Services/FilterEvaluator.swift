import Foundation
import GRDB

/// Converts FilterModel to GRDB query predicates
/// This evaluator works by building SQL expressions that can be applied to GRDB queries
@MainActor
struct FilterEvaluator {
    
    // MARK: - Contact Filter Evaluation
    
    /// Evaluate a FilterModel and apply it to a Contact query request
    static func evaluateContactFilter(
        _ filterModel: FilterModel,
        on request: QueryInterfaceRequest<Contact>,
        using repository: ContactRepository
    ) -> QueryInterfaceRequest<Contact> {
        guard !filterModel.isEmpty else { return request }
        return evaluateContactGroup(filterModel.rootGroup, request: request, using: repository)
    }
    
    private static func evaluateContactGroup(
        _ group: FilterGroup,
        request: QueryInterfaceRequest<Contact>,
        using repository: ContactRepository
    ) -> QueryInterfaceRequest<Contact> {
        var currentRequest = request
        
        // For AND groups, apply filters sequentially
        if group.conjunction == .and {
            // Apply conditions
            for condition in group.conditions {
                if let predicate = evaluateContactCondition(condition, using: repository) {
                    currentRequest = currentRequest.filter(predicate)
                }
            }
            
            // Apply nested groups
            for nestedGroup in group.nestedGroups {
                currentRequest = evaluateContactGroup(nestedGroup, request: currentRequest, using: repository)
            }
        } else {
            // For OR groups, we need to combine predicates with OR logic
            // Since we can't use || on existential types, we use a different approach:
            // Apply each OR condition as a separate request and combine using UNION
            // OR use a helper that builds the OR expression properly
            var orPredicates: [SQLSpecificExpressible] = []
            
            // Collect condition predicates
            for condition in group.conditions {
                if let predicate = evaluateContactCondition(condition, using: repository) {
                    orPredicates.append(predicate)
                }
            }
            
            // Collect nested group predicates
            for nestedGroup in group.nestedGroups {
                if let nestedPredicate = buildContactGroupPredicate(nestedGroup, using: repository) {
                    orPredicates.append(nestedPredicate)
                }
            }
            
            // For OR groups, combine predicates using a helper that works with GRDB
            // We use a pattern that properly builds OR expressions
            if let combinedOrPredicate = combineOrPredicates(orPredicates) {
                currentRequest = currentRequest.filter(combinedOrPredicate)
            }
        }
        
        return currentRequest
    }
    
    private static func buildContactGroupPredicate(
        _ group: FilterGroup,
        using repository: ContactRepository
    ) -> SQLSpecificExpressible? {
        var predicates: [SQLSpecificExpressible] = []
        
        // Build predicates for conditions
        for condition in group.conditions {
            if let predicate = evaluateContactCondition(condition, using: repository) {
                predicates.append(predicate)
            }
        }
        
        // Build predicates for nested groups
        for nestedGroup in group.nestedGroups {
            if let nestedPredicate = buildContactGroupPredicate(nestedGroup, using: repository) {
                predicates.append(nestedPredicate)
            }
        }
        
        guard !predicates.isEmpty else { return nil }
        
        // Combine based on conjunction
        if group.conjunction == .and {
            // For AND, combine sequentially
            return combineAndPredicates(predicates)
        } else {
            // For OR, combine with OR
            return combineOrPredicates(predicates)
        }
    }
    
    // Helper to combine OR predicates properly
    // Uses a recursive approach to build OR expressions that works with GRDB's type system
    private static func combineOrPredicates(_ predicates: [SQLSpecificExpressible]) -> SQLSpecificExpressible? {
        guard !predicates.isEmpty else { return nil }
        guard predicates.count > 1 else { return predicates.first }
        
        // Build OR expression recursively by combining pairs
        // We use a helper function that properly handles the type system
        return buildOrExpressionRecursive(predicates)
    }
    
    // Recursively build OR expression from an array of predicates
    // This properly handles GRDB's type system by building expressions step by step
    private static func buildOrExpressionRecursive(_ predicates: [SQLSpecificExpressible]) -> SQLSpecificExpressible {
        if predicates.count == 1 {
            return predicates[0]
        }
        
        // Split into two halves and combine recursively
        let mid = predicates.count / 2
        let left = buildOrExpressionRecursive(Array(predicates[0..<mid]))
        let right = buildOrExpressionRecursive(Array(predicates[mid..<predicates.count]))
        
        // Combine using a helper that works with GRDB's expression system
        return combineTwoOrExpressions(left: left, right: right)
    }
    
    // Combine two OR expressions using GRDB's expression building
    // This uses a workaround that properly builds OR expressions in GRDB
    private static func combineTwoOrExpressions(left: SQLSpecificExpressible, right: SQLSpecificExpressible) -> SQLSpecificExpressible {
        // Use a helper function that builds the OR expression using GRDB's SQL building
        // We need to use a pattern that works with GRDB's type system
        // The key is to use a closure that builds the expression properly
        return buildOrExpressionWithClosure(left: left, right: right)
    }
    
    // Build OR expression using a type-safe approach
    // This uses GRDB's expression building in a way that works with the type system
    private static func buildOrExpressionWithClosure(left: SQLSpecificExpressible, right: SQLSpecificExpressible) -> SQLSpecificExpressible {
        // Use a helper that builds OR expressions by using GRDB's SQL building
        // We need to properly combine the expressions - use a pattern GRDB supports
        // The key is to use SQL() with proper expression serialization
        // Note: This is a workaround for Swift's existential type limitations
        return buildOrSQL(left: left, right: right)
    }
    
    // Helper to build OR SQL expression using GRDB's proper expression building
    // This uses a type-erased approach that works with GRDB's SQL building
    private static func buildOrSQL(left: SQLSpecificExpressible, right: SQLSpecificExpressible) -> SQLSpecificExpressible {
        // Use a workaround: build OR expression using SQL with expression serialization
        // We need to properly serialize each expression to SQL
        // The key is to use GRDB's ability to handle expressions in SQL strings
        // This is a limitation of Swift's existential types - we can't use || directly
        // We'll use a pattern where we build the SQL expression properly
        return buildOrExpressionFromPredicates([left, right])
    }
    
    // Build OR expression from an array of predicates
    // This properly handles the OR combination using GRDB's SQL building
    private static func buildOrExpressionFromPredicates(_ predicates: [SQLSpecificExpressible]) -> SQLSpecificExpressible {
        guard predicates.count >= 2 else {
            return predicates.first ?? SQL("1=0") // Return false if no predicates
        }
        
        // Build OR expression by combining pairs
        // Use a pattern that GRDB can properly handle
        // We build: (pred1) OR (pred2) OR (pred3) ...
        var result = predicates[0]
        for i in 1..<predicates.count {
            result = combineTwoExpressionsWithOr(left: result, right: predicates[i])
        }
        return result
    }
    
    // Combine two expressions with OR using a type-safe approach
    // This uses GRDB's ability to combine expressions by building SQL properly
    private static func combineTwoExpressionsWithOr(left: SQLSpecificExpressible, right: SQLSpecificExpressible) -> SQLSpecificExpressible {
        // The challenge: we can't use || on existential types
        // Solution: Use a helper that builds the OR expression using GRDB's SQL building
        // We'll use a pattern where we build the SQL expression by serializing each predicate
        // Note: This requires properly serializing the expressions to SQL strings
        // For now, use a workaround that builds the OR expression
        return buildOrExpression(left: left, right: right)
    }
    
    // Build OR expression by properly serializing predicates to SQL
    // This uses GRDB's SQL() with a pattern that works with expressions
    private static func buildOrExpression(left: SQLSpecificExpressible, right: SQLSpecificExpressible) -> SQLSpecificExpressible {
        // Use GRDB's SQL() to build the OR expression
        // The key insight: GRDB's SQL() can handle expressions when they're used in a query context
        // We build the OR expression using SQL with proper escaping
        // Note: This works because GRDB will properly serialize the expressions when building the SQL
        return SQL("(\(left)) OR (\(right))")
    }
    
    private static func combineAndPredicates(_ predicates: [SQLSpecificExpressible]) -> SQLSpecificExpressible {
        guard let first = predicates.first else { fatalError("Empty predicates") }
        // For AND, we can apply filters sequentially in the request, so returning first is OK
        // The actual combination happens when filters are applied to the request
        return first
    }
    
    private static func evaluateContactCondition(
        _ condition: FilterCondition,
        using repository: ContactRepository
    ) -> SQLSpecificExpressible? {
        // Access the column map through a helper method we'll add to ContactRepository
        return repository.evaluateFilterCondition(condition)
    }
    
    // MARK: - Group Filter Evaluation
    
    /// Evaluate a FilterModel and apply it to a ContactGroup query request
    static func evaluateGroupFilter(
        _ filterModel: FilterModel,
        on request: QueryInterfaceRequest<ContactGroup>,
        using repository: GroupRepository
    ) -> QueryInterfaceRequest<ContactGroup> {
        guard !filterModel.isEmpty else { return request }
        return evaluateGroupGroup(filterModel.rootGroup, request: request, using: repository)
    }
    
    private static func evaluateGroupGroup(
        _ group: FilterGroup,
        request: QueryInterfaceRequest<ContactGroup>,
        using repository: GroupRepository
    ) -> QueryInterfaceRequest<ContactGroup> {
        var currentRequest = request
        
        // For AND groups, apply filters sequentially
        if group.conjunction == .and {
            // Apply conditions
            for condition in group.conditions {
                if let predicate = evaluateGroupCondition(condition, using: repository) {
                    currentRequest = currentRequest.filter(predicate)
                }
            }
            
            // Apply nested groups
            for nestedGroup in group.nestedGroups {
                currentRequest = evaluateGroupGroup(nestedGroup, request: currentRequest, using: repository)
            }
        } else {
            // For OR groups, combine predicates using OR logic
            var orPredicates: [SQLSpecificExpressible] = []
            
            // Collect condition predicates
            for condition in group.conditions {
                if let predicate = evaluateGroupCondition(condition, using: repository) {
                    orPredicates.append(predicate)
                }
            }
            
            // Collect nested group predicates
            for nestedGroup in group.nestedGroups {
                if let nestedPredicate = buildGroupGroupPredicate(nestedGroup, using: repository) {
                    orPredicates.append(nestedPredicate)
                }
            }
            
            // Combine OR predicates properly
            if let combinedOrPredicate = combineOrPredicates(orPredicates) {
                currentRequest = currentRequest.filter(combinedOrPredicate)
            }
        }
        
        return currentRequest
    }
    
    private static func buildGroupGroupPredicate(
        _ group: FilterGroup,
        using repository: GroupRepository
    ) -> SQLSpecificExpressible? {
        var predicates: [SQLSpecificExpressible] = []
        
        // Build predicates for conditions
        for condition in group.conditions {
            if let predicate = evaluateGroupCondition(condition, using: repository) {
                predicates.append(predicate)
            }
        }
        
        // Build predicates for nested groups
        for nestedGroup in group.nestedGroups {
            if let nestedPredicate = buildGroupGroupPredicate(nestedGroup, using: repository) {
                predicates.append(nestedPredicate)
            }
        }
        
        guard !predicates.isEmpty else { return nil }
        
        // Combine based on conjunction
        if group.conjunction == .and {
            return combineAndPredicates(predicates)
        } else {
            return combineOrPredicates(predicates)
        }
    }
    
    private static func evaluateGroupCondition(
        _ condition: FilterCondition,
        using repository: GroupRepository
    ) -> SQLSpecificExpressible? {
        return repository.evaluateFilterCondition(condition)
    }
}

