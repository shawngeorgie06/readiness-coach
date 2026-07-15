import Foundation
import UserNotifications

/// Requests permission for and delivers the daily local readiness notification.
final class NotificationService {
    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter

    init(defaults: UserDefaults = .standard, center: UNUserNotificationCenter = .current()) {
        self.defaults = defaults
        self.center = center
    }

    private enum Keys { static let lastNotifiedDay = "lastReadinessNotifiedDay" }
    private static let identifier = "daily-readiness"

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Delivers today's readiness immediately, at most once per local calendar day.
    func postReadiness(_ today: TodayDTO) {
        let dayKey = String(today.date.prefix(10))
        guard defaults.string(forKey: Keys.lastNotifiedDay) != dayKey else { return }

        let content = UNMutableNotificationContent()
        content.title = "Readiness \(Int(today.readiness.rounded())) · \(today.decision.title) day"
        content.body = (today.isLowConfidence || today.calibrating)
            ? "Limited data today — tap for details."
            : today.decision.meaning
        content.sound = .default

        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: nil)
        center.add(request)
        defaults.set(dayKey, forKey: Keys.lastNotifiedDay)
    }

    func cancelPending() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }
}
