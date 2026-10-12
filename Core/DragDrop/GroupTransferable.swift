import SwiftUI
import UniformTypeIdentifiers

struct GroupTransferable: Transferable, Codable {
    let item: GroupDragItem
    
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .crmGroup)
    }
}

struct GroupDragItem: Codable, Hashable {
    var groupId: UUID
    var groupName: String
    var memberPhones: [String]
    var origin: GroupDragOrigin
}

enum GroupDragOrigin: Codable, Hashable {
    case groupsToolbar
    case canvas(canvasId: UUID)
    case group(id: UUID) // For nested groups
}
