import Foundation
import UserNotifications

let center = UNUserNotificationCenter.current()
center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
    if let error = error {
        print("❌ Error requesting notification permission: \(error)")
    } else {
        print("✅ Notification permission granted: \(granted)")
    }
    exit(0)
}

// Keep the process alive long enough to trigger the dialog
RunLoop.main.run(until: Date().addingTimeInterval(2))