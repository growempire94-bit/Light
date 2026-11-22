import Foundation
import UserNotifications

enum NotificationManager {
    /// Category of the "light is on" notification; has a "turn off alarm" button.
    static let alarmCategory = "LIGHT_ON"
    static let stopAlarmAction = "STOP_ALARM"

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func registerCategories() {
        let stop = UNNotificationAction(identifier: stopAlarmAction,
                                        title: "🔕 Выключить сигнал",
                                        options: [])
        let category = UNNotificationCategory(identifier: alarmCategory,
                                              actions: [stop],
                                              intentIdentifiers: [],
                                              options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func post(title: String, body: String, category: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        if let category {
            content.categoryIdentifier = category
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Show notifications as banners even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// Tapping the "light is on" notification, or its "turn off" button, stops the siren.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.categoryIdentifier == NotificationManager.alarmCategory {
            DispatchQueue.main.async {
                AudioManager.shared.stopAlarm()
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }
}
