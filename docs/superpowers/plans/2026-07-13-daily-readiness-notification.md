# Daily Readiness Notification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Post a local notification each morning showing today's freshly-computed readiness ("Readiness 82 · Push day"), driven by a background refresh, with a Settings toggle + time picker.

**Architecture:** iOS-only. A `BGAppRefreshTask` wakes the app in the morning, runs the existing `SyncService.syncNow` (HealthKit → backend → `GET /v1/today`), and — only if the returned score is for today — posts a local notification via a new `NotificationService`. Settings gains a toggle and time picker; nothing schedules or requests permission until enabled.

**Tech Stack:** SwiftUI (iOS 17), `UserNotifications`, `BackgroundTasks` (`BGTaskScheduler` + SwiftUI `.backgroundTask(.appRefresh:)`). No backend, no new dependencies.

## Global Constraints

- **iOS presentation/plumbing only. No backend change, no push server, no APNs, no DTO change.** Reuse `SyncService.syncNow`; consume the existing `TodayDTO { date: String, readiness: Double, decision: Decision, calibrating: Bool, confidence: String, isLowConfidence: Bool }`.
- **The deterministic score owns the decision.** The notification only *displays* `readiness`/`decision`; it never computes or overrides.
- **Off by default.** No scheduling and no permission request until the user turns the toggle on.
- **Fresh-only.** Post **only** when the synced `today.date` (first 10 chars) equals the local calendar today. Never post a stale number. If iOS doesn't wake the app, no notification that day — surfaced by a caveat caption in Settings.
- **Background task identifier (verbatim, must match across Info.plist, service, and the `.backgroundTask` modifier):** `com.readinesscoach.morningReadiness`.
- **Notification identifier (verbatim):** `daily-readiness`.
- **Defaults:** notifications off; time 07:00 (`notificationHour = 7`, `notificationMinute = 0`).
- **Low-confidence hedge:** when `today.isLowConfidence || today.calibrating`, the body is exactly `"Limited data today — tap for details."`; otherwise the body is `today.decision.meaning`.
- **The project is file-system-synchronized (objectVersion 77):** new `.swift` files under `ios/ReadinessCoach/` are auto-included — do NOT edit `project.pbxproj`.
- **No iOS test target** (consistent with prior iOS features). Verification is the simulator build below plus the manual/debugger checks each task names. Do NOT create a test target.
- **Build command (verbatim), run from repo root (`/Users/shawngeorgie/readiness-coach`):**
  `xcodebuild -project ios/ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
- **Headless SourceKit false positives:** single-file diagnostics may report "cannot find type X in scope" for module types (AppSettings, TodayDTO, SyncService, etc.). The whole-module `xcodebuild` build is authoritative.

---

### Task 1: AppSettings — notification preferences

**Files:**
- Modify: `ios/ReadinessCoach/Settings/AppSettings.swift`

**Interfaces:**
- Produces: `AppSettings.notificationsEnabled: Bool`, `.notificationHour: Int`, `.notificationMinute: Int` — all `@Published`, UserDefaults-backed.

- [ ] **Step 1: Add the three published properties**

In `AppSettings.swift`, after the `hasCompletedOnboarding` published property (the block ending at its `}` around line 14), add:

```swift
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }
    @Published var notificationHour: Int {
        didSet { defaults.set(notificationHour, forKey: Keys.notificationHour) }
    }
    @Published var notificationMinute: Int {
        didSet { defaults.set(notificationMinute, forKey: Keys.notificationMinute) }
    }
```

- [ ] **Step 2: Initialize them in `init`**

In `init(defaults:)`, after `self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)`, add:

```swift
        self.notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        self.notificationHour = (defaults.object(forKey: Keys.notificationHour) as? Int) ?? 7
        self.notificationMinute = defaults.integer(forKey: Keys.notificationMinute)
```

(`notificationMinute` defaults to 0, which is `integer(forKey:)`'s natural default; `notificationHour` must default to 7 when unset, hence the `object(forKey:) as? Int ?? 7`.)

- [ ] **Step 3: Add the keys**

In the `private enum Keys` block, after `static let lastSync = "lastSyncAt"`, add:

```swift
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationHour = "notificationHour"
        static let notificationMinute = "notificationMinute"
