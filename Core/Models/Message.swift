import Foundation

/// Message model for iMessage data
struct Message: Identifiable, Codable {
    var guid: String // Primary key
    var rowid: Int?
    var body: String?
    var phoneNumber: String?
    var isFromMe: Bool
    var cacheRoomname: String?
    var groupChatName: String?
    var timestamp: Int?
    var service: String?
    var account: String?
    var chatId: String?
    var attributedBody: Data?
    var subject: String?
    var country: String?
    var error: Int
    var dateRead: Int
    var dateDelivered: Int
    var isSent: Bool
    var isRead: Bool
    var hasAttachments: Bool
    var contactId: Int?
    var messageType: String?
    var isFirstMessage: Bool
    var isLastMessage: Bool
    var isNew: Bool
    var source: String
    
    var id: String { guid }
    
    init(
        guid: String,
        rowid: Int? = nil,
        body: String? = nil,
        phoneNumber: String? = nil,
        isFromMe: Bool = false,
        cacheRoomname: String? = nil,
        groupChatName: String? = nil,
        timestamp: Int? = nil,
        service: String? = nil,
        account: String? = nil,
        chatId: String? = nil,
        attributedBody: Data? = nil,
        subject: String? = nil,
        country: String? = nil,
        error: Int = 0,
        dateRead: Int = 0,
        dateDelivered: Int = 0,
        isSent: Bool = false,
        isRead: Bool = false,
        hasAttachments: Bool = false,
        contactId: Int? = nil,
        messageType: String? = nil,
        isFirstMessage: Bool = false,
        isLastMessage: Bool = false,
        isNew: Bool = false,
        source: String = "imessage"
    ) {
        self.guid = guid
        self.rowid = rowid
        self.body = body
        self.phoneNumber = phoneNumber
        self.isFromMe = isFromMe
        self.cacheRoomname = cacheRoomname
        self.groupChatName = groupChatName
        self.timestamp = timestamp
        self.service = service
        self.account = account
        self.chatId = chatId
        self.attributedBody = attributedBody
        self.subject = subject
        self.country = country
        self.error = error
        self.dateRead = dateRead
        self.dateDelivered = dateDelivered
        self.isSent = isSent
        self.isRead = isRead
        self.hasAttachments = hasAttachments
        self.contactId = contactId
        self.messageType = messageType
        self.isFirstMessage = isFirstMessage
        self.isLastMessage = isLastMessage
        self.isNew = isNew
        self.source = source
    }
    
    /// Computed property to convert timestamp to Date
    var date: Date? {
        guard let timestamp = timestamp else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}

// MARK: - Equatable

extension Message: Equatable {
    static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.guid == rhs.guid
    }
}

// MARK: - Hashable

extension Message: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(guid)
    }
}

