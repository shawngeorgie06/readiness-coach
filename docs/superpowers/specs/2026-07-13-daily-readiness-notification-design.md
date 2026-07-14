# Daily Readiness Notification — Design

**Date:** 2026-07-13
**Layer:** iOS only — no backend change (all endpoints already exist).

## Goal

Deliver a local notification each morning showing the user's readiness for
today ("Readiness 82 · Push day"), so they get the day's call without opening
the app. The number must always be a real, computed-that-morning score —
never a stale one.

## Approach (decisions locked in brainstorming)

- **Fresh-only.** A background task wakes the app in the morning, runs the
  existing sync (HealthKit → backend → `GET /v1/today`), and posts the
  notification **only** if the returned score is for today's calendar date. If
  iOS does not wake the app that morning, no notification is sent that day —
  a stale number is never shown. This reliability caveat is surfaced in the
  Settings UI.
- **User-configurable time.** A time picker in Settings (default 07:00) sets
  the target the background refresh is scheduled against. iOS controls the
  exact wake time; the target is the `earliestBeginDate`, not a guarantee.
- **Low-confidence → send with a hedge.** When the fresh score is low-confidence
  or calibrating, still notify, but replace the body with "Limited data today —
  tap for details."
- **Background-only posting (v1).** The notification is posted only from the
  background-refresh path. If the app is already foregrounded, the user simply
  sees Today; no notification fires.

## Non-Goals / Invariants

- **No backend change**, no push server, no APNs. Local notifications only.
- **The deterministic score owns the decision.** The notification only
  *displays* the server's `readiness`/`decision`; it never computes or
  overrides anything.
- **Read-only HealthKit, no Watch app, no local LLM** — untouched.
- Off by default; nothing is scheduled and no permission is requested until
  the user enables the toggle.

## Components

### 1. `NotificationService` (new, `ios/ReadinessCoach/Services/NotificationService.swift`)
- `requestAuthorization() async -> Bool` — wraps `UNUserNotificationCenter`
  `.requestAuthorization([.alert, .sound])`; returns granted.
- `authorizationStatus() async -> UNAuthorizationStatus` — for the Settings UI
  to show a "denied — enable in iOS Settings" hint.
- `postReadiness(_ today: TodayDTO)` — builds and delivers a local notification
  **immediately** (a `UNNotificationRequest` with `nil` trigger). Title
  `"Readiness {Int(readiness)} · {Decision.title} day"`. Body: `today.decision.meaning`,
  or `"Limited data today — tap for details."` when `today.isLowConfidence ||
  today.calibrating`. Stable identifier `"daily-readiness"` (replaces any prior).
- **Once-per-day guard:** stores the last-notified `yyyy-MM-dd` (local) in
  UserDefaults; `postReadiness` no-ops if already posted for that day. Prevents
  double-posting across repeated background wakes.

### 2. `BackgroundRefreshService` (new, `ios/ReadinessCoach/Services/BackgroundRefreshService.swift`)
- Task identifier constant: `com.readinesscoach.morningReadiness`.
- `schedule(for settings: AppSettings)` — submits a `BGAppRefreshTaskRequest`
  with `earliestBeginDate` = the next occurrence (from now, local) of the
  configured hour/minute. No-op when notifications are disabled. Cancels any
  existing request first (`BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)`,
  then re-submit) so a changed time takes effect.
- `handle(settings:sync:notifications:) async` — the work run when the task
  fires: `await sync.syncNow(settings)`, then read `sync.today`; if
  `today.date` equals the local calendar today, call
  `notifications.postReadiness(today)`. Always calls `schedule(for:)` again at
  the end to queue tomorrow. Guards: if notifications got disabled or
  permission was revoked, skip posting.
- Registration uses the SwiftUI scene modifier
  `.backgroundTask(.appRefresh(BackgroundRefreshService.taskID)) { … }` (iOS 16+),
  which handles task completion and cancellation; the closure calls `handle`.

### 3. `AppSettings` additions
- `notificationsEnabled: Bool` (default `false`), persisted like existing keys.
- `notificationHour: Int` (default `7`) and `notificationMinute: Int` (default `0`).
- New keys added to the existing `Keys` enum, following the current
  `didSet { defaults.set(...) }` pattern.

### 4. `SettingsView` additions
- A "Daily readiness" section: a toggle bound to `notificationsEnabled` and,
  when on, a `DatePicker(.hourAndMinute)` bound to the hour/minute.
- Turning the toggle **on** calls `NotificationService.requestAuthorization()`;
  if granted, `BackgroundRefreshService.schedule(for:)` is called; if denied,
  the toggle reverts and a hint appears ("Enable notifications for Readiness
  Coach in iOS Settings").
- Changing the time re-schedules. Turning **off** cancels the scheduled task
  (`BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)`) and
  removes pending notifications.
- A caption states the freshness caveat: "Sent in the morning after your data
  syncs. iOS decides the exact time, so some mornings it may arrive late or not
  at all."

### 5. `Info.plist`
- `BGTaskSchedulerPermittedIdentifiers` = `[com.readinesscoach.morningReadiness]`.
- `UIBackgroundModes` = `[fetch, processing]`.

### 6. App wiring (`ReadinessCoachApp`)
- Add the `.backgroundTask(.appRefresh(…))` modifier to the `WindowGroup` scene,
  calling `BackgroundRefreshService.handle` with the shared `settings`, `sync`,
  and a `NotificationService`.
- On launch and on entering background (via `scenePhase`), call
  `BackgroundRefreshService.schedule(for: settings)` so a request is always
  queued when notifications are enabled.

## Notification content rules

| Condition | Title | Body |
|-----------|-------|------|
| Normal | `Readiness 82 · Push day` | `You're recovered — a hard session is on the table.` (`decision.meaning`) |
| Low-confidence / calibrating | `Readiness 33 · Recover day` | `Limited data today — tap for details.` |

Tapping the notification launches the app (default) to Today — no custom
deep-link routing needed for v1 since Today is the launch tab.

## Edge cases

- **Permission denied / revoked:** never schedule; Settings shows the hint and
  keeps the toggle off. `handle` re-checks authorization before posting.
- **iOS never wakes the app:** no notification that day (accepted per
  fresh-only). Documented in the Settings caption.
- **Score not for today** (`today.date != local today`, e.g. sync failed or
  returned yesterday): skip posting; still reschedule.
- **Multiple wakes / foreground + background same day:** once-per-day guard
  prevents duplicates.
- **Not configured / no client:** `syncNow` already no-ops without a client;
  `handle` then sees no fresh `today` and skips.

## Verification

- iOS builds for the Simulator (`xcodebuild … -sdk iphonesimulator
  CODE_SIGNING_ALLOWED=NO build`) and for device. No iOS test target (consistent
  with prior iOS features).
- **Simulator cannot** run BGAppRefresh or HealthKit; exercise the background
  handler with the Xcode debugger's
  `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.readinesscoach.morningReadiness"]`.
- **Device manual pass:** enable the toggle → grant permission → simulate a
  launch (or wait) → confirm a "Readiness N · … day" notification appears with
  the correct number; toggle off → confirm no further notifications; deny
  permission → confirm the hint shows and nothing schedules.
