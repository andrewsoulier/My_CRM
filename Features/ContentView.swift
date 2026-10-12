import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Text("My CRM")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Group {
                Text(appModel.isBackendConnected ? "Backend: Connected" : "Backend: Disconnected")
                    .font(.headline)
                if let db = appModel.dbURL {
                    Text("DB: \(db.path())")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("DB: Not set")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: 720, minHeight: 480)
        .padding(24)
    }
}
