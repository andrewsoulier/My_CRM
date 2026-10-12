import Foundation
import GRDB

@MainActor
class TagRepository {
    private let dbManager: GRDBDatabaseManager
    private let logger = LogManager.shared
    
    init(dbManager: GRDBDatabaseManager? = nil) {
        self.dbManager = dbManager ?? GRDBDatabaseManager.shared
    }
    
    // MARK: - CRUD
    
    func fetchAll() async throws -> [Tag] {
        try await dbManager.read { db in
            try Tag
                .order(Column("name"))
                .fetchAll(db)
        }
    }
    
    func fetch(uuid: UUID) async throws -> Tag? {
        try await dbManager.read { db in
            try Tag.fetchOne(db, uuid: uuid)
        }
    }
    
    func findOrCreate(name: String, colorHex: String? = nil) async throws -> Tag {
        if let existing = try await fetchByName(name: name) {
            return existing
        }
        
        let tag = Tag(name: name, colorHex: colorHex)
        try await insert(tag)
        return tag
    }
    
    func fetchByName(name: String) async throws -> Tag? {
        try await dbManager.read { db in
            try Tag
                .filter(Column("name") == name)
                .fetchOne(db)
        }
    }
    
    func insert(_ tag: Tag) async throws {
        try await dbManager.write { db in
            var mutableTag = tag
            try mutableTag.insert(db)
        }
        logger.info("✅ Inserted tag \(tag.name)")
    }
    
    func update(_ tag: Tag) async throws {
        try await dbManager.write { db in
            var mutableTag = tag
            try mutableTag.update(db)
        }
        logger.info("✅ Updated tag \(tag.name)")
    }
    
    func upsert(_ tag: Tag) async throws {
        try await dbManager.write { db in
            var mutableTag = tag
            try mutableTag.save(db)
        }
    }
    
    func delete(uuid: UUID) async throws {
        let deleted = try await dbManager.write { db in
            try Tag
                .filter(Column("uuid") == uuid.uuidString)
                .deleteAll(db)
        }
        if deleted > 0 {
            logger.info("🗑️ Deleted tag \(uuid.uuidString)")
        } else {
            logger.warning("⚠️ Tag not found for deletion \(uuid.uuidString)")
        }
    }
    
    // MARK: - Linking helpers
    
    func link(tagUUID: UUID, toContact contactID: Int64) async throws {
        try await updateLinks(tagUUID: tagUUID) { tag in
            var updated = tag
            if !updated.linkedContactIDs.contains(contactID) {
                updated.linkedContactIDs.append(contactID)
            }
            return updated
        }
    }
    
    func unlink(tagUUID: UUID, fromContact contactID: Int64) async throws {
        try await updateLinks(tagUUID: tagUUID) { tag in
            var updated = tag
            updated.linkedContactIDs.removeAll { $0 == contactID }
            return updated
        }
    }
    
    func link(tagUUID: UUID, toGroup groupUUID: UUID) async throws {
        try await updateLinks(tagUUID: tagUUID) { tag in
            var updated = tag
            if !updated.linkedGroupIDs.contains(groupUUID) {
                updated.linkedGroupIDs.append(groupUUID)
            }
            return updated
        }
    }
    
    func unlink(tagUUID: UUID, fromGroup groupUUID: UUID) async throws {
        try await updateLinks(tagUUID: tagUUID) { tag in
            var updated = tag
            updated.linkedGroupIDs.removeAll { $0 == groupUUID }
            return updated
        }
    }
    
    private func updateLinks(tagUUID: UUID, transform: (Tag) -> Tag) async throws {
        guard var tag = try await fetch(uuid: tagUUID) else {
            throw DatabaseError(message: "Tag not found: \(tagUUID)")
        }
        tag = transform(tag)
        try await update(tag)
    }
    
    // MARK: - Observations
    
    func observeAll() -> AsyncThrowingStream<[Tag], Error> {
        let observation = ValueObservation.tracking { db in
            try Tag.order(Column("name")).fetchAll(db)
        }
        return dbManager.observe(observation)
    }
}

