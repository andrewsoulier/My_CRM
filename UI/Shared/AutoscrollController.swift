import SwiftUI
import AppKit

class AutoscrollController: ObservableObject {
    @Published var isScrolling = false
    private var scrollTimer: Timer?
    private var scrollView: NSScrollView?
    private var scrollDirection: ScrollDirection = .none
    private var scrollVelocity: CGFloat = 0
    
    init() {
        print("🚨 AutoscrollController.init() called")
    }
    
    enum ScrollDirection {
        case none, up, down, left, right
    }
    
    func attach(to scrollView: NSScrollView) {
        self.scrollView = scrollView
    }
    
    func onDragLocationChanged(_ location: CGPoint, in bounds: CGRect) {
        let edgeThreshold: CGFloat = 32
        let maxVelocity: CGFloat = 8
        
        // Determine scroll direction based on location
        let newDirection: ScrollDirection
        let newVelocity: CGFloat
        
        if location.y < bounds.minY + edgeThreshold {
            newDirection = .up
            newVelocity = maxVelocity * (1 - (location.y - bounds.minY) / edgeThreshold)
        } else if location.y > bounds.maxY - edgeThreshold {
            newDirection = .down
            newVelocity = maxVelocity * (1 - (bounds.maxY - location.y) / edgeThreshold)
        } else if location.x < bounds.minX + edgeThreshold {
            newDirection = .left
            newVelocity = maxVelocity * (1 - (location.x - bounds.minX) / edgeThreshold)
        } else if location.x > bounds.maxX - edgeThreshold {
            newDirection = .right
            newVelocity = maxVelocity * (1 - (bounds.maxX - location.x) / edgeThreshold)
        } else {
            newDirection = .none
            newVelocity = 0
        }
        
        // Update scroll state
        if newDirection != scrollDirection || newVelocity != scrollVelocity {
            scrollDirection = newDirection
            scrollVelocity = newVelocity
            
            if newDirection != .none {
                startScrolling()
            } else {
                stopScrolling()
            }
        }
    }
    
    private func startScrolling() {
        guard scrollTimer == nil else { return }
        
        isScrolling = true
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.performScroll()
        }
    }
    
    private func stopScrolling() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        isScrolling = false
    }
    
    private func performScroll() {
        guard let scrollView = scrollView else { return }
        
        let scrollAmount = scrollVelocity
        
        switch scrollDirection {
        case .up:
            scrollView.contentView.scroll(CGPoint(x: 0, y: scrollAmount))
        case .down:
            scrollView.contentView.scroll(CGPoint(x: 0, y: -scrollAmount))
        case .left:
            scrollView.contentView.scroll(CGPoint(x: scrollAmount, y: 0))
        case .right:
            scrollView.contentView.scroll(CGPoint(x: -scrollAmount, y: 0))
        case .none:
            break
        }
    }
    
    func cleanup() {
        stopScrolling()
        scrollView = nil
    }
}

// MARK: - SwiftUI Integration

struct AutoscrollModifier: ViewModifier {
    @StateObject private var autoscrollController = AutoscrollController()
    let onDragLocationChanged: (CGPoint) -> Void
    
    func body(content: Content) -> some View {
        content
            .background(
                AutoscrollViewRepresentable(autoscrollController: autoscrollController, onDragLocationChanged: onDragLocationChanged)
            )
    }
}

struct AutoscrollViewRepresentable: NSViewRepresentable {
    let autoscrollController: AutoscrollController
    let onDragLocationChanged: (CGPoint) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        
        // Find the scroll view in the view hierarchy
        DispatchQueue.main.async {
            if let scrollView = findScrollView(in: view) {
                autoscrollController.attach(to: scrollView)
            }
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Update if needed
    }
    
    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        
        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }
        
        return nil
    }
}

extension View {
    func autoscroll(onDragLocationChanged: @escaping (CGPoint) -> Void) -> some View {
        modifier(AutoscrollModifier(onDragLocationChanged: onDragLocationChanged))
    }
}
