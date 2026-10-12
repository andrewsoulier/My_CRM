import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let crmContactList = UTType(exportedAs: "com.mycrm.contact-list")
    static let crmGroup = UTType(exportedAs: "com.mycrm.group")
}

struct ContactDragItem: Codable, Hashable {
    var phones: [String]          // primary keys
    var uuids: [UUID]             // contact UUIDs
    var origin: DragOrigin        // .contactsBar, .group(UUID), .deck(UUID)
}

enum DragOrigin: Codable, Hashable {
    case contactsBar
    case group(id: UUID)
    case deck(id: UUID)
}
