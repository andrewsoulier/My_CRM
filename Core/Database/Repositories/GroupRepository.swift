import Foundation
import GRDB

/// Repository for ContactGroup database operations using GRDB
@MainActor
class GroupRepository {
    private let dbManager: GRDBDatabaseManager
    private let logger = LogManager.shared
    
    private enum ColumnSemanticType {
        case text
        case number
        case date
    }
    
    private struct ColumnInfo {
        let column: Column
        let semanticType: ColumnSemanticType
        let collate: DatabaseCollation?
    }
    
    /// Mapping between grid column identifiers and database columns.
    /// Keep in sync with `GridViewService.GroupColumns`.
    private static let columnMap: [String: ColumnInfo] = {
        let nocase: DatabaseCollation = .localizedCaseInsensitiveCompare
        return [
            "group.name": ColumnInfo(column: Column("name"), semanticType: .text, collate: nocase),
            "group.color": ColumnInfo(column: Column("color"), semanticType: .text, collate: nocase),
            "group.created_at": ColumnInfo(column: Column("created_at"), semanticType: .date, collate: nil),
            "group.size": ColumnInfo(column: Column("size"), semanticType: .number, collate: nil),
            "group.participants": ColumnInfo(column: Column("member_phones"), semanticType: .text, collate: nocase),
            "group.tags": ColumnInfo(column: Column("tags"), semanticType: .text, collate: nocase),
            "group.children": ColumnInfo(column: Column("child_group_ids"), semanticType: .text, collate: nocase),
            "group.parents": ColumnInfo(column: Column("parent_group_ids"), semanticType: .text, collate: nocase)
        ]
    }()
    
    init(dbManager: GRDBDatabaseManager? = nil) {
        self.dbManager = dbManager ?? GRDBDatabaseManager.shared
    }
    
    // MARK: - Create
    
    /// Insert a new group
    func insert(_ group: ContactGroup) async throws {
        try await dbManager.write { db in
            try group.insert(db)
        }
        logger.info("✅ Inserted group: \(group.name) (\(group.id))")
    }
    
    /// Insert multiple groups in a transaction
    func insertAll(_ groups: [ContactGroup]) async throws {
        try await dbManager.transaction { db in
            for group in groups {
                try group.insert(db)
            }
            return ()
        }
        logger.info("✅ Inserted \(groups.count) groups")
    }
    
    // MARK: - Read
    
    /// Fetch group by ID
    func fetchOne(id: UUID) async throws -> ContactGroup? {
        return try await dbManager.read { db in
            try ContactGroup.fetchOne(db, id: id)
        }
    }
    
    /// Fetch all groups
    func fetchAll() async throws -> [ContactGroup] {
        return try await fetch(limit: Int.max, offset: 0, sorts: [GridSortDescriptor(columnId: "group.name", direction: .ascending)], filters: [:])
    }
    
