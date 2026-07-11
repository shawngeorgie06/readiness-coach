import SwiftUI

@main
struct ReadinessCoachApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var sync = SyncService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(sync)
        }
    }
}
