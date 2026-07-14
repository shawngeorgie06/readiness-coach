import Foundation
import BackgroundTasks

/// Schedules and runs the morning background refresh behind the daily readiness
/// notification. Posts only a freshly-computed, same-day score.
enum BackgroundRefreshService {
    static let taskID = "com.readinesscoach.morningReadiness"

    /// Queues the next refresh at the user's configured time. No-op when disabled.
    static func schedule(for settings: AppSettings) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
        guard settings.notificationsEnabled else { return }

        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = nextRun(hour: settings.notificationHour, minute: settings.notificationMinute)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
    }

    /// One refresh: sync, then post the notification only if today's score is fresh.
    /// Always re-queues tomorrow's request.
    @MainActor
    static func handle(settings: AppSettings, sync: SyncService, notifications: NotificationService) async {
        defer { schedule(for: settings) }
        guard settings.notificationsEnabled else { return }
        guard await notifications.authorizationStatus() == .authorized else { return }

        await sync.syncNow(settings)
        guard let today = sync.today, String(today.date.prefix(10)) == localToday() else { return }
        notifications.postReadiness(today)
    }

    /// Next strictly-future occurrence of hour:minute in local time.
    private static func nextRun(hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(24 * 60 * 60)
    }

    private static func localToday() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar.current
        f.timeZone = .current
        return f.string(from: Date())
    }
}
