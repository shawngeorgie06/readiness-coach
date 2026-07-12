# Readiness Coach — Usability v1 (design)

Date: 2026-07-11
Scope: iOS app only. No backend changes, no new capabilities/entitlements.

## Goal

Reduce friction across four areas the user flagged: setup/onboarding, syncing,
navigation, and clarity of the data. Single-user personal app.

## Decisions (locked)

- **Sync**: auto-sync on app open / return to foreground; manual button + pull-to-refresh remain.
- **Navigation**: 5 tabs — Today · Sleep · Train · Body · Trends. Ask Coach and
  Settings move off the tab bar to Today nav-bar buttons.
- **Delivery**: all four areas in one pass.

## 1. Onboarding

- Token field: `.textInputAutocapitalization(.never)` + `.autocorrectionDisabled()`
  + monospaced; fixes the observed auto-capitalize failure.
- Reduce visible fields to **API URL** and **API token**. User ID auto-generates
  (already does) and moves under a collapsible **Advanced** section.
- Prefill API URL from the last saved value.
- **Test connection** button: calls `GET /health` then a trial `GET /v1/today`;
  shows ✓/✗ inline. "Start & sync" stays enabled once URL+token are present, but
  the test gives confidence before leaving onboarding.

## 2. Syncing

- Add a shared app model driving sync. On `scenePhase == .active` (app open/foreground),
  trigger `syncNow` once, debounced so rapid foreground toggles don't double-sync.
- Today shows **"Last synced <relative>"** (e.g. "3m ago"), always visible; derived
  from `AppSettings.lastSyncAt`.
- Sync progress: while uploading, show "Uploading N samples…" (N from the payload
  count) instead of a bare spinner; on completion show the existing summary.
- Manual **Sync** button and pull-to-refresh unchanged.

## 3. Navigation

- `MainTabView`: 5 tabs — Today, Sleep, Train, Body, Trends. Removes the iOS
  "More" overflow entirely.
- **Ask Coach**: reachable from (a) a prominent button on the Today screen and
  (b) a chat icon in the Today nav bar. Presented via navigation push or sheet.
- **Settings**: gear icon in the Today nav bar (sheet or push). Sync-now lives in
  both Today and Settings.

## 4. Clarity of data

- **Decision meaning line** under the decision chip on Today: one plain sentence
  per decision (push/maintain/recover).
- **Tappable pillars**: tapping a pillar row opens a sheet with what it measures,
  its weight (Sleep 35% / Recovery 40% / Load 25%), and today's drivers.
- **Friendlier errors**: a reusable `ErrorCard` (icon + plain message + Retry)
  replaces raw red `Text` on Today and the detail tabs.
- **ⓘ affordance** on the calibrating and low-confidence banners linking to a short
  explanation of what the state means and how it affects the decision.
- **Mini readiness sparkline** on Today (last 7 days from `/v1/history`) that taps
  through to the Trends tab.

## Components (new/changed)

- New: `AppModel` (or extend `SyncService`) to own scenePhase-driven auto-sync and
  expose `lastSyncAt` relative text + in-flight sample count.
- New: `ErrorCard`, `PillarDetailSheet`, `InfoBadge` (ⓘ), `ReadinessSparkline`.
- Changed: `OnboardingView`, `RootView`/`MainTabView`, `TodayView`, `SettingsView`,
  `AskCoachView` presentation, `LabeledField` (secure field flags).

## Non-goals

- No HealthKit background delivery.
- No backend/API changes.
- No new metrics or data types (covered by the prior data-detail work).

## Success criteria

- Opening the app auto-syncs and shows a fresh score with a visible "last synced".
- Onboarding token entry works first try (no capitalization mismatch); a bad
  URL/token is caught by Test connection.
- All primary destinations reachable without a "More" menu.
- Errors show a retry affordance; each pillar and the calibrating/low-confidence
  states are self-explanatory in-app.
