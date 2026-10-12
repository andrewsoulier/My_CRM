import SwiftUI

struct ContactNodeView: View {
    let contact: Contact
    @EnvironmentObject var selectionManager: SelectionManager
    
    var body: some View {
        ZStack {
            // Background Circle
            Circle()
                .fill(Color.accentColor.opacity(0.1))
                .stroke(Color.accentColor, lineWidth: 1)
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(selectionManager.isContactSelected(contact.phone) ? Color.accentColor.opacity(0.2) : Color.clear)
                )
            
            // Profile Photo or Contact Initials
            if let profileImage = contact.profileImage {
                Image(nsImage: profileImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
            } else {
                Text(contact.initials)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
        }
        .scaleEffect(selectionManager.isContactSelected(contact.phone) ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: selectionManager.isContactSelected(contact.phone))
        .overlay(
            // Selection indicator
            Group {
                if selectionManager.isContactSelected(contact.phone) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.caption2)
                                .foregroundColor(.white)
                        )
                        .offset(x: 25, y: -25)
                }
            }
        )
    }
}

#Preview {
    ContactNodeView(contact: Contact(
        phone: "+1-555-000-0000",
        name: "Contact Name",
        firstName: "Contact",
        lastName: "Name",
        email: "contact@example.com",
        business: "Company"
    ))
    .environmentObject(SelectionManager())
}
