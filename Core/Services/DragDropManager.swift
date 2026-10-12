import SwiftUI
import Foundation
import UniformTypeIdentifiers

// swiftlint:disable:next sendable
// NSItemProvider doesn't conform to Sendable, but this is expected and safe in our usage

@MainActor
final class DragDropManager: ObservableObject {
    static let shared = DragDropManager()
    
    init() {}
    
    // MARK: - Drag Source Helpers
    
    func makeItems(for phones: [String], uuids: [UUID], origin: DragOrigin, dataProvider: any DataProvider) -> [NSItemProvider] {
        let item = ContactDragItem(phones: phones, uuids: uuids, origin: origin)
        return [ProviderBridge.createItemProvider(for: item, dataProvider: dataProvider)]
    }
    
    func transferable(for phones: [String], uuids: [UUID], origin: DragOrigin) -> ContactTransferable {
        let item = ContactDragItem(phones: phones, uuids: uuids, origin: origin)
        return ContactTransferable(item: item)
    }
    
    // MARK: - Drop Target Helpers
    
    // swiftlint:disable:next sendable
    func decodeProviders(_ providers: [NSItemProvider]) async throws -> ContactDragItem? {
        DragDropLogger.shared.log("decodeProviders called with \(providers.count) providers", operation: "DECODE")
        
        guard let provider = providers.first else { 
            DragDropLogger.shared.log("No providers found", operation: "ERROR")
            return nil 
        }
        
        // Use a completion handler approach to avoid Sendable issues
        return try await withCheckedThrowingContinuation { continuation in
            // Use a local variable to avoid Sendable issues
            let localProvider = provider
            
            // Check what type identifiers are available
            let availableTypes = localProvider.registeredTypeIdentifiers
            DragDropLogger.shared.log("Available type identifiers: \(availableTypes)", operation: "DECODE")
            
            // Try CRM contact list format first (our internal format)
            if availableTypes.contains(UTType.crmContactList.identifier) {
                DragDropLogger.shared.log("Loading CRM contact list format", operation: "DECODE")
                localProvider.loadDataRepresentation(forTypeIdentifier: UTType.crmContactList.identifier) { @Sendable data, error in
                    if let error = error {
                        DragDropLogger.shared.log("CRM contact list decode error: \(error), trying vCard format", operation: "DECODE")
                        // Fall back to vCard format
                        // swiftlint:disable:next sendable
                        let sendableProvider = localProvider
                        self.loadVCardFormat(sendableProvider, continuation: continuation)
                        return
                    }
                    
                    guard let data = data else {
                        DragDropLogger.shared.log("No CRM contact list data received", operation: "ERROR")
                        // swiftlint:disable:next sendable
                        let sendableProvider = localProvider
                        self.loadVCardFormat(sendableProvider, continuation: continuation)
                        return
                    }
                    
                    // Try to decode as ContactDragItem first
                    if let item = ProviderBridge.decode(data) {
                        DragDropLogger.shared.log("Successfully decoded CRM contact drag item with \(item.phones.count) phones", operation: "DECODE")
                        continuation.resume(returning: item)
                        return
                    }
                    
                    // If that fails, try to decode as Contact object
                    do {
                        let contact = try JSONDecoder().decode(Contact.self, from: data)
                        DragDropLogger.shared.log("Successfully decoded Contact object: \(contact.name) with phone: \(contact.phone)", operation: "DECODE")
                        let item = ContactDragItem(phones: [contact.phone], uuids: [contact.id], origin: .contactsBar)
                        DragDropLogger.shared.log("Converted Contact to ContactDragItem with \(item.phones.count) phones", operation: "DECODE")
                        continuation.resume(returning: item)
                        return
                    } catch {
                        DragDropLogger.shared.log("Failed to decode as Contact object: \(error)", operation: "ERROR")
                    }
                    
                    DragDropLogger.shared.log("Failed to decode CRM contact data in any format, trying vCard format", operation: "ERROR")
                    // swiftlint:disable:next sendable
                    let sendableProvider = localProvider
                    self.loadVCardFormat(sendableProvider, continuation: continuation)
                }
            } else {
                // Try vCard format
                // swiftlint:disable:next sendable
                let sendableProvider = localProvider
                self.loadVCardFormat(sendableProvider, continuation: continuation)
            }
        }
    }
    