    func fetch(limit: Int, offset: Int, sorts: [GridSortDescriptor], filters: [String: AnyCodable]) async throws -> [ContactGroup] {
        return try await dbManager.read { [self] db in
            var request = ContactGroup.all()
            request = self.apply(filters: filters, to: request)
            request = self.apply(sorts: sorts, to: request)
            return try request
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }
    
    /// Fetch groups with FilterModel (new filter system)
    func fetch(limit: Int, offset: Int, sorts: [GridSortDescriptor], filterModel: FilterModel) async throws -> [ContactGroup] {
        return try await dbManager.read { [self] db in
            var request = ContactGroup.all()
            request = FilterEvaluator.evaluateGroupFilter(filterModel, on: request, using: self)
            request = self.apply(sorts: sorts, to: request)
            return try request
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }
    
    /// Fetch root groups (no parent)
    func fetchRootGroups() async throws -> [ContactGroup] {
        return try await dbManager.read { db in
            try ContactGroup.fetchRootGroups(db)
        }
    }
    
    /// Fetch child groups
    func fetchChildren(parentID: UUID) async throws -> [ContactGroup] {
        return try await dbManager.read { db in
            try ContactGroup.fetchChildren(db, parentID: parentID)
        }
    }
    
    /// Fetch all decks
    func fetchDecks() async throws -> [ContactGroup] {
        return try await dbManager.read { db in
            try ContactGroup.fetchDecks(db)
        }
    }
    
    /// Fetch groups containing phone number
    func fetchContaining(phone: String) async throws -> [ContactGroup] {
        return try await dbManager.read { db in
            try ContactGroup.fetchContaining(db, phone: phone)
        }
    }
    
    /// Search groups
    func search(query: String) async throws -> [ContactGroup] {
        return try await dbManager.read { db in
            try ContactGroup.search(db, query: query)
        }
    }
    
    /// Count total groups
    func count() async throws -> Int {
        try await count(filters: [:])
    }
    
    func count(filters: [String: AnyCodable]) async throws -> Int {
        return try await dbManager.read { [self] db in
            var request = ContactGroup.all()
            request = self.apply(filters: filters, to: request)
            return try request.fetchCount(db)
        }
    }
    
    /// Count groups with FilterModel (new filter system)
    func count(filterModel: FilterModel) async throws -> Int {
        return try await dbManager.read { [self] db in
            var request = ContactGroup.all()
            request = FilterEvaluator.evaluateGroupFilter(filterModel, on: request, using: self)
            return try request.fetchCount(db)
        }
    }
    
    // MARK: - Update
    
    /// Update an existing group
    func update(_ group: ContactGroup) async throws {
        try await dbManager.write { [self] db in
            try group.update(db)
            try self.syncContactGroups(db: db, phones: group.memberPhones)
        }
        logger.info("✅ Updated group: \(group.name) (\(group.id))")
    }
    
    /// Upsert (insert or update) a group
    func upsert(_ group: ContactGroup) async throws {
        try await dbManager.write { db in
            try group.save(db)
        }
        logger.info("✅ Upserted group: \(group.name) (\(group.id))")
    }
    
    /// Add member to group
    func addMember(groupID: UUID, phone: String) async throws {
        try await dbManager.write { [self] db in
            guard var group = try ContactGroup.fetchOne(db, id: groupID) else {
                throw DatabaseError(message: "Group not found: \(groupID)")
            }
            
            group.memberPhones.insert(phone)
            group.cachedSize = group.memberPhones.count
            try group.update(db)
            
            // Update participants JSON with name
            try self.updateParticipantsWithName(db: db, groupID: groupID, phone: phone, operation: .add)
            
            try self.syncContactGroups(db: db, phone: phone)
        }
        logger.info("✅ Added member \(phone) to group \(groupID)")
    }
    
    /// Remove member from group
    func removeMember(groupID: UUID, phone: String) async throws {
        try await dbManager.write { [self] db in
            guard var group = try ContactGroup.fetchOne(db, id: groupID) else {
                throw DatabaseError(message: "Group not found: \(groupID)")
            }
            
            group.memberPhones.remove(phone)
            group.cachedSize = group.memberPhones.count
            try group.update(db)
            
            // Update participants JSON - remove participant
            try self.updateParticipantsWithName(db: db, groupID: groupID, phone: phone, operation: .remove)
            
            try self.syncContactGroups(db: db, phone: phone)
        }
        logger.info("✅ Removed member \(phone) from group \(groupID)")
    }
    
    /// Replace all tags for a group
    func updateTags(groupID: UUID, tagIDs: [UUID]) async throws {
        try await dbManager.write { db in
            guard var group = try ContactGroup.fetchOne(db, id: groupID) else {
                throw DatabaseError(message: "Group not found: \(groupID)")
            }
            group.tags = Set(tagIDs)
            group.cachedSize = group.memberPhones.count
            try group.update(db)
        }
    }
    
    /// Replace child group relationships
    func updateChildGroups(groupID: UUID, childIDs: [UUID]) async throws {
        try await dbManager.write { db in
            guard var group = try ContactGroup.fetchOne(db, id: groupID) else {
                throw DatabaseError(message: "Group not found: \(groupID)")
            }
            group.childGroupIDs = Set(childIDs)
            group.cachedSize = group.memberPhones.count
            try group.update(db)
        }
    }
    
    /// Replace parent group relationships
    func updateParentGroups(groupID: UUID, parentIDs: [UUID]) async throws {
        try await dbManager.write { db in
            guard var group = try ContactGroup.fetchOne(db, id: groupID) else {
                throw DatabaseError(message: "Group not found: \(groupID)")
            }
            group.parentGroupIDs = Set(parentIDs)
            group.cachedSize = group.memberPhones.count
            try group.update(db)
        }
    }
    
    // MARK: - Delete
    
    /// Delete group by ID
    func delete(id: UUID) async throws {
        let deleted = try await dbManager.write { [self] db in
            guard let group = try ContactGroup.fetchOne(db, id: id) else {
                return 0
            }
            let memberPhones = Array(group.memberPhones)
            let deleted = try ContactGroup
                .filter(Column("id") == id.uuidString)
                .deleteAll(db)
            if deleted > 0 {
                try self.syncContactGroups(db: db, phones: memberPhones)
            }
            return deleted
        }
        
        if deleted > 0 {
            logger.info("✅ Deleted group: \(id)")
        } else {
            logger.warning("⚠️ Group not found for deletion: \(id)")
        }
    }
    
    /// Delete a group
    func delete(_ group: ContactGroup) async throws {
        try await delete(id: group.id)
    }
    
    /// Delete all groups (use with caution!)
    func deleteAll() async throws {
        let deleted = try await dbManager.write { db in
            let count = try ContactGroup.deleteAll(db)
            if count > 0 {
                try db.execute(sql: "UPDATE contacts SET groups = '[]'")
            }
            return count
        }
        logger.warning("⚠️ Deleted all groups (\(deleted) total)")
    }
    
    // MARK: - Observations
    
    /// Observe all groups (reactive)
    func observeAll() -> AsyncThrowingStream<[ContactGroup], Error> {
        let observation = ValueObservation.tracking { db in
            try ContactGroup
                .order(Column("name"))
                .fetchAll(db)
        }
        return dbManager.observe(observation)
    }
    
    /// Observe single group by ID (reactive)
    func observe(id: UUID) -> AsyncThrowingStream<ContactGroup?, Error> {
        let observation = ValueObservation.tracking { db in
            try ContactGroup.fetchOne(db, id: id)
        }
        return dbManager.observe(observation)
    }
    
    /// Observe root groups (reactive)
    func observeRootGroups() -> AsyncThrowingStream<[ContactGroup], Error> {
        let observation = ValueObservation.tracking { db in
            try ContactGroup.fetchRootGroups(db)
        }
        return dbManager.observe(observation)
    }
    
    /// Observe decks (reactive)
    func observeDecks() -> AsyncThrowingStream<[ContactGroup], Error> {
        let observation = ValueObservation.tracking { db in
            try ContactGroup.fetchDecks(db)
        }
        return dbManager.observe(observation)
    }
}

extension GroupRepository {
    /// Evaluate a single filter condition and return a SQL predicate
    func evaluateFilterCondition(_ condition: FilterCondition) -> SQLSpecificExpressible? {
        guard let info = Self.columnMap[condition.field] else { return nil }
        
        let columnExpression: SQLSpecificExpressible
        if let collate = info.collate {
            columnExpression = info.column.collating(collate)
        } else {
            columnExpression = info.column
        }
        
        switch info.semanticType {
        case .text:
            return evaluateTextCondition(condition, columnExpression: columnExpression, column: info.column)
        case .number:
            return evaluateNumberCondition(condition, column: info.column)
        case .date:
            return evaluateDateCondition(condition, column: info.column)
        }
    }
    
    private func evaluateTextCondition(
        _ condition: FilterCondition,
        columnExpression: SQLSpecificExpressible,
        column: Column
    ) -> SQLSpecificExpressible? {
        switch condition.`operator` {
        case .contains:
            guard let value = condition.value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return columnExpression.like("%\(value)%")
            
        case .equals:
            guard let value = condition.value else { return nil }
            return column == value
            
        case .startsWith:
            guard let value = condition.value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return columnExpression.like("\(value)%")
            
        case .endsWith:
            guard let value = condition.value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return columnExpression.like("%\(value)")
            
        case .isEmpty:
            return (column == nil) || (column == "")
            
        case .isNotEmpty:
            return (column != nil) && (column != "")
            
        default:
            return nil
        }
    }
    
    private func evaluateNumberCondition(
        _ condition: FilterCondition,
        column: Column
    ) -> SQLSpecificExpressible? {
        guard let valueString = condition.value,
              let value = Double(valueString) else {
            return nil
        }
        
        switch condition.`operator` {
        case .equals:
            return column == value
            
        case .greaterThan:
            return column > value
            
        case .lessThan:
            return column < value
            
        case .between:
            guard let secondValueString = condition.secondValue,
                  let secondValue = Double(secondValueString) else {
                return nil
            }
            let minValue = min(value, secondValue)
            let maxValue = max(value, secondValue)
            return column >= minValue && column <= maxValue
            
        default:
            return nil
        }
    }
    
    private func evaluateDateCondition(
        _ condition: FilterCondition,
        column: Column
    ) -> SQLSpecificExpressible? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Determine if we should use relative or absolute date
        let useRelative = condition.dateValueType == .relative || condition.`operator`.isRelativeDate
        
        // Get the date to use
        let date: Date?
        if useRelative {
            // Use relative date calculation
            date = RelativeDateCalculator.calculateDate(
                operator: condition.`operator`,
                relativeValue: condition.relativeDateValue
            )
        } else {
            // Use absolute date from value
            if let valueString = condition.value {
                date = isoFormatter.date(from: valueString)
            } else {
                date = nil
            }
        }
        
        guard let date = date else { return nil }
        let dateString = isoFormatter.string(from: date)
        
        switch condition.`operator` {
        case .`is`:
            return column == dateString
            
        case .before:
            return column < dateString
            
        case .after:
            return column > dateString
            
        case .onOrBefore:
            return column <= dateString
            
        case .onOrAfter:
            return column >= dateString
            
        case .lastNDaysAgo, .lastWeek, .lastMonth, .lastYear:
            // For relative dates, we typically want "on or after" the calculated date
            return column >= dateString
            
        default:
            return nil
        }
    }
}

private extension GroupRepository {
    enum ParticipantOperation {
        case add
        case remove
    }
    
