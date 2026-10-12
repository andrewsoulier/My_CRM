import SwiftUI
import UniformTypeIdentifiers

struct DropTestView: View {
    @State private var droppedContacts: [Contact] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Drop Test View")
                .font(.title)
                .padding()
            
            Text("Drag contacts here to test drop functionality")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Rectangle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 300, height: 200)
                .overlay(
                    Text("Drop Zone")
                        .foregroundColor(.white)
                        .font(.headline)
                )
                .onDrop(of: [UTType.crmContactList.identifier], isTargeted: nil) { providers in
                    DragDropLogger.shared.log("DropTestView onDrop triggered with \(providers.count) providers", operation: "DESTINATION")
                    
                    for provider in providers {
                        provider.loadDataRepresentation(forTypeIdentifier: UTType.crmContactList.identifier) { data, error in
                            if let error = error {
                                DragDropLogger.shared.log("DropTestView failed to load data: \(error)", operation: "ERROR")
                                return
                            }
                            
                            guard let data = data else {
                                DragDropLogger.shared.log("DropTestView no data received", operation: "ERROR")
                                return
                            }
                            
                            if let contact = try? JSONDecoder().decode(Contact.self, from: data) {
                                DragDropLogger.shared.log("DropTestView successfully decoded contact: \(contact.name)", operation: "SUCCESS")
                                DispatchQueue.main.async {
                                    droppedContacts.append(contact)
                                }
                            } else {
                                DragDropLogger.shared.log("DropTestView failed to decode contact", operation: "ERROR")
                            }
                        }
                    }
                    return true
                }
            
            if !droppedContacts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Dropped Contacts:")
                        .font(.headline)
                    
                    ForEach(droppedContacts, id: \.id) { contact in
                        Text("• \(contact.name) (\(contact.phone))")
                            .font(.caption)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
