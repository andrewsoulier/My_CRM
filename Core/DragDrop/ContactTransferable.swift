import SwiftUI
import UniformTypeIdentifiers

struct ContactTransferable: Transferable, Codable {
    let item: ContactDragItem
    
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .crmContactList)
    }
}