    func updateParticipantsWithName(db: Database, groupID: UUID, phone: String, operation: ParticipantOperation) throws {
        // Get current participants JSON
        let row = try? Row.fetchOne(db, sql: "SELECT participants FROM groups WHERE id = ?", arguments: [groupID.uuidString])
        
        var participants: [[String: Any]] = []
        if let participantsJson: String = row?["participants"], !participantsJson.isEmpty,
           let data = participantsJson.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            participants = parsed
        }
        
        switch operation {
        case .add:
            // Check if participant already exists
            let exists = participants.contains { ($0["id"] as? String) == phone }
            if !exists {
                // Get contact name and UUID
                let contactRow = try? Row.fetchOne(db, sql: "SELECT name FROM contacts WHERE phone = ?", arguments: [phone])
                let contactName = contactRow?["name"] as? String ?? ""
                
                // Try to get contact UUID from Contact model if available
                // For now, we'll use an empty string and let the system populate it later if needed
                let participant: [String: Any] = [
                    "id": phone,
                    "name": contactName,
                    "UUID": "" // Will be populated by other systems that have access to Contact model
                ]
                participants.append(participant)
            } else {
                // Update existing participant's name if it's empty or changed
                if let index = participants.firstIndex(where: { ($0["id"] as? String) == phone }) {
                    let contactRow = try? Row.fetchOne(db, sql: "SELECT name FROM contacts WHERE phone = ?", arguments: [phone])
                    let contactName = contactRow?["name"] as? String ?? ""
                    if contactName.isEmpty == false {
                        participants[index]["name"] = contactName
                    }
                }
            }
        case .remove:
            participants.removeAll { ($0["id"] as? String) == phone }
        }
        
