import SwiftUI

enum AppBuild {
    /// Bump when shipping device-visible UI fixes — shown on Today so you can confirm the install.
    static let stamp = "1.1.0"
}

@main
struct ReadinessCoachApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var sync = SyncService()
    private let notifications = NotificationService()

    init() {
        ScrollLockBootstrap.apply()
    }

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
