import Foundation
import GRDB

/// Repository for Invite database operations using GRDB
@MainActor
class InviteRepository {
    private let dbManager: GRDBDatabaseManager
    private let logger = LogManager.shared
    
    init(dbManager: GRDBDatabaseManager? = nil) {
        self.dbManager = dbManager ?? GRDBDatabaseManager.shared
    }
    
    // MARK: - Create
    
    /// Insert a new invite
    func insert(_ invite: Invite) async throws {
        try await dbManager.write { db in
            try invite.insert(db)
        }
        logger.info("✅ Inserted invite: \(invite.title) (\(invite.id))")
    }
    
    /// Insert multiple invites in a transaction
    func insertAll(_ invites: [Invite]) async throws {
        try await dbManager.transaction { db in
            for invite in invites {
                try invite.insert(db)
            }
            return ()
        }
        logger.info("✅ Inserted \(invites.count) invites")
    }
    
    // MARK: - Read
    
    /// Fetch invite by ID
    func fetchOne(id: UUID) async throws -> Invite? {
        return try await dbManager.read { db in
            try Invite.fetchOne(db, id: id)
        }
    }
    
    /// Fetch all invites
    func fetchAll() async throws -> [Invite] {
        return try await dbManager.read { db in
            try Invite
                .order(Column("priority").desc, Column("due_date").asc)
                .fetchAll(db)
        }
    }
    
    /// Fetch pending invites
    func fetchPending() async throws -> [Invite] {
        return try await dbManager.read { db in
            try Invite.fetchPending(db)
        }
    }
    
    /// Fetch invites by priority
    func fetch(priority: Priority) async throws -> [Invite] {
        return try await dbManager.read { db in
            try Invite.fetch(db, priority: priority)
        }
    }
    
    /// Fetch invites due today
    func fetchDueToday() async throws -> [Invite] {
        return try await dbManager.read { db in
            try Invite.fetchDueToday(db)
        }
    }
    
    /// Fetch overdue invites
    func fetchOverdue() async throws -> [Invite] {
        return try await dbManager.read { db in
            try Invite.fetchOverdue(db)
        }
    }
    
    /// Fetch invites for a contact
    func fetchAll(phoneNumber: String) async throws -> [Invite] {
        return try await dbManager.read { db in
            try Invite
                .filter(Column("to_phone") == phoneNumber || Column("from_phone") == phoneNumber)
                .order(Column("due_date").desc)
                .fetchAll(db)
        }
    }
    
    /// Count total invites
    func count() async throws -> Int {
        return try await dbManager.read { db in
            try Invite.fetchCount(db)
        }
    }
    
    /// Count pending invites
    func countPending() async throws -> Int {
        return try await dbManager.read { db in
            try Invite
                .filter(Column("completed") == false)
                .fetchCount(db)
        }
    }
    
    // MARK: - Update
    
    /// Update an existing invite
    func update(_ invite: Invite) async throws {
        try await dbManager.write { db in
            try invite.update(db)
        }
        logger.info("✅ Updated invite: \(invite.title) (\(invite.id))")
    }
    
    /// Upsert (insert or update) an invite
    func upsert(_ invite: Invite) async throws {
        try await dbManager.write { db in
            try invite.save(db)
        }
        logger.info("✅ Upserted invite: \(invite.title) (\(invite.id))")
    }
    
    /// Mark invite as completed
    func markCompleted(id: UUID) async throws {
        try await dbManager.write { db in
            guard var invite = try Invite.fetchOne(db, id: id) else {
                throw DatabaseError(message: "Invite not found: \(id)")
            }
            
            var updatedInvite = invite
            updatedInvite.completed = true
            updatedInvite.dateCompleted = Date()
            updatedInvite.completionStatus = .completed
            updatedInvite.lastModifiedDate = Date()
            
            try updatedInvite.update(db)
        }
        logger.info("✅ Marked invite as completed: \(id)")
    }
    
    // MARK: - Delete
    
    /// Delete invite by ID
    func delete(id: UUID) async throws {
        let deleted = try await dbManager.write { db in
            try Invite
                .filter(Column("id") == id.uuidString)
                .deleteAll(db)
        }
        
        if deleted > 0 {
            logger.info("✅ Deleted invite: \(id)")
        } else {
            logger.warning("⚠️ Invite not found for deletion: \(id)")
        }
    }
    
    /// Delete an invite
    func delete(_ invite: Invite) async throws {
        try await delete(id: invite.id)
    }
    
    /// Delete completed invites older than specified date
    func deleteCompleted(olderThan date: Date) async throws {
        let dateString = ISO8601DateFormatter().string(from: date)
        
        let deleted = try await dbManager.write { db in
            try Invite
                .filter(Column("completed") == true)
                .filter(Column("date_completed") < dateString)
                .deleteAll(db)
        }
        logger.info("✅ Deleted \(deleted) completed invites older than \(date)")
    }
    
    // MARK: - Observations
    
    /// Observe all invites (reactive)
    func observeAll() -> AsyncThrowingStream<[Invite], Error> {
        let observation = ValueObservation.tracking { db in
            try Invite
                .order(Column("priority").desc, Column("due_date").asc)
                .fetchAll(db)
        }
        return dbManager.observe(observation)
    }
    
    /// Observe single invite by ID (reactive)
    func observe(id: UUID) -> AsyncThrowingStream<Invite?, Error> {
        let observation = ValueObservation.tracking { db in
            try Invite.fetchOne(db, id: id)
        }
        return dbManager.observe(observation)
    }
    
    /// Observe pending invites (reactive)
    func observePending() -> AsyncThrowingStream<[Invite], Error> {
        let observation = ValueObservation.tracking { db in
            try Invite.fetchPending(db)
        }
        return dbManager.observe(observation)
    }
    
    /// Observe invites due today (reactive)
    func observeDueToday() -> AsyncThrowingStream<[Invite], Error> {
        let observation = ValueObservation.tracking { db in
            try Invite.fetchDueToday(db)
        }
        return dbManager.observe(observation)
    }
}

