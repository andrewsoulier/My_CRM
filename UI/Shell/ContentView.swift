import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataProvider: SQLiteDataProvider
    @EnvironmentObject var dragDropManager: DragDropManager
    @EnvironmentObject var selectionManager: SelectionManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Error Banner at the top
            if appState.showingError && appState.messageType == .error, let errorMessage = appState.lastError {
                ErrorBanner(message: errorMessage) {
                    appState.clearError()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1001) // Above everything else
            }
            
            HStack(spacing: 0) {
                // Page Navigation Bar (far left)
                if appState.isPageNavBarVisible {
                    PageNavBarView()
                        .frame(width: 260)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    // Icon in top right corner to re-expand navigation bar
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    appState.togglePageNavBar()
                                }
                            }) {
                                Image(systemName: "sidebar.left")
                                    .font(.title2)
                                    .foregroundColor(.primary)
                                    .padding(12)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 8)
                            .padding(.top, 8)
                        }
                        Spacer()
                    }
                    .frame(width: 40)
                    .background(getCollapsedSidebarColor(index: 0))
                    .allowsHitTesting(true)
                    .zIndex(1000) // Ensure it's above the canvas
                }
                
                // Note: Contacts and Groups are now integrated into PageNavBarView
                
                // Workspace (center) with canvas panning
                WorkspaceView()
                    .environmentObject(dataProvider)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))
                    .zIndex(1) // Lower z-index so navigation bars are above
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isPageNavBarVisible)
        .animation(.easeInOut(duration: 0.3), value: appState.showingError)
        .onTapGesture {
            // Global click handler to unfocus search bar when clicking anywhere
            // This will be handled by the search bar's focus state
            NotificationCenter.default.post(name: NSNotification.Name("UnfocusSearchBar"), object: nil)
        }
        .onAppear {
            setupNavigationNotifications()
        }
        .alert(appState.messageType.title, isPresented: Binding(
            get: { appState.showingError && appState.messageType == .message },
            set: { if !$0 { appState.clearError() } }
        )) {
            Button("OK") {
                appState.clearError()
            }
        } message: {
            Text(appState.lastError ?? "An unknown error occurred")
        }
        .sheet(isPresented: $appState.showingSettings) {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(dataProvider)
        }
    }
    
    private func getCollapsedSidebarColor(index: Int) -> Color {
        let baseColor = Color(NSColor.controlColor)
        let darkeningFactor = Double(index) * 0.05 // 5% darker for each subsequent sidebar
        
        // Create a darker version of the base color
        return baseColor.opacity(1.0 + darkeningFactor)
    }
    
    private func setupNavigationNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ToggleNavigationBars"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
                    appState.togglePageNavBar()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(SQLiteDataProvider())
        .environmentObject(DragDropManager())
        .environmentObject(SelectionManager())
        .environmentObject(HotkeyManager())
}
