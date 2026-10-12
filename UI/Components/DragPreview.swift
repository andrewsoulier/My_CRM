import SwiftUI

struct DragPreview: View {
    let count: Int
    
    var body: some View {
        VStack(spacing: 4) {
            // Contact avatars grid (simplified for now)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: min(count, 3)), spacing: 2) {
                ForEach(0..<min(count, 9), id: \.self) { index in
                    Circle()
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Text("👤")
                                .font(.caption2)
                        )
                }
            }
            .frame(width: 60, height: 60)
            
            // Count badge
            if count > 1 {
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(radius: 4)
        )
    }
}

#Preview {
    DragPreview(count: 5)
}
