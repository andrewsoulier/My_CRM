import SwiftUI

@main
struct MyCRMApp: App {
    @StateObject private var locationReporter = LocationReporter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationReporter)
        }
    }
}
