import Foundation
import GRDB

/// Repository for Contact database operations using GRDB
@MainActor
class ContactRepository {
    private let dbManager: GRDBDatabaseManager
    private let logger = LogManager.shared
    
    private enum ColumnSemanticType {
        case text
        case number
        case date
        case smartchip
    }
    
    private struct ColumnInfo {
        let column: Column
        let semanticType: ColumnSemanticType
        let collate: DatabaseCollation?
    }
    
    /// Mapping between grid column identifiers and database columns.
    /// Keep in sync with `GridViewService.ContactColumns`.
    private static let columnMap: [String: ColumnInfo] = {
        let nocase: DatabaseCollation = .localizedCaseInsensitiveCompare
        return [
            "contact.name": ColumnInfo(column: Contact.Columns.name, semanticType: .text, collate: nocase),
            "contact.first_name": ColumnInfo(column: Contact.Columns.firstName, semanticType: .text, collate: nocase),
            "contact.last_name": ColumnInfo(column: Contact.Columns.lastName, semanticType: .text, collate: nocase),
            "contact.nickname": ColumnInfo(column: Contact.Columns.nickname, semanticType: .text, collate: nocase),
            "contact.phone": ColumnInfo(column: Contact.Columns.phone, semanticType: .text, collate: nocase),
            "contact.email": ColumnInfo(column: Contact.Columns.email, semanticType: .text, collate: nocase),
            "contact.address": ColumnInfo(column: Contact.Columns.address, semanticType: .text, collate: nocase),
            "contact.notes": ColumnInfo(column: Contact.Columns.notes, semanticType: .text, collate: nocase),
            "contact.creation_date": ColumnInfo(column: Contact.Columns.creationDate, semanticType: .date, collate: nil),
            "contact.birthday": ColumnInfo(column: Contact.Columns.birthday, semanticType: .date, collate: nil),
            "contact.total_messages": ColumnInfo(column: Contact.Columns.totalMessages, semanticType: .number, collate: nil),
            "contact.messages_sent": ColumnInfo(column: Contact.Columns.messagesSent, semanticType: .number, collate: nil),
            "contact.messages_received": ColumnInfo(column: Contact.Columns.messagesReceived, semanticType: .number, collate: nil),
            "contact.last_message_received": ColumnInfo(column: Contact.Columns.lastMessageReceivedDate, semanticType: .date, collate: nil),
            "contact.last_message_sent": ColumnInfo(column: Contact.Columns.lastMessageSentDate, semanticType: .date, collate: nil),
            "contact.profile_photo": ColumnInfo(column: Contact.Columns.profilePhoto, semanticType: .text, collate: nil),
            // Smart chip columns use their backing JSON/text columns for coarse sorting/filtering
            "contact.groups": ColumnInfo(column: Column("groups"), semanticType: .smartchip, collate: nocase),
            "contact.tags": ColumnInfo(column: Contact.Columns.tagIDs, semanticType: .smartchip, collate: nocase),
            "contact.relationships": ColumnInfo(column: Contact.Columns.relationshipIDs, semanticType: .smartchip, collate: nocase)
        ]
    }()
    
    init(dbManager: GRDBDatabaseManager? = nil) {
        self.dbManager = dbManager ?? GRDBDatabaseManager.shared
    }
    
    // MARK: - Create
    
    /// Insert a new contact
    func insert(_ contact: Contact) async throws {
        try await dbManager.write { db in
            try contact.insert(db)
        }
        logger.info("✅ Inserted contact: \(contact.name) (\(contact.phone))")
    }
    
    /// Insert multiple contacts in a transaction
    func insertAll(_ contacts: [Contact]) async throws {
        try await dbManager.transaction { db in
            for contact in contacts {
                try contact.insert(db)
            }
            return ()
        }
        logger.info("✅ Inserted \(contacts.count) contacts")
    }
    
    // MARK: - Read
    
    /// Fetch contact by phone number
    func fetchOne(phone: String) async throws -> Contact? {
        return try await dbManager.read { db in
            try Contact.fetchOne(db, phone: phone)
        }
    }
    
