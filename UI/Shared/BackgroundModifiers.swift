import SwiftUI

// MARK: - Reusable Background View Modifiers

extension View {
    /// Standard overlay background with black opacity
    func overlayBackground(opacity: Double = 0.8) -> some View {
        self.background(Color.black.opacity(opacity))
    }
    
    /// Standard blue background with opacity
    func blueBackground(opacity: Double = 0.1) -> some View {
        self.background(Color.blue.opacity(opacity))
    }
    
    /// Standard control background color
    func controlBackground() -> some View {
        self.background(Color(NSColor.controlBackgroundColor))
    }
    
    /// Semi-transparent background for overlays
    func semiTransparentBackground() -> some View {
        self.background(Color.black.opacity(0.3))
    }
    
    /// Dark overlay background for modals
    func modalBackground() -> some View {
        self.background(Color.black.opacity(0.7))
    }
}
