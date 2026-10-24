import Foundation
import OSLog

/// Measurement hooks for launch-to-Today and tab-switch latency. Each interval
/// is an `OSSignposter` interval (visible in Instruments) and also logs
/// `perf <name> <ms>ms` so `log stream` can read it. End calls are idempotent:
/// only the first call after a matching begin records anything.
enum PerfSignpost {
    private static let subsystem = "com.readinesscoach.ReadinessCoach"
    private static let signposter = OSSignposter(subsystem: subsystem, category: "perf")
    private static let logger = Logger(subsystem: subsystem, category: "perf")

    private struct Active {
        let name: String
        let state: OSSignpostIntervalState
        let start: ContinuousClock.Instant
    }

    private static let lock = NSLock()
    private static var launch: Active?
    private static var tabSwitch: (tab: String, active: Active)?

    static func beginLaunch() {
        lock.lock(); defer { lock.unlock() }
        launch = Active(name: "LaunchToToday", state: signposter.beginInterval("LaunchToToday"), start: .now)
    }

    static func endLaunchIfNeeded() {
        lock.lock()
        let active = launch
        launch = nil
        lock.unlock()
        finish(active)
    }

    static func beginTabSwitch(to tab: String) {
        lock.lock()
        let previous = tabSwitch?.active
        tabSwitch = (tab, Active(name: "TabSwitch.\(tab)", state: signposter.beginInterval("TabSwitch"), start: .now))
        lock.unlock()
        // A switch abandoned before content appeared is closed without a log line.
        if let previous { signposter.endInterval("TabSwitch", previous.state) }
    }

    static func endTabSwitchIfNeeded(tab: String) {
        lock.lock()
        let current = tabSwitch
        if current?.tab == tab { tabSwitch = nil }
        lock.unlock()
        guard let current, current.tab == tab else { return }
        finish(current.active)
    }

    private static func finish(_ active: Active?) {
        guard let active else { return }
        signposter.endInterval(active.name == "LaunchToToday" ? "LaunchToToday" : "TabSwitch", active.state)
        let elapsed = active.start.duration(to: .now)
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        let line = "perf \(active.name) \(String(format: "%.1f", ms))ms"
        logger.notice("\(line, privacy: .public)")
    }
}
