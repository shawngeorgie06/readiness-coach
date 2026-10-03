import SwiftUI

/// Hosted unit tests must not read live account state or start Health/network work.
enum AppLaunch {
    static var isUnitTestHost: Bool {
        isUnitTestHost(environment: ProcessInfo.processInfo.environment,
                       hasXCTest: NSClassFromString("XCTestCase") != nil)
    }

    static func isUnitTestHost(environment: [String: String], hasXCTest: Bool) -> Bool {
        hasXCTest || ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]
            .contains { environment[$0]?.isEmpty == false }
    }
}

@main
struct ReadinessCoachApp: App {
    var body: some Scene {
        WindowGroup {
            if AppLaunch.isUnitTestHost {
                Color.clear
            } else {
                LiveAppRoot()
            }
        }
    }
}

private struct LiveAppRoot: View {
    @StateObject private var settings = AppSettings()
    @StateObject private var sync = SyncService()

    var body: some View {
        RootView()
            .environmentObject(settings)
            .environmentObject(sync)
    }
}
