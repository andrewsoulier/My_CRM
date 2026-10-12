import Foundation
import SQLite3

/// Updates contact message metadata from the messages table after import.
final class ContactMessageEnrichmentService {
    private let logger = LogManager.shared

    struct EnrichmentStats {
        let contactsUpdated: Int
        let messagesLinked: Int
    }

    func run() -> EnrichmentStats {
        guard let db = try? CRMDatabase.shared.open() else {
            logger.error("❌ ContactMessageEnrichmentService: Failed to open database")
            return EnrichmentStats(contactsUpdated: 0, messagesLinked: 0)
        }
        defer { sqlite3_close(db) }

        logger.info("🔄 ContactMessageEnrichmentService: Starting contact enrichment from messages")

        sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil)

        // Link messages to contacts by normalized phone (last 10 digits) or exact phone match
        let linkSQL = """
        UPDATE messages
        SET contact_id = (
            SELECT c.id FROM contacts c
            WHERE c.phone = messages.phone_number
               OR (length(replace(replace(replace(c.phone, '+', ''), '-', ''), ' ', '')) >= 10
                   AND length(replace(replace(replace(messages.phone_number, '+', ''), '-', ''), ' ', '')) >= 10
                   AND substr(replace(replace(replace(c.phone, '+', ''), '-', ''), ' ', ''), -10)
                     = substr(replace(replace(replace(messages.phone_number, '+', ''), '-', ''), ' ', ''), -10))
            LIMIT 1
        )
        WHERE (contact_id IS NULL OR contact_id = 0)
          AND phone_number IS NOT NULL
          AND phone_number != ''
        """
        var linked = 0
        if sqlite3_exec(db, linkSQL, nil, nil, nil) == SQLITE_OK {
            linked = Int(sqlite3_changes(db))
        } else {
            logger.warning("⚠️ ContactMessageEnrichmentService: Message linking failed: \(String(cString: sqlite3_errmsg(db)))")
        }

        // Aggregate stats per contact from linked messages
        let enrichSQL = """
        UPDATE contacts SET
            first_message_date = COALESCE((
                SELECT datetime(MIN(
                    CASE
                        WHEN m.timestamp > 1000000000000 THEN m.timestamp / 1000.0
                        WHEN m.timestamp > 1000000000 THEN m.timestamp * 1.0
                        ELSE (m.timestamp + 978307200) * 1000.0
                    END
                ) / 1000.0, 'unixepoch')
                FROM messages m WHERE m.contact_id = contacts.id
            ), first_message_date),
            last_message_date = (
                SELECT datetime(MAX(
                    CASE
                        WHEN m.timestamp > 1000000000000 THEN m.timestamp / 1000.0
                        WHEN m.timestamp > 1000000000 THEN m.timestamp * 1.0
                        ELSE (m.timestamp + 978307200) * 1000.0
                    END
                ) / 1000.0, 'unixepoch')
                FROM messages m WHERE m.contact_id = contacts.id
            ),
            total_messages = (
                SELECT COUNT(*) FROM messages m WHERE m.contact_id = contacts.id
            ),
            messages_sent = (
                SELECT COUNT(*) FROM messages m WHERE m.contact_id = contacts.id AND m.is_from_me = 1
            ),
            messages_received = (
                SELECT COUNT(*) FROM messages m WHERE m.contact_id = contacts.id AND m.is_from_me = 0
            ),
            sent_last_message = COALESCE((
                SELECT m.is_from_me FROM messages m
                WHERE m.contact_id = contacts.id
                ORDER BY m.timestamp DESC LIMIT 1
            ), sent_last_message)
        WHERE id IN (SELECT DISTINCT contact_id FROM messages WHERE contact_id IS NOT NULL AND contact_id != 0)
        """
        var updated = 0
        if sqlite3_exec(db, enrichSQL, nil, nil, nil) == SQLITE_OK {
            updated = Int(sqlite3_changes(db))
        } else {
            logger.warning("⚠️ ContactMessageEnrichmentService: Enrichment failed: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return EnrichmentStats(contactsUpdated: 0, messagesLinked: linked)
        }

        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        logger.info("✅ ContactMessageEnrichmentService: Linked \(linked) messages, updated \(updated) contacts")
        return EnrichmentStats(contactsUpdated: updated, messagesLinked: linked)
    }
}