```

- [ ] **Step 4: Verify it builds**

Run: `xcodebuild -project ios/ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/ReadinessCoach/Settings/AppSettings.swift
git commit -m "feat(ios): persist daily-notification preferences in AppSettings"
```

---

### Task 2: NotificationService

**Files:**
- Create: `ios/ReadinessCoach/Services/NotificationService.swift`

**Interfaces:**
- Consumes: `TodayDTO` (fields `date`, `readiness`, `decision`, `calibrating`, `isLowConfidence`), `Decision.title`, `Decision.meaning`.
- Produces: `final class NotificationService` with `requestAuthorization() async -> Bool`, `authorizationStatus() async -> UNAuthorizationStatus`, `postReadiness(_ today: TodayDTO)`, `cancelPending()`.

- [ ] **Step 1: Create the file**

Create `ios/ReadinessCoach/Services/NotificationService.swift`:

```swift
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
```

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild -project ios/ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/ReadinessCoach/Services/NotificationService.swift
git commit -m "feat(ios): NotificationService for the daily readiness alert"
```

---

### Task 3: Background refresh service, Info.plist, and app wiring

**Files:**
- Create: `ios/ReadinessCoach/Services/BackgroundRefreshService.swift`
- Modify: `ios/Info.plist`
- Modify: `ios/ReadinessCoach/ReadinessCoachApp.swift`
- Modify: `ios/ReadinessCoach/Views/RootView.swift`

**Interfaces:**
- Consumes: `AppSettings` (`notificationsEnabled`, `notificationHour`, `notificationMinute`), `SyncService` (`syncNow`, `today`), `NotificationService` (`authorizationStatus`, `postReadiness`), `TodayDTO.date`.
- Produces: `enum BackgroundRefreshService` with `static let taskID`, `static func schedule(for:)`, `static func cancel()`, `@MainActor static func handle(settings:sync:notifications:) async`.

- [ ] **Step 1: Create `BackgroundRefreshService.swift`**

Create `ios/ReadinessCoach/Services/BackgroundRefreshService.swift`:

```swift
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
```

- [ ] **Step 2: Add background keys to `Info.plist`**

In `ios/Info.plist`, replace:

```xml
	</dict>
</dict>
</plist>
```

with:

```xml
	</dict>
	<key>BGTaskSchedulerPermittedIdentifiers</key>
	<array>
		<string>com.readinesscoach.morningReadiness</string>
	</array>
	<key>UIBackgroundModes</key>
	<array>
		<string>fetch</string>
		<string>processing</string>
	</array>
</dict>
</plist>
```

(This inserts the two keys after the `NSAppTransportSecurity` dict's closing `</dict>` and before the root dict's closing `</dict>`. Use tab indentation to match the file.)

- [ ] **Step 3: Register the background task in the App scene**

Replace the whole body of `ios/ReadinessCoach/ReadinessCoachApp.swift` with:

```swift
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
```

> **If the build reports a concurrency error** about capturing non-`Sendable` `AppSettings`/`SyncService` in the `@Sendable` `.backgroundTask` closure (only under strict-concurrency mode): resolve it minimally without changing behavior — mark `final class AppSettings` as `@unchecked Sendable` (it is UserDefaults-backed and effectively serial), keeping the capture. Do NOT restructure the flow. If the build already succeeds (Swift 5 mode, warnings only), leave it as written.

- [ ] **Step 4: Schedule from RootView's lifecycle**

In `ios/ReadinessCoach/Views/RootView.swift`, replace the `MainTabView()` block inside `if settings.isReady`:

```swift
            MainTabView()
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await sync.autoSync(settings) } }
                }
                .task { await sync.autoSync(settings) }
```

with:

```swift
            MainTabView()
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await sync.autoSync(settings) } }
                    else if phase == .background { BackgroundRefreshService.schedule(for: settings) }
                }
                .task {
                    await sync.autoSync(settings)
                    BackgroundRefreshService.schedule(for: settings)
                }
```

- [ ] **Step 5: Verify it builds**

Run: `xcodebuild -project ios/ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/ReadinessCoach/Services/BackgroundRefreshService.swift ios/Info.plist ios/ReadinessCoach/ReadinessCoachApp.swift ios/ReadinessCoach/Views/RootView.swift
git commit -m "feat(ios): morning background refresh that posts the readiness notification"
```

---

### Task 4: Settings UI — toggle, time picker, permission flow

