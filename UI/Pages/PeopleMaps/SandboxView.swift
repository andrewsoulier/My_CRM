import SwiftUI

struct SandboxView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    
    var body: some View {
        SimplifiedCanvasView(
            viewModel: globalCanvasService.groupsMapViewModel, 
            gestureCoordinator: globalCanvasService.gestureCoordinator,
            edgeScrollingManager: globalCanvasService.edgeScrollingManager
        )
        .onAppear {
            // Set AppState in viewModel for debug settings access
            globalCanvasService.groupsMapViewModel.appState = appState
            print("🔧 SandboxView: Set AppState in GroupsMapViewModel")
        }
    }
}

#Preview {
    SandboxView()
}
