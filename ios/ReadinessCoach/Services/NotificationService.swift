import Foundation
import UserNotifications

/// Schedules the daily readiness notification as a repeating local calendar
/// notification. iOS delivers it at the chosen time on its own — no background
/// execution — so it fires reliably. Because the text is fixed when scheduled,
/// it shows the LATEST synced score (honestly labeled, may predate this
/// morning's sync); the app refreshes it on each foreground so it stays current.
final class NotificationService {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    private static let identifier = "daily-readiness"

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Schedule (or replace) the repeating daily notification per current
    /// settings. Cancels it when notifications are disabled. Re-adding with the
    /// same identifier replaces the pending request, refreshing time + content
    /// without skipping a day.
    func refreshDailySchedule(settings: AppSettings, latest: TodayDTO?) {
        guard settings.notificationsEnabled else { cancelDaily(); return }
        Task {
            let status = await authorizationStatus()
            guard status == .authorized || status == .provisional else {
                cancelDaily()
                return
            }
            scheduleDaily(
                hour: settings.notificationHour,
                minute: settings.notificationMinute,
                latest: latest
            )
        }
    }

    /// Schedule the repeating daily notification at hour:minute. Content shows
    /// the latest known score ("Latest …", never asserted as today's), or a
    /// generic prompt when no score is known yet.
    func scheduleDaily(hour: Int, minute: Int, latest: TodayDTO?) {
        let content = UNMutableNotificationContent()
        if let today = latest {
            content.title = "Latest readiness \(Int(today.readiness.rounded())) · \(today.decision.title)"
            content.body = "Tap for today's up-to-date score."
        } else {
            content.title = "Readiness Coach"
            content.body = "Your readiness for today is ready — tap to check in."
        }
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)
        center.add(request)
    }

    func cancelDaily() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }
}