**Files:**
- Modify: `ios/ReadinessCoach/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `AppSettings` (`notificationsEnabled`, `notificationHour`, `notificationMinute`), `NotificationService.requestAuthorization()`, `BackgroundRefreshService.schedule(for:)` / `.cancel()`.

- [ ] **Step 1: Add a NotificationService instance and denied-state to `SettingsView`**

In `SettingsView`, after `@State private var isDeleting = false`, add:

```swift
    @State private var notificationDenied = false
    private let notifications = NotificationService()
```

- [ ] **Step 2: Add the "Daily readiness" section**

In the `Form`, immediately after the `Section("Sync") { … }` block's closing `}` (before `Section("Data & privacy")`), add:

```swift
                Section("Daily readiness") {
                    Toggle("Morning notification", isOn: Binding(
                        get: { settings.notificationsEnabled },
                        set: { isOn in
                            if isOn {
                                Task {
                                    let granted = await notifications.requestAuthorization()
                                    if granted {
                                        settings.notificationsEnabled = true
                                        notificationDenied = false
                                        BackgroundRefreshService.schedule(for: settings)
                                    } else {
                                        settings.notificationsEnabled = false
                                        notificationDenied = true
                                    }
                                }
                            } else {
                                settings.notificationsEnabled = false
                                notificationDenied = false
                                BackgroundRefreshService.cancel()
                                notifications.cancelPending()
                            }
                        }
                    ))

                    if settings.notificationsEnabled {
                        DatePicker("Time", selection: notificationTime, displayedComponents: .hourAndMinute)
                    }

                    if notificationDenied {
                        Text("Turn on notifications for Readiness Coach in iOS Settings to use this.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Text("Sent in the morning after your data syncs. iOS decides the exact time, so some mornings it may arrive late or not at all.")
                        .font(.caption).foregroundStyle(.secondary)
                }
```

- [ ] **Step 3: Add the time binding helper**

In `SettingsView`, add this computed property (e.g. after the `deleteAccount()` method):

```swift
    /// Bridges the stored hour/minute to a `DatePicker` Date, rescheduling on change.
    private var notificationTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: settings.notificationHour,
                    minute: settings.notificationMinute,
                    second: 0, of: Date()
                ) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings.notificationHour = c.hour ?? 7
                settings.notificationMinute = c.minute ?? 0
                BackgroundRefreshService.schedule(for: settings)
            }
        )
    }
```

- [ ] **Step 4: Verify it builds**

Run: `xcodebuild -project ios/ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual behavioral check (device — background refresh & HealthKit don't run on Simulator)**

- Toggle "Morning notification" on → iOS permission prompt appears; granting keeps it on and shows the time picker + caveat caption.
- Denying reverts the toggle and shows the "Turn on notifications … in iOS Settings" hint.
- With it on, change the time → no crash (a new BG request is scheduled).
- Trigger the handler via the Xcode debugger while paused:
  `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.readinesscoach.morningReadiness"]`
  → a "Readiness N · … day" notification appears with today's number (hedged body when low-confidence).
- Toggle off → `cancelPending` clears it and no further notifications schedule.

- [ ] **Step 6: Commit**

```bash
git add ios/ReadinessCoach/Views/SettingsView.swift
git commit -m "feat(ios): Settings toggle and time picker for the daily notification"
```

---

## Self-Review Notes

- **Spec coverage:** prefs persistence → Task 1; NotificationService (content rules, once-per-day guard, permission) → Task 2; BGAppRefresh scheduling/handle + Info.plist background modes + app registration + lifecycle scheduling → Task 3; Settings toggle/time/permission-flow/caveat → Task 4.
- **Identifier consistency:** `com.readinesscoach.morningReadiness` appears identically in the Global Constraints, Task 3 service (`taskID`), Info.plist `BGTaskSchedulerPermittedIdentifiers`, and the `.backgroundTask(.appRefresh(...))` modifier. Notification identifier `daily-readiness` is defined once in `NotificationService`.
- **Type consistency:** `handle` reads `sync.today` (`TodayDTO?`) and compares `String(today.date.prefix(10))` to `localToday()`; `postReadiness` uses `today.isLowConfidence`/`today.calibrating`/`today.decision.title`/`today.decision.meaning`, all confirmed to exist.
- **Fresh-only / off-by-default:** `schedule` and `handle` both guard on `notificationsEnabled`; `handle` also re-checks `.authorized` and the same-day date before posting.
