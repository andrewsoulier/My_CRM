import Foundation
import SQLite3

struct MessagesImportStats {
    let totalChats: Int
    let totalMessages: Int
    let importedNew: Int
}

final class MessagesImporter {
    private let logger = LogManager.shared
    private let appleEpochToUnixSeconds: Int64 = 978_307_200 // seconds between 1970 and 2001 epochs
    
    /// Normalize phone number to format +###########
    /// Removes spaces, parentheses, dashes, and ensures it starts with +
    private func normalizePhone(_ phone: String) -> String {
        // If it's an email, return as-is
        if phone.contains("@") {
            return phone
        }
        
        // Remove all non-digit characters except +
        let digitsOnly = phone.filter { $0.isNumber || $0 == "+" }
        
        // If it already starts with +, return as is
        if digitsOnly.hasPrefix("+") {
            return digitsOnly
        }
        
        // If it's 10 digits, assume US number and prepend +1
        if digitsOnly.count == 10 {
            return "+1" + digitsOnly
        }
        
        // If it's 11 digits starting with 1, prepend +
        if digitsOnly.count == 11 && digitsOnly.hasPrefix("1") {
            return "+" + digitsOnly
        }
        
        // Otherwise, just prepend + to whatever we have
        return "+" + digitsOnly
    }

    private func appleNsToUnixMs(_ appleNs: Int64) -> Int64 {
        // Convert Apple epoch nanoseconds to Unix epoch milliseconds
        return (appleNs / 1_000_000) + (appleEpochToUnixSeconds * 1_000)
    }

    private func unixMsToAppleNs(_ unixMs: Int64) -> Int64 {
        // Convert Unix epoch milliseconds back to Apple epoch nanoseconds
        // Handle edge case: if unixMs is 0 or very small, return 0 to avoid overflow
        if unixMs == 0 {
            return 0
        }
        
        // Use checked arithmetic to prevent overflow
        let epochOffsetMs = appleEpochToUnixSeconds * 1_000
        let adjustedMs = unixMs - epochOffsetMs
        
        // Check if multiplication would overflow
        if adjustedMs < Int64.min / 1_000_000 || adjustedMs > Int64.max / 1_000_000 {
            logger.warning("⚠️ MessagesImporter: Timestamp conversion would overflow, returning 0")
            return 0
        }
        
        return adjustedMs * 1_000_000
    }
    func run(chatDBPath: String? = nil) -> MessagesImportStats {
        let path = chatDBPath ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library").appendingPathComponent("Messages")
            .appendingPathComponent("chat.db").path

        var chatDB: OpaquePointer?
        var totalChats = 0
        var totalMessages = 0
        var importedNew = 0

        logger.info("💬 MessagesImporter.run(): starting (chatDB=\(path), crmDB=\(SettingsManager.shared.settings.database.path))")
        
        // ALWAYS ensure messages table exists, even if we can't access chat.db
        // This ensures the table is created on first run regardless of Full Disk Access
        if let crm = try? CRMDatabase.shared.open() {
            MessagesDAO().ensureSchema(db: crm)
            sqlite3_close(crm)
            logger.info("💬 MessagesImporter.run(): Ensured messages table exists")
        } else {
            logger.warning("💬 MessagesImporter.run(): Could not ensure messages table (database connection failed)")
        }
        
        // Open chat.db in READONLY mode to avoid conflicts with IMDPersistenceAgent
        let openResult = sqlite3_open_v2(path, &chatDB, SQLITE_OPEN_READONLY, nil)
        if openResult == SQLITE_OK {
            defer { sqlite3_close(chatDB) }
            totalChats = count(db: chatDB, table: "chat")
            totalMessages = count(db: chatDB, table: "message")
            logger.info("💬 MessagesImporter.run(): chat.db counts chats=\(totalChats) messages=\(totalMessages)")
            // Determine the latest CRM timestamp, then import all chat.db messages newer than that
            let lastUnixMs = getMaxCrmTimestamp()
            logger.info("💬 MessagesImporter.run(): last CRM unixMs=\(lastUnixMs)")
            let sinceAppleNs = unixMsToAppleNs(lastUnixMs)
            logger.info("💬 MessagesImporter.run(): sinceAppleNs=\(sinceAppleNs)")
            if let msgs = readMessagesSince(db: chatDB, sinceAppleNs: sinceAppleNs) {
                importedNew = msgs.count
                logger.info("💬 MessagesImporter.run(): fetched messages to import=\(importedNew)")
                if importedNew > 0, let crm = try? CRMDatabase.shared.open() {
                    defer { sqlite3_close(crm) }
                    let batchSize = 5000
                    var rows: [[String: Any]] = []
                    rows.reserveCapacity(min(batchSize, msgs.count))
                    let dao = MessagesDAO()
                    for m in msgs {
                        var guid = m.guid
                        if guid.isEmpty { guid = "ROWID-\(m.rowid)" }
                        
                        let normalizedPhone = m.phoneNumber.map { normalizePhone($0) } ?? ""
                        let bodyText = m.body ?? decodeAttributedBody(m.attributedBody) ?? ""
                        
                        rows.append([
                            "guid": guid,
                            "rowid": m.rowid,
                            "body": bodyText,
                            "phone_number": normalizedPhone,
                            "is_from_me": m.isFromMe,
                            "cache_roomname": m.cacheRoomname ?? "",
                            "group_chat_name": m.groupChatName ?? "",
                            "timestamp": appleNsToUnixMs(m.timestamp),
                            "service": m.service ?? "",
                            "account": m.account ?? "",
                            "chat_id": m.chatId ?? "",
                            "attributedBody": m.attributedBody ?? Data(),
                            "subject": m.subject ?? "",
                            "country": m.country ?? "",
                            "error": m.error ?? 0,
                            "date_read": m.dateRead ?? 0,
                            "date_delivered": m.dateDelivered ?? 0,
                            "is_sent": m.isSent ?? 0,
                            "is_read": m.isRead ?? 0,
                            "has_attachments": m.hasAttachments,
                            "contact_id": 0,
                            "message_type": m.messageType ?? "",
                            "is_first_message": 0,
                            "is_last_message": 0,
                            "is_new": 0,
                            "source": "imessage"
                        ])
                        
                        if rows.count >= batchSize {
                            dao.upsertBatch(db: crm, rows: rows)
                            rows.removeAll(keepingCapacity: true)
                        }
                    }
                    if !rows.isEmpty {
                        dao.upsertBatch(db: crm, rows: rows)
                    }
                    logger.info("💬 MessagesImporter.run(): upserted rows=\(importedNew)")
                    let totalAfter = count(db: crm, table: "messages")
                    logger.info("💬 MessagesImporter.run(): CRM messages total after upsert=\(totalAfter)")
                }
            }
        } else {
            let errorMsg = String(cString: sqlite3_errstr(openResult))
            print("❌ MessagesImporter: Could not open chat.db at \(path) - SQLite error \(openResult): \(errorMsg)")
            logger.error("❌ MessagesImporter: Could not open chat.db at \(path) - SQLite error \(openResult): \(errorMsg)")
        }

        logger.info("💬 MessagesImporter.run(): done (importedNew=\(importedNew))")
        return MessagesImportStats(totalChats: totalChats, totalMessages: totalMessages, importedNew: importedNew)
    }

