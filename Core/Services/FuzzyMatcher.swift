import Foundation

struct FuzzyMatcher {
    private let maxEditDistance: Int
    private let fieldWeights: [String: Double]
    
    init(maxEditDistance: Int = 2, fieldWeights: [String: Double] = [:]) {
        self.maxEditDistance = maxEditDistance
        self.fieldWeights = fieldWeights.isEmpty ? [
            "name": 1.0,
            "business": 0.8,
            "email": 0.6,
            "phone": 0.4
        ] : fieldWeights
    }
    
    // MARK: - Main Search Function
    func search<T: Searchable>(query: String, in items: [T]) -> [SearchResult<T>] {
        guard !query.isEmpty else { return [] }
        guard !items.isEmpty else { return [] }
        
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        var results: [SearchResult<T>] = []
        
        for item in items {
            let score = calculateScore(query: normalizedQuery, for: item)
            if score > 0 {
                results.append(SearchResult(item: item, score: score))
            }
        }
        
        // Sort by score (highest first)
        results.sort { $0.score > $1.score }
        
        return results
    }
    
    // MARK: - Score Calculation
    private func calculateScore<T: Searchable>(query: String, for item: T) -> Double {
        var totalScore = 0.0
        var maxPossibleScore = 0.0
        
        for (field, weight) in fieldWeights {
            if let value = item.searchableValue(for: field) {
                do {
                    let fieldScore = try calculateFieldScore(query: query, value: value)
                    totalScore += fieldScore * weight
                    maxPossibleScore += weight
                } catch {
                    print("⚠️ Error calculating field score for \(field): \(error.localizedDescription)")
                    continue
                }
            }
        }
        
        return maxPossibleScore > 0 ? totalScore / maxPossibleScore : 0.0
    }
    
    private func calculateFieldScore(query: String, value: String) throws -> Double {
        guard !query.isEmpty else { return 0.0 }
        guard !value.isEmpty else { return 0.0 }
        
        let normalizedValue = value.lowercased()
        
        // Exact match gets highest score
        if normalizedValue == query {
            return 1.0
        }
        
        // Contains match gets high score
        if normalizedValue.contains(query) {
            return 0.9
        }
        
        // Starts with match gets good score
        if normalizedValue.hasPrefix(query) {
            return 0.8
        }
        
        // Fuzzy match using Levenshtein distance
        let distance = levenshteinDistance(query, normalizedValue)
        if distance <= maxEditDistance {
            let similarity = 1.0 - (Double(distance) / Double(max(query.count, normalizedValue.count)))
            return similarity * 0.7 // Cap fuzzy matches at 70%
        }
        
        return 0.0
    }
    
    // MARK: - Levenshtein Distance Algorithm
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let len1 = s1.count
        let len2 = s2.count
        
        var matrix = Array(repeating: Array(repeating: 0, count: len2 + 1), count: len1 + 1)
        
        // Initialize first row and column
        for i in 0...len1 {
            matrix[i][0] = i
        }
        for j in 0...len2 {
            matrix[0][j] = j
        }
        
        // Fill the matrix
        for i in 1...len1 {
            for j in 1...len2 {
                let cost = s1[s1.index(s1.startIndex, offsetBy: i - 1)] == s2[s2.index(s2.startIndex, offsetBy: j - 1)] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }
        
        return matrix[len1][len2]
    }
    
    // MARK: - Utility Functions
    func highlightMatches<T: Searchable>(query: String, in item: T) -> [String: [Range<String.Index>]] {
        let normalizedQuery = query.lowercased()
        var highlights: [String: [Range<String.Index>]] = [:]
        
        for field in fieldWeights.keys {
            if let value = item.searchableValue(for: field) {
                let ranges = findMatches(query: normalizedQuery, in: value.lowercased())
                if !ranges.isEmpty {
                    highlights[field] = ranges
                }
            }
        }
        
        return highlights
    }
    
    private func findMatches(query: String, in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex
        
        while let range = text.range(of: query, options: .caseInsensitive, range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<text.endIndex
        }
        
        return ranges
    }
}

// MARK: - Searchable Protocol
protocol Searchable {
    func searchableValue(for field: String) -> String?
}

// MARK: - SearchResult
struct SearchResult<T> {
    let item: T
    let score: Double
}

// MARK: - Contact Extension
extension Contact: Searchable {
    func searchableValue(for field: String) -> String? {
        switch field {
        case "name":
            return displayName
        case "business":
            return business
        case "email":
            return email
        case "phone":
            return phone
        default:
            return nil
        }
    }
}

// MARK: - Group Extension
extension ContactGroup: Searchable {
    func searchableValue(for field: String) -> String? {
        switch field {
        case "name":
            return name
        default:
            return nil
        }
    }
}

// MARK: - Deck Extension
extension Deck: Searchable {
    func searchableValue(for field: String) -> String? {
        switch field {
        case "name":
            return name
        case "description":
            return description
        default:
            return nil
        }
    }
}