        // Update participants JSON in database
        if let participantsData = try? JSONSerialization.data(withJSONObject: participants),
           let participantsString = String(data: participantsData, encoding: .utf8) {
            try db.execute(
                sql: "UPDATE groups SET participants = ? WHERE id = ?",
                arguments: [participantsString, groupID.uuidString]
            )
        }
    }
    
    func syncContactGroups<S: Sequence>(db: Database, phones: S) throws where S.Element == String {
        let uniquePhones = Set(phones.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        for phone in uniquePhones {
            try syncContactGroups(db: db, phone: phone)
        }
    }
    
    func syncContactGroups(db: Database, phone: String) throws {
        let groups = try ContactGroup.fetchContaining(db, phone: phone)
        let names = groups.map { $0.name }.sorted()
        let serialized: String
        if let data = try? JSONEncoder().encode(names),
           let string = String(data: data, encoding: .utf8) {
            serialized = string
        } else {
            serialized = "[]"
        }
        try db.execute(
            sql: "UPDATE contacts SET groups = ? WHERE phone = ?",
            arguments: [serialized, phone]
        )
    }
    
    func apply(filters: [String: AnyCodable], to request: QueryInterfaceRequest<ContactGroup>) -> QueryInterfaceRequest<ContactGroup> {
        var request = request
        for (columnId, value) in filters {
            guard let info = Self.columnMap[columnId] else { continue }
            let expression: SQLSpecificExpressible = {
                if let collate = info.collate {
                    return info.column.collating(collate)
                }
                return info.column
            }()
            switch info.semanticType {
            case .text:
                if let stringValue = value.value as? String, !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    request = request.filter(expression.like("%\(stringValue)%"))
                } else if let arrayValue = value.value as? [String] {
                    let expressions = arrayValue
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .map { expression.like("%\($0)%") }
                    if let first = expressions.first {
                        let combined = expressions.dropFirst().reduce(first) { partial, next in
                            partial || next
                        }
                        request = request.filter(combined)
                    }
                }
            case .number:
                if let number = value.value as? NSNumber {
                    request = request.filter(info.column == number)
                } else if let stringValue = value.value as? String, let doubleValue = Double(stringValue) {
                    request = request.filter(info.column == doubleValue)
                }
            case .date:
                if let stringValue = value.value as? String, !stringValue.isEmpty {
                    request = request.filter(info.column.like("%\(stringValue)%"))
                }
            }
        }
        return request
    }
    
    func apply(sorts: [GridSortDescriptor], to request: QueryInterfaceRequest<ContactGroup>) -> QueryInterfaceRequest<ContactGroup> {
        var orderingTerms: [SQLOrderingTerm] = []
        for descriptor in sorts {
            guard let info = Self.columnMap[descriptor.columnId] else { continue }
            let expression: SQLSpecificExpressible = info.collate.map { info.column.collating($0) } ?? info.column
            switch descriptor.direction {
            case .ascending:
                orderingTerms.append(expression.asc)
            case .descending:
                orderingTerms.append(expression.desc)
            }
        }
        if orderingTerms.isEmpty {
            orderingTerms = [Column("name").collating(.localizedCaseInsensitiveCompare).asc]
        }
        return request.order(orderingTerms)
    }
}

