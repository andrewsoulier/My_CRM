import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var globalCanvasService: GlobalCanvasService
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    
    var body: some View {
        Group {
            switch appState.selectedPage {
            case .peopleMaps:
                SimplifiedCanvasView(
                    viewModel: globalCanvasService.groupsMapViewModel, 
                    gestureCoordinator: globalCanvasService.gestureCoordinator,
                    edgeScrollingManager: globalCanvasService.edgeScrollingManager
                )
            case .gridView:
                GridViewPage()
            case .deckBuilder:
                DeckBuilderView()
            case .canvasManagement:
                CanvasManagementView()
            case .smartLists:
                CanvasWrapperView {
                    PlaceholderView(title: "Smart Lists", description: "Create and manage smart contact lists based on criteria")
                }
            case .timeline:
                CanvasWrapperView {
                    PlaceholderView(title: "Timeline View", description: "View contact interactions and history over time")
                }
            case .flashcardTrainer:
                CanvasWrapperView {
                    PlaceholderView(title: "Flashcard Trainer", description: "Train your memory with contact flashcards")
                }
            case .quickSend:
                QuickSendView()
            case .engagementDashboard:
                CanvasWrapperView {
                    PlaceholderView(title: "Engagement Dashboard", description: "Track and visualize your contact engagement")
                }
            case .automationsManager:
                CanvasWrapperView {
                    PlaceholderView(title: "Automations Manager", description: "Create and manage contact automation workflows")
                }
            case .tagManager:
                CanvasWrapperView {
                    PlaceholderView(title: "Tag Manager", description: "Organize contacts with custom tags")
                }
            case .groupsAndCircles:
                CanvasWrapperView {
                    PlaceholderView(title: "Groups & Circles", description: "Manage contact groups and relationship circles")
                }
            case .importSync:
                CanvasWrapperView {
                    PlaceholderView(title: "Import/Sync", description: "Import contacts and sync with external services")
                }
            case .settings:
                SettingsView()
                    .environmentObject(appState)
                    .environmentObject(dataProvider)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                    // Connect HotkeyManager to canvas components
                    hotkeyManager.setCanvasComponents(viewModel: globalCanvasService.groupsMapViewModel, gestureCoordinator: globalCanvasService.gestureCoordinator)
                    
                    // Set AppState in HotkeyManager for focus detection
                    hotkeyManager.setAppState(appState)
                    
                    // Set AppState in viewModel for debug settings access
                    globalCanvasService.groupsMapViewModel.appState = appState
                    
                    // Set dataProvider for contact lookups
                    globalCanvasService.setDataProvider(dataProvider)
                    
                    // Refresh contact data now that dataProvider is available
                    globalCanvasService.groupsMapViewModel.refreshContactData()
                }
                .onChange(of: appState.selectedPage) { oldPage, newPage in
                    // Release search bar focus when switching to canvas page
                    if newPage == .peopleMaps {
                        NotificationCenter.default.post(name: NSNotification.Name("UnfocusSearchBar"), object: nil)
                    } else {
                        hotkeyManager.enableNavHotkeys()
                    }
                    
                    // When switching to grid view, ensure filters are loaded
                    if newPage == .gridView {
                        // The GridViewPage will handle loading filters when it appears
                        // This is just a placeholder for future enhancements if needed
                    }
                }
    }
}

struct CanvasWrapperView<Content: View>: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var selectionManager: SelectionManager
    @State private var isPanning = false
    
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .offset(x: appState.canvasOffset.x, y: appState.canvasOffset.y)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        handleCanvasDrag(value)
                    }
                    .onEnded { _ in
                        isPanning = false
                    }
            )
            .onTapGesture {
                // Clear selection when tapping on empty canvas (but not with modifiers)
                if !isPanning && !NSEvent.modifierFlags.contains(.shift) && !NSEvent.modifierFlags.contains(.command) {
                    selectionManager.clearAllSelections()
                }
            }
    }
    
    private func handleCanvasDrag(_ value: DragGesture.Value) {
        // Handle canvas panning
        let translation = value.translation
        appState.canvasOffset = CGPoint(
            x: appState.canvasOffset.x + translation.width,
            y: appState.canvasOffset.y + translation.height
        )
        isPanning = true
    }
}

struct PlaceholderView: View {
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.title)
                .fontWeight(.bold)
            
            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Text("Coming Soon")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

#Preview {
    WorkspaceView()
        .environmentObject(AppState())
}
