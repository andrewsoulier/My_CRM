import Foundation

struct Deck: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var memberPhones: [String] // ordered list of phone numbers
    var createdAt: Date
    var updatedAt: Date
    var description: String?
    
    // Computed property for drag & drop compatibility
    var members: [String] {
        get { memberPhones }
        set { memberPhones = newValue }
    }
    
    init(id: UUID = UUID(), name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.memberPhones = []
        self.createdAt = Date()
        self.updatedAt = Date()
        self.description = description
    }
    
    // Computed properties
    var memberCount: Int {
        memberPhones.count
    }
    
    var isEmpty: Bool {
        memberPhones.isEmpty
    }
    
    // Methods
    mutating func addMember(_ phone: String) {
        if !memberPhones.contains(phone) {
            memberPhones.append(phone)
            updatedAt = Date()
        }
    }
    
    mutating func removeMember(_ phone: String) {
        memberPhones.removeAll { $0 == phone }
        updatedAt = Date()
    }
    
    mutating func reorderMembers(from source: IndexSet, to destination: Int) {
        memberPhones.move(fromOffsets: source, toOffset: destination)
        updatedAt = Date()
    }
    
    func containsMember(_ phone: String) -> Bool {
        memberPhones.contains(phone)
    }
}
