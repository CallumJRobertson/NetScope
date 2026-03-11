import Foundation
import UserNotifications

@MainActor
final class AlertNotifier {
    private var hasRequestedAuthorization = false

    func sendHighUsageAlert(appName: String, rateMbps: Double) {
        guard rateMbps > 0 else {
            return
        }

        Task {
            let center = UNUserNotificationCenter.current()
            if !hasRequestedAuthorization {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                hasRequestedAuthorization = true
            }

            let content = UNMutableNotificationContent()
            content.title = "High Bandwidth Usage"
            content.body = "\(appName) is using \(String(format: "%.1f", rateMbps)) Mbps"
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
