import SwiftUI

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.title3)
            
            Text(message)
                .foregroundColor(.red)
                .font(.body)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.7))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Dismiss error")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.red.opacity(0.1)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.red.opacity(0.3)),
                    alignment: .bottom
                )
        )
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    VStack {
        ErrorBanner(message: "This is a sample error message that can be quite long and will wrap to multiple lines if needed.") {
            print("Dismissed")
        }
        Spacer()
    }
    .padding()
}

