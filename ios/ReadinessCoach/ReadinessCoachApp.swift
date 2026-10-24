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
    init() {
        if !AppLaunch.isUnitTestHost { PerfSignpost.beginLaunch() }
    }

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
    @State private var store: AppStore
    @StateObject private var sync: SyncService

    init() {
        let store = AppStore(cache: StoreActivation.cache)
        _store = State(initialValue: store)
        _sync = StateObject(wrappedValue: SyncService(store: store))
    }

    var body: some View {
        RootView()
            .environmentObject(settings)
            .environmentObject(sync)
            .environment(store)
            .onAppear(perform: activateStore)
            .onChange(of: settings.userId) { _, _ in activateStore() }
            .onChange(of: settings.isReady) { _, _ in activateStore() }
    }

    private func activateStore() {
        StoreActivation.activate(store, settings: settings)
    }
}
