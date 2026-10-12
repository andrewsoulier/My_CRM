import Foundation
import GRDB

@MainActor
class RelationshipRepository {
    private let dbManager: GRDBDatabaseManager
    private let logger = LogManager.shared
    
    init(dbManager: GRDBDatabaseManager? = nil) {
        self.dbManager = dbManager ?? GRDBDatabaseManager.shared
    }
    
    // MARK: - CRUD
    
    func fetchAll() async throws -> [Relationship] {
        try await dbManager.read { db in
            try Relationship
                .order(Column("name"))
                .fetchAll(db)
        }
    }
    
    func fetch(uuid: UUID) async throws -> Relationship? {
        try await dbManager.read { db in
            try Relationship.fetchOne(db, uuid: uuid)
        }
    }
    
    func findOrCreate(name: String, colorHex: String? = nil) async throws -> Relationship {
        if let existing = try await fetchByName(name: name) {
            return existing
        }
        
        let relationship = Relationship(name: name, colorHex: colorHex)
        try await insert(relationship)
        return relationship
    }
    
    func fetchByName(name: String) async throws -> Relationship? {
        try await dbManager.read { db in
            try Relationship
                .filter(Column("name") == name)
                .fetchOne(db)
        }
    }
    
    func insert(_ relationship: Relationship) async throws {
        try await dbManager.write { db in
            var mutable = relationship
            try mutable.insert(db)
        }
        logger.info("✅ Inserted relationship \(relationship.name)")
    }
    
    func update(_ relationship: Relationship) async throws {
        try await dbManager.write { db in
            var mutable = relationship
            try mutable.update(db)
        }
        logger.info("✅ Updated relationship \(relationship.name)")
    }
    
    func upsert(_ relationship: Relationship) async throws {
        try await dbManager.write { db in
            var mutable = relationship
            try mutable.save(db)
        }
    }
    
    func delete(uuid: UUID) async throws {
        let deleted = try await dbManager.write { db in
            try Relationship
                .filter(Column("uuid") == uuid.uuidString)
                .deleteAll(db)
        }
        if deleted > 0 {
            logger.info("🗑️ Deleted relationship \(uuid.uuidString)")
        } else {
            logger.warning("⚠️ Relationship not found for deletion \(uuid.uuidString)")
        }
    }
    
    // MARK: - Linking
    
    func link(relationshipUUID: UUID, toContact contactID: Int64) async throws {
        try await updateLinks(relationshipUUID: relationshipUUID) { relationship in
            var updated = relationship
            if !updated.linkedContactIDs.contains(contactID) {
                updated.linkedContactIDs.append(contactID)
            }
            return updated
        }
    }
    
    func unlink(relationshipUUID: UUID, fromContact contactID: Int64) async throws {
        try await updateLinks(relationshipUUID: relationshipUUID) { relationship in
            var updated = relationship
            updated.linkedContactIDs.removeAll { $0 == contactID }
            return updated
        }
    }
    
    func link(relationshipUUID: UUID, toGroup groupUUID: UUID) async throws {
        try await updateLinks(relationshipUUID: relationshipUUID) { relationship in
            var updated = relationship
            if !updated.linkedGroupIDs.contains(groupUUID) {
                updated.linkedGroupIDs.append(groupUUID)
            }
            return updated
        }
    }
    
    func unlink(relationshipUUID: UUID, fromGroup groupUUID: UUID) async throws {
        try await updateLinks(relationshipUUID: relationshipUUID) { relationship in
            var updated = relationship
            updated.linkedGroupIDs.removeAll { $0 == groupUUID }
            return updated
        }
    }
    
    private func updateLinks(relationshipUUID: UUID, transform: (Relationship) -> Relationship) async throws {
        guard var relationship = try await fetch(uuid: relationshipUUID) else {
            throw DatabaseError(message: "Relationship not found: \(relationshipUUID)")
        }
        relationship = transform(relationship)
        try await update(relationship)
    }
    
    // MARK: - Observations
    
    func observeAll() -> AsyncThrowingStream<[Relationship], Error> {
        let observation = ValueObservation.tracking { db in
            try Relationship.order(Column("name")).fetchAll(db)
        }
        return dbManager.observe(observation)
    }
}