    // MARK: - Minimal message read from chat.db (schema simplified)
    private struct ChatMsg {
        let guid: String
        let rowid: Int
        let body: String?
        let attributedBody: Data?
        let phoneNumber: String?
        let isFromMe: Bool
        let cacheRoomname: String?
        let groupChatName: String?
        let timestamp: Int64
        let service: String?
        let account: String?
        let chatId: String?
        let subject: String?
        let country: String?
        let error: Int?
        let dateRead: Int?
        let dateDelivered: Int?
        let isSent: Int?
        let isRead: Int?
        let hasAttachments: Bool
        let messageType: String?
    }

    private func decodeAttributedBody(_ data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        if text.contains("NSString") {
            text = text.components(separatedBy: "NSString").dropFirst().joined(separator: "NSString")
        }
        if text.contains("NSNumber") {
            text = text.components(separatedBy: "NSNumber").first ?? text
        }
        if text.contains("NSDictionary") {
            text = text.components(separatedBy: "NSDictionary").first ?? text
        }
        text = text.trimmingCharacters(in: .controlCharacters)
        if text.count > 12 {
            text = String(text.dropFirst(6).dropLast(6))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func readMessagesSince(db: OpaquePointer?, sinceAppleNs: Int64) -> [ChatMsg]? {
        let sql = """
        SELECT 
            m.guid, 
            m.rowid, 
            m.text as body,
            m.attributedBody,
            m.is_from_me, 
            m.date as timestamp,
            h.id as phone_number
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        WHERE m.date >= ?
        ORDER BY m.date ASC
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, sinceAppleNs)
        var result: [ChatMsg] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let guid = String(cString: sqlite3_column_text(stmt, 0))
            let rowid = Int(sqlite3_column_int64(stmt, 1))
            let body = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            var attributedBody: Data?
            if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                let dataPtr = sqlite3_column_blob(stmt, 3)
                let dataSize = Int(sqlite3_column_bytes(stmt, 3))
                if let dataPtr = dataPtr, dataSize > 0 {
                    attributedBody = Data(bytes: dataPtr, count: dataSize)
                }
            }
            let isFromMe = sqlite3_column_int(stmt, 4) == 1
            let timestamp = sqlite3_column_int64(stmt, 5)
            let phoneNumber = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
            result.append(ChatMsg(
                guid: guid,
                rowid: rowid,
                body: body,
                attributedBody: attributedBody,
                phoneNumber: phoneNumber,
                isFromMe: isFromMe,
                cacheRoomname: nil,
                groupChatName: nil,
                timestamp: timestamp,
                service: nil,
                account: nil,
                chatId: nil,
                subject: nil,
                country: nil,
                error: nil,
                dateRead: nil,
                dateDelivered: nil,
                isSent: nil,
                isRead: nil,
                hasAttachments: false,
                messageType: nil
            ))
        }
        return result
    }

    // MARK: - CRM helpers
    private func getMaxCrmTimestamp() -> Int64 {
        guard let db = try? CRMDatabase.shared.open() else { return 0 }
        defer { sqlite3_close(db) }
        // Ensure schema to avoid errors on empty DB
        MessagesDAO().ensureSchema(db: db)
        var stmt: OpaquePointer?
        let sql = "SELECT COALESCE(MAX(timestamp), 0) FROM messages;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        return 0
    }

    private func count(db: OpaquePointer?, table: String) -> Int {
        var stmt: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM \(table);"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW { return Int(sqlite3_column_int(stmt, 0)) }
        return 0
    }
}