    // MARK: - Helper Methods (nonisolated for use in @Sendable closures)
    
    nonisolated private func loadVCardFormat(_ provider: NSItemProvider, continuation: CheckedContinuation<ContactDragItem?, Error>) {
        DragDropLogger.shared.log("Loading vCard format", operation: "DECODE")
        
        // Try file representation first
        if provider.hasItemConformingToTypeIdentifier(UTType.vCard.identifier) {
            DragDropLogger.shared.log("Loading vCard as file representation", operation: "DECODE")
            // swiftlint:disable:next sendable
            // NSItemProvider doesn't conform to Sendable, but this is safe in our usage
            provider.loadFileRepresentation(forTypeIdentifier: UTType.vCard.identifier) { @Sendable url, error in
                if let error = error {
                    DragDropLogger.shared.log("vCard file load error: \(error), trying data representation", operation: "DECODE")
                    // Fall back to data representation
                    // swiftlint:disable:next sendable
                    let sendableProvider = provider
                    self.loadVCardAsData(sendableProvider, continuation: continuation)
                    return
                }
                
                guard let url = url else {
                    DragDropLogger.shared.log("No vCard file received from provider", operation: "ERROR")
                    // swiftlint:disable:next sendable
                    let sendableProvider = provider
                    self.loadVCardAsData(sendableProvider, continuation: continuation)
                    return
                }
                
                // Read vCard file content
                do {
                    let vCardData = try Data(contentsOf: url)
                    let vCardString = String(data: vCardData, encoding: .utf8) ?? ""
                    DragDropLogger.shared.log("Decoded vCard string from file: \(vCardString)", operation: "DECODE")
                    
                    let contact = Contact.fromVCardString(vCardString)
                    if !contact.phone.isEmpty {
                        let item = ContactDragItem(phones: [contact.phone], uuids: [contact.id], origin: .contactsBar)
                        DragDropLogger.shared.log("Successfully decoded vCard contact with phone: \(contact.phone)", operation: "DECODE")
                        continuation.resume(returning: item)
                    } else {
                        DragDropLogger.shared.log("Failed to decode vCard - empty phone", operation: "ERROR")
                        continuation.resume(throwing: NSError(domain: "CRM", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to decode vCard - empty phone"]))
                    }
                } catch {
                    DragDropLogger.shared.log("Failed to read vCard file: \(error)", operation: "ERROR")
                    continuation.resume(throwing: error)
                }
            }
        } else {
            // Try data representation
            self.loadVCardAsData(provider, continuation: continuation)
        }
    }
    
    nonisolated private func loadVCardAsData(_ provider: NSItemProvider, continuation: CheckedContinuation<ContactDragItem?, Error>) {
        DragDropLogger.shared.log("Loading vCard as data representation", operation: "DECODE")
        // swiftlint:disable:next sendable
        // NSItemProvider doesn't conform to Sendable, but this is safe in our usage
        provider.loadDataRepresentation(forTypeIdentifier: UTType.vCard.identifier) { @Sendable data, error in
            if let error = error {
                DragDropLogger.shared.log("vCard data decode error: \(error)", operation: "ERROR")
                continuation.resume(throwing: NSError(domain: "CRM", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to decode contact drag item"]))
                return
            }
            
            guard let data = data else {
                DragDropLogger.shared.log("No vCard data received from provider", operation: "ERROR")
                continuation.resume(throwing: NSError(domain: "CRM", code: 3, userInfo: [NSLocalizedDescriptionKey: "No vCard data received from provider"]))
                return
            }
            
            // Decode vCard format
            let vCardString = String(data: data, encoding: .utf8) ?? ""
            DragDropLogger.shared.log("Decoded vCard string from data: \(vCardString)", operation: "DECODE")
            
            let contact = Contact.fromVCardString(vCardString)
            if !contact.phone.isEmpty {
                let item = ContactDragItem(phones: [contact.phone], uuids: [contact.id], origin: .contactsBar)
                DragDropLogger.shared.log("Successfully decoded vCard contact with phone: \(contact.phone)", operation: "DECODE")
                continuation.resume(returning: item)
            } else {
                DragDropLogger.shared.log("Failed to decode vCard - empty phone", operation: "ERROR")
                continuation.resume(throwing: NSError(domain: "CRM", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to decode vCard - empty phone"]))
            }
        }
    }
    
    // MARK: - Perform Drop Operations
    
    func performDrop(
        item: ContactDragItem,
        to target: DropTarget,
        copy: Bool,
        dataProvider: any DataProvider,
        undo: UndoManager?
    ) async throws {
        
        // Deduplicate phones while preserving order
        let uniquePhones = Array(NSOrderedSet(array: item.phones)) as? [String] ?? item.phones
        
        guard !uniquePhones.isEmpty else {
            throw NSError(domain: "CRM", code: 4, userInfo: [NSLocalizedDescriptionKey: "No valid contacts to drop"])
        }
        
        switch target {
        case .group(let groupId):
            try await handleGroupDrop(item: item, targetGroupId: groupId, copy: copy, dataProvider: dataProvider, undo: undo)
            

            
        case .sandbox:
            // Future: handle sandbox drops
            break
        }
    }
    
    // MARK: - Group Drop Logic
    
    private func handleGroupDrop(
        item: ContactDragItem,
        targetGroupId: UUID,
        copy: Bool,
        dataProvider: any DataProvider,
        undo: UndoManager?
    ) async throws {
        
        let phones = Array(NSOrderedSet(array: item.phones)) as? [String] ?? item.phones
        
        switch item.origin {
        case .contactsBar:
            // Add contacts to group (non-destructive)
            try await addContactsToGroup(phones: phones, groupId: targetGroupId, dataProvider: dataProvider, undo: undo)
            
        case .group(let sourceGroupId):
            if sourceGroupId == targetGroupId {
                // Same group - no-op
                return
            }
            
            if copy {
                // Copy contacts to target group
                try await addContactsToGroup(phones: phones, groupId: targetGroupId, dataProvider: dataProvider, undo: undo)
            } else {
                // Move contacts from source to target group
                try await moveContactsBetweenGroups(phones: phones, fromGroupId: sourceGroupId, toGroupId: targetGroupId, dataProvider: dataProvider, undo: undo)
            }
            
        case .deck:
            // Add contacts from deck to group (non-destructive)
            try await addContactsToGroup(phones: phones, groupId: targetGroupId, dataProvider: dataProvider, undo: undo)
        }
    }
    

    
    // MARK: - Helper Operations
    
    private func addContactsToGroup(phones: [String], groupId: UUID, dataProvider: any DataProvider, undo: UndoManager?) async throws {
        // Get current group members
        let currentMembers = dataProvider.getGroupMembers(groupId: groupId) ?? []
        let newMembers = currentMembers + phones
        
        // Register undo operation
        undo?.registerUndo(withTarget: self) { _ in
            Task {
                try? await dataProvider.updateGroupMembers(groupId: groupId, members: currentMembers)
            }
        }
        
        // Perform the operation
        try await dataProvider.updateGroupMembers(groupId: groupId, members: newMembers)
    }
    
    private func moveContactsBetweenGroups(phones: [String], fromGroupId: UUID, toGroupId: UUID, dataProvider: any DataProvider, undo: UndoManager?) async throws {
        // Get current members of both groups
        let fromMembers = dataProvider.getGroupMembers(groupId: fromGroupId) ?? []
        let toMembers = dataProvider.getGroupMembers(groupId: toGroupId) ?? []
        
        // Calculate new member lists
        let newFromMembers = fromMembers.filter { !phones.contains($0) }
        let newToMembers = toMembers + phones
        
        // Register undo operation
        undo?.registerUndo(withTarget: self) { _ in
            Task {
                try? await dataProvider.updateGroupMembers(groupId: fromGroupId, members: fromMembers)
                try? await dataProvider.updateGroupMembers(groupId: toGroupId, members: toMembers)
            }
        }
        
        // Perform the operations
        try await dataProvider.updateGroupMembers(groupId: fromGroupId, members: newFromMembers)
        try await dataProvider.updateGroupMembers(groupId: toGroupId, members: newToMembers)
    }
    

}

// MARK: - Drop Target Enum

enum DropTarget {
    case group(id: UUID)

    case sandbox(position: CGPoint?)    // future behaviors
}
