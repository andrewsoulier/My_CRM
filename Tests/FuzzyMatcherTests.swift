import XCTest
@testable import MyCRM

final class FuzzyMatcherTests: XCTestCase {
    var matcher: FuzzyMatcher!
    var testContacts: [Contact]!
    
    override func setUp() {
        super.setUp()
        matcher = FuzzyMatcher()
        
        testContacts = [
            Contact(phone: "+1-555-123-4567", name: "John Smith", firstName: "John", lastName: "Smith", email: "john.smith@example.com", business: "Acme Corp"),
            Contact(phone: "+1-555-987-6543", name: "Jane Doe", firstName: "Jane", lastName: "Doe", email: "jane.doe@example.com", business: "Tech Inc"),
            Contact(phone: "+1-555-111-2222", name: "Bob Johnson", firstName: "Bob", lastName: "Johnson", email: "bob.johnson@example.com", business: "Startup LLC"),
            Contact(phone: "+1-555-333-4444", name: "Alice Brown", firstName: "Alice", lastName: "Brown", email: "alice.brown@example.com", business: "Consulting Co")
        ]
    }
    
    override func tearDown() {
        matcher = nil
        testContacts = nil
        super.tearDown()
    }
    
    func testExactMatch() {
        let results = matcher.search(query: "John Smith", in: testContacts)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.item.phone, "+1-555-123-4567")
        XCTAssertEqual(results.first?.score, 1.0, accuracy: 0.01)
    }
    
    func testPartialMatch() {
        let results = matcher.search(query: "John", in: testContacts)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.item.phone, "+1-555-123-4567")
        XCTAssertGreaterThan(results.first?.score ?? 0, 0.8)
    }
    
    func testBusinessMatch() {
        let results = matcher.search(query: "Acme", in: testContacts)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.item.phone, "+1-555-123-4567")
        XCTAssertGreaterThan(results.first?.score ?? 0, 0.7)
    }
    
    func testEmailMatch() {
        let results = matcher.search(query: "jane.doe", in: testContacts)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.item.phone, "+1-555-987-6543")
        XCTAssertGreaterThan(results.first?.score ?? 0, 0.5)
    }
    
    func testFuzzyMatch() {
        let results = matcher.search(query: "Jon Smith", in: testContacts) // Typo: Jon instead of John
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.item.phone, "+1-555-123-4567")
        XCTAssertGreaterThan(results.first?.score ?? 0, 0.5)
    }
    
    func testNoMatch() {
        let results = matcher.search(query: "XYZ", in: testContacts)
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testEmptyQuery() {
        let results = matcher.search(query: "", in: testContacts)
        
        XCTAssertEqual(results.count, 0)
    }
    
    func testMultipleMatches() {
        let results = matcher.search(query: "example.com", in: testContacts)
        
        XCTAssertEqual(results.count, 4)
        // All contacts should have the same email domain
        XCTAssertTrue(results.allSatisfy { $0.item.email?.contains("example.com") == true })
    }
    
    func testCaseInsensitive() {
        let results = matcher.search(query: "JOHN SMITH", in: testContacts)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.item.phone, "+1-555-123-4567")
    }
    
    func testLevenshteinDistance() {
        // Test exact distance calculation
        let distance1 = calculateLevenshteinDistance("kitten", "sitting")
        XCTAssertEqual(distance1, 3)
        
        let distance2 = calculateLevenshteinDistance("hello", "world")
        XCTAssertEqual(distance2, 4)
        
        let distance3 = calculateLevenshteinDistance("same", "same")
        XCTAssertEqual(distance3, 0)
    }
    
    // Helper function to test Levenshtein distance directly
    private func calculateLevenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let len1 = s1.count
        let len2 = s2.count
        
        var matrix = Array(repeating: Array(repeating: 0, count: len2 + 1), count: len1 + 1)
        
        for i in 0...len1 {
            matrix[i][0] = i
        }
        for j in 0...len2 {
            matrix[0][j] = j
        }
        
        for i in 1...len1 {
            for j in 1...len2 {
                let cost = s1[s1.index(s1.startIndex, offsetBy: i - 1)] == s2[s2.index(s2.startIndex, offsetBy: j - 1)] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }
        
        return matrix[len1][len2]
    }
}
