import Foundation
import UserNotifications

/// Dispatches macOS user notifications for surfaced errors and status updates.
@MainActor
final class SystemNotificationDispatcher {
    static let shared = SystemNotificationDispatcher()
    
    private init() {}
    
    /// Posts a notification to Notification Center with the provided title and body.
    func post(title: String, body: String, identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "gridview.\(identifier)",
            content: content,
            trigger: nil
        )
        
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                LogManager.shared.error("❌ Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }
}