    /// Fetch contact by database row ID
    func fetchOne(databaseId: Int64) async throws -> Contact? {
        return try await dbManager.read { db in
            try Contact
                .filter(Column("id") == databaseId)
                .fetchOne(db)
        }
    }
    
    /// Fetch all contacts
    func fetchAll() async throws -> [Contact] {
        return try await dbManager.read { db in
            try Contact
                .order(Column("name"))
                .fetchAll(db)
        }
    }
    
    /// Fetch contacts with pagination
    func fetch(limit: Int, offset: Int) async throws -> [Contact] {
        try await fetch(limit: limit, offset: offset, sorts: [], filters: [:])
    }
    
    /// Fetch contacts with advanced sorting and filtering for the grid view
    func fetch(limit: Int, offset: Int, sorts: [GridSortDescriptor], filters: [String: AnyCodable]) async throws -> [Contact] {
        return try await dbManager.read { [self] db in
            var request = Contact.all()
            request = self.apply(filters: filters, to: request)
            request = self.apply(sorts: sorts, to: request)
            return try request
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }
    
    /// Fetch contacts with FilterModel (new filter system)
    func fetch(limit: Int, offset: Int, sorts: [GridSortDescriptor], filterModel: FilterModel) async throws -> [Contact] {
        return try await dbManager.read { [self] db in
            var request = Contact.all()
            request = FilterEvaluator.evaluateContactFilter(filterModel, on: request, using: self)
            request = self.apply(sorts: sorts, to: request)
            return try request
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }
    
    /// Fetch contacts by business
    func fetchAll(business: String) async throws -> [Contact] {
        return try await dbManager.read { db in
            try Contact.fetchAll(db, business: business)
        }
    }
    
    /// Fetch recent contacts
    func fetchRecent(limit: Int = 50) async throws -> [Contact] {
        return try await dbManager.read { db in
            try Contact.fetchRecent(db, limit: limit)
        }
    }
    
    /// Search contacts
    func search(query: String) async throws -> [Contact] {
        return try await dbManager.read { db in
            try Contact.search(db, query: query)
        }
    }
    
    /// Count total contacts
    func count() async throws -> Int {
        try await count(filters: [:])
    }
    
    func count(filters: [String: AnyCodable]) async throws -> Int {
        return try await dbManager.read { [self] db in
            var request = Contact.all()
            request = self.apply(filters: filters, to: request)
            return try request.fetchCount(db)
        }
    }
    
    /// Count contacts with FilterModel (new filter system)
    func count(filterModel: FilterModel) async throws -> Int {
        return try await dbManager.read { [self] db in
            var request = Contact.all()
            request = FilterEvaluator.evaluateContactFilter(filterModel, on: request, using: self)
            return try request.fetchCount(db)
        }
    }
    
    // MARK: - Update
    
    /// Update an existing contact
    func update(_ contact: Contact) async throws {
        try await dbManager.write { db in
            try contact.update(db)
        }
        logger.info("✅ Updated contact: \(contact.name) (\(contact.phone))")
    }
    
    /// Upsert (insert or update) a contact
    func upsert(_ contact: Contact) async throws {
        try await dbManager.write { db in
            try contact.save(db)
        }
        logger.info("✅ Upserted contact: \(contact.name) (\(contact.phone))")
    }
    
    /// Update multiple contacts in a transaction
    func updateAll(_ contacts: [Contact]) async throws {
        try await dbManager.transaction { db in
            for contact in contacts {
                try contact.update(db)
            }
            return ()
        }
        logger.info("✅ Updated \(contacts.count) contacts")
    }
    
    // MARK: - Delete
    
    /// Delete contact by phone
    func delete(phone: String) async throws {
        let deleted = try await dbManager.write { db in
            try Contact
                .filter(Column("phone") == phone)
                .deleteAll(db)
        }
        
        if deleted > 0 {
            logger.info("✅ Deleted contact: \(phone)")
        } else {
            logger.warning("⚠️ Contact not found for deletion: \(phone)")
        }
    }
    
    /// Delete a contact
    func delete(_ contact: Contact) async throws {
        try await delete(phone: contact.phone)
    }
    
    /// Delete all contacts (use with caution!)
    func deleteAll() async throws {
        let deleted = try await dbManager.write { db in
            try Contact.deleteAll(db)
        }
        logger.warning("⚠️ Deleted all contacts (\(deleted) total)")
    }
    
    // MARK: - Batch Operations
    
    /// Update message statistics and timestamps for a contact
    func recordMessageEvent(phone: String, timestamp: Date, isSentByPrimaryUser: Bool) async throws {
        try await dbManager.write { db in
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoString = isoFormatter.string(from: timestamp)
            let columnsToUpdate: [String]
            if isSentByPrimaryUser {
                columnsToUpdate = [
                    "total_messages = total_messages + 1",
                    "messages_sent = messages_sent + 1",
                    "last_message_sent_date = ?",
                    "sent_last_message = 1"
                ]
            } else {
                columnsToUpdate = [
                    "total_messages = total_messages + 1",
                    "messages_received = messages_received + 1",
                    "last_message_received_date = ?",
                    "sent_last_message = 0"
                ]
            }
            let sql = "UPDATE contacts SET \(columnsToUpdate.joined(separator: ", ")), last_message_date = CASE WHEN last_message_date IS NULL OR last_message_date < ? THEN ? ELSE last_message_date END WHERE phone = ?"
            try db.execute(sql: sql, arguments: [isoString, isoString, isoString, phone])
        }
    }
    
    /// Forcefully update sent/received timestamps without touching counts
    func updateMessageTimestamps(phone: String, sent: Date?, received: Date?) async throws {
        try await dbManager.write { db in
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let sentString = sent.map { isoFormatter.string(from: $0) }
            let receivedString = received.map { isoFormatter.string(from: $0) }
            try db.execute(
                sql: "UPDATE contacts SET last_message_sent_date = COALESCE(?, last_message_sent_date), last_message_received_date = COALESCE(?, last_message_received_date) WHERE phone = ?",
                arguments: [sentString, receivedString, phone]
            )
        }
    }
    
    /// Update nickname value
    func updateNickname(phone: String, nickname: String?) async throws {
        try await dbManager.write { db in
            try db.execute(
                sql: "UPDATE contacts SET nickname = ? WHERE phone = ?",
                arguments: [nickname, phone]
            )
        }
    }
    
    /// Replace tag IDs for a contact
    func updateTagIDs(phone: String, tagIDs: [UUID]) async throws {
        let encoded = try JSONEncoder().encode(tagIDs.map { $0.uuidString })
        let serialized = String(data: encoded, encoding: .utf8)
        try await dbManager.write { db in
            try db.execute(
                sql: "UPDATE contacts SET tag_ids = ? WHERE phone = ?",
                arguments: [serialized, phone]
            )
        }
    }
    
    /// Replace relationship IDs for a contact
    func updateRelationshipIDs(phone: String, relationshipIDs: [UUID]) async throws {
        let encoded = try JSONEncoder().encode(relationshipIDs.map { $0.uuidString })
        let serialized = String(data: encoded, encoding: .utf8)
        try await dbManager.write { db in
            try db.execute(
                sql: "UPDATE contacts SET relationship_ids = ? WHERE phone = ?",
                arguments: [serialized, phone]
            )
        }
    }
    
    /// Replace the serialized groups column for a contact using sorted group names.
    func updateGroups(phone: String, groupNames: [String]) async throws {
        let sortedNames = groupNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        let serialized: String = {
            guard let data = try? JSONEncoder().encode(sortedNames),
                  let string = String(data: data, encoding: .utf8) else {
                return "[]"
            }
            return string
        }()
        
        try await dbManager.write { db in
            try db.execute(
                sql: "UPDATE contacts SET groups = ? WHERE phone = ?",
                arguments: [serialized, phone]
            )
        }
    }
    
    // MARK: - Observations
    
    /// Observe all contacts (reactive)
    func observeAll() -> AsyncThrowingStream<[Contact], Error> {
        let observation = ValueObservation.tracking { db in
            try Contact
                .order(Column("name"))
                .fetchAll(db)
        }
        return dbManager.observe(observation)
    }
    
    /// Observe single contact by phone (reactive)
    func observe(phone: String) -> AsyncThrowingStream<Contact?, Error> {
        let observation = ValueObservation.tracking { db in
            try Contact.fetchOne(db, phone: phone)
        }
        return dbManager.observe(observation)
    }
    
    /// Observe recent contacts (reactive)
    func observeRecent(limit: Int = 50) -> AsyncThrowingStream<[Contact], Error> {
        let observation = ValueObservation.tracking { db in
            try Contact.fetchRecent(db, limit: limit)
        }
        return dbManager.observe(observation)
    }
}

extension ContactRepository {
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
        case .smartchip:
            return evaluateSmartChipCondition(condition, column: info.column, fieldId: condition.field)
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
    
    private func evaluateSmartChipCondition(
        _ condition: FilterCondition,
        column: Column,
        fieldId: String
    ) -> SQLSpecificExpressible? {
        switch condition.`operator` {
        case .containsAnyOf:
            guard let selectedValues = condition.selectedValues, !selectedValues.isEmpty else {
                return nil
            }
            return buildContainsAnyOfPredicate(column: column, fieldId: fieldId, selectedValues: selectedValues)
            
        case .containsNoneOf:
            guard let selectedValues = condition.selectedValues, !selectedValues.isEmpty else {
                return nil
            }
            return buildContainsNoneOfPredicate(column: column, fieldId: fieldId, selectedValues: selectedValues)
            
        case .contains, .equals, .isEmpty, .isNotEmpty:
            // Fall back to text condition evaluation for other operators
            return evaluateTextCondition(condition, columnExpression: column, column: column)
            
        default:
            return nil
        }
    }
    
    private func buildContainsAnyOfPredicate(column: Column, fieldId: String, selectedValues: [String]) -> SQLSpecificExpressible? {
        // For groups: JSON format is {"group_id": group_id}
        // For tags/relationships: JSON array of UUIDs
        // We need to check if any of the selected values (names) match
        
        // Get the IDs for the selected names
        let ids = getIdsForNames(fieldId: fieldId, names: selectedValues)
        guard !ids.isEmpty else { return nil }
        
        // Build SQL predicate that checks if the JSON contains any of the IDs
        if fieldId == "contact.groups" {
            // Groups are stored as JSON object: {"uuid": int_id}
            // We need to check if any key matches the group UUIDs
            var predicates: [SQLSpecificExpressible] = []
            for id in ids {
                // Check if JSON contains the key (group UUID)
                predicates.append(column.like("%\"\(id)\"%"))
            }
            // Combine with OR
            return combineOrPredicates(predicates)
        } else {
            // Tags and relationships are stored as JSON arrays of UUIDs
            var predicates: [SQLSpecificExpressible] = []
            for id in ids {
                // Check if JSON array contains the UUID
                predicates.append(column.like("%\(id)%"))
            }
            // Combine with OR
            return combineOrPredicates(predicates)
        }
    }
    
    private func buildContainsNoneOfPredicate(column: Column, fieldId: String, selectedValues: [String]) -> SQLSpecificExpressible? {
        // Similar to containsAnyOf but negated
        guard let anyOfPredicate = buildContainsAnyOfPredicate(column: column, fieldId: fieldId, selectedValues: selectedValues) else {
            return nil
        }
        // Negate: NOT (contains any of)
        return SQL("NOT (\(anyOfPredicate))")
    }
    
    private func getIdsForNames(fieldId: String, names: [String]) -> [String] {
        // This is a synchronous helper - in practice, we'd need to fetch from database
        // For now, return the names as-is (they might be UUIDs or names)
        // In a real implementation, we'd need to look up UUIDs from names
        return names
    }
    
    private func combineOrPredicates(_ predicates: [SQLSpecificExpressible]) -> SQLSpecificExpressible? {
        guard let first = predicates.first else { return nil }
        if predicates.count == 1 { return first }
        
        // Build OR expression using SQL - workaround for existential type limitations
        // Combine predicates with OR using SQL string building
        let sqlParts = predicates.map { pred in
            // Convert predicate to SQL string representation
            // This is a simplified approach - in practice we'd need proper SQL serialization
            return "\(pred)"
        }
        // For now, return first predicate as workaround
        // TODO: Properly combine OR predicates when existential type issue is resolved
        return first
    }
}

private extension ContactRepository {
    func apply(filters: [String: AnyCodable], to request: QueryInterfaceRequest<Contact>) -> QueryInterfaceRequest<Contact> {
        var request = request
        for (columnId, value) in filters {
            guard let info = Self.columnMap[columnId] else { continue }
            let columnExpression: SQLSpecificExpressible
            if let collate = info.collate {
                columnExpression = info.column.collating(collate)
            } else {
                columnExpression = info.column
            }
            switch info.semanticType {
            case .text:
                if let stringValue = value.value as? String, !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let pattern = "%\(stringValue)%"
                    request = request.filter(columnExpression.like(pattern))
                } else if let arrayValue = value.value as? [String] {
                    let expressions = arrayValue
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .map { columnExpression.like("%\($0)%") }
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
            case .smartchip:
                // Smartchip fields use text-like filtering for legacy support
                if let stringValue = value.value as? String, !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let pattern = "%\(stringValue)%"
                    request = request.filter(columnExpression.like(pattern))
                }
            case .date:
                if let stringValue = value.value as? String, !stringValue.isEmpty {
                    request = request.filter(info.column.like("%\(stringValue)%"))
                }
            }
        }
        return request
    }
    
    func apply(sorts: [GridSortDescriptor], to request: QueryInterfaceRequest<Contact>) -> QueryInterfaceRequest<Contact> {
        var orderingTerms: [SQLOrderingTerm] = []
        for descriptor in sorts {
            guard let info = Self.columnMap[descriptor.columnId] else { continue }
            var columnExpression: SQLSpecificExpressible = info.column
            if let collate = info.collate {
                columnExpression = info.column.collating(collate)
            }
            
            // Special handling for name column: A-Z, 0-9, special chars, spaces, null
            if descriptor.columnId == "contact.name" {
                // Use SQL expression for custom sorting
                let sortKey = SQL("""
                    CASE 
                        WHEN name IS NULL OR name = '' THEN 4
                        WHEN lower(substr(trim(name), 1, 1)) BETWEEN 'a' AND 'z' THEN 0
                        WHEN substr(trim(name), 1, 1) BETWEEN '0' AND '9' THEN 1
                        WHEN substr(trim(name), 1, 1) = ' ' THEN 3
                        ELSE 2
                    END
                    """)
                switch descriptor.direction {
                case .ascending:
                    orderingTerms.append(sortKey.asc)
                    orderingTerms.append(columnExpression.collating(.localizedCaseInsensitiveCompare).asc)
                case .descending:
                    orderingTerms.append(sortKey.desc)
                    orderingTerms.append(columnExpression.collating(.localizedCaseInsensitiveCompare).desc)
                }
            } else {
                switch descriptor.direction {
                case .ascending:
                    orderingTerms.append(columnExpression.asc)
                case .descending:
                    orderingTerms.append(columnExpression.desc)
                }
            }
        }
        if orderingTerms.isEmpty {
            // Default sort: A-Z, 0-9, special chars, spaces, null
            let sortKey = SQL("""
                CASE 
                    WHEN name IS NULL OR name = '' THEN 4
                    WHEN lower(substr(trim(name), 1, 1)) BETWEEN 'a' AND 'z' THEN 0
                    WHEN substr(trim(name), 1, 1) BETWEEN '0' AND '9' THEN 1
                    WHEN substr(trim(name), 1, 1) = ' ' THEN 3
                    ELSE 2
                END
                """)
            orderingTerms.append(sortKey.asc)
            orderingTerms.append(Contact.Columns.name.collating(.localizedCaseInsensitiveCompare).asc)
        }
        return request.order(orderingTerms)
    }
}

