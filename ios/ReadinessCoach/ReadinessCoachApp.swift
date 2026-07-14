import SwiftUI

@main
struct ReadinessCoachApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var sync = SyncService()
    private let notifications = NotificationService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(sync)
        }
        .backgroundTask(.appRefresh(BackgroundRefreshService.taskID)) {
            await BackgroundRefreshService.handle(settings: settings, sync: sync, notifications: notifications)
        }
    }
}
