# Usability v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce friction in the Readiness Coach iOS app across onboarding, syncing, navigation, and data clarity.

**Architecture:** iOS-only SwiftUI changes. Auto-sync is driven by `scenePhase`. Navigation drops from 7 tabs to 5, with Ask Coach and Settings promoted to Today nav-bar buttons. New small, focused view components (ErrorCard, InfoBadge, PillarDetailSheet, ReadinessSparkline). No backend or entitlement changes.

**Tech Stack:** SwiftUI, Swift Charts, HealthKit (existing), iOS 17.

## Global Constraints

- Target **iOS 17**, Swift 5.0, SwiftUI lifecycle. Verbatim from project config.
- **No backend/API changes.** Reuse existing endpoints only: `GET /health`, `GET /v1/today`, `GET /v1/history`, `POST /v1/sync`, `POST /v1/coach/ask`, `GET /v1/{sleep,train,body}`, `DELETE /v1/user`.
- **No new capabilities/entitlements** (no HealthKit background delivery).
- Read-only HealthKit; the score owns the decision (never recomputed/upgraded client-side).
- **Verification per task (no iOS test target):**
  - Build: `cd ios && xcodebuild -project ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` → expect `** BUILD SUCCEEDED **`.
  - Run: install to booted simulator, point its container prefs at the backend + a seeded user, launch, screenshot, confirm the described behavior.
  - Backend must be running (`PATH="$HOME/.local/node/bin:$PATH" npm --prefix ~/readiness-coach/backend run dev`) at `http://127.0.0.1:4000`, token `dev-token-change-me`.
- Commit after each task with the message shown.

---

### Task 1: Onboarding polish (token field, fields layout, Test connection)

**Files:**
- Modify: `ios/ReadinessCoach/Views/SettingsView.swift` (the shared `LabeledField`) — add autocapitalization/autocorrect controls.
- Modify: `ios/ReadinessCoach/Views/OnboardingView.swift` — 2 visible fields + Advanced disclosure + Test connection.
- Modify: `ios/ReadinessCoach/Networking/APIClient.swift` — add `testConnection()`.

**Interfaces:**
- Produces: `APIClient.testConnection() async throws` (throws `APIError` on failure; returns normally on success). `LabeledField` gains `autocapitalization: TextInputAutocapitalization = .never` behavior for secure fields.

- [ ] **Step 1: Fix the secure field in `LabeledField`** so the token never auto-capitalizes.

In `SettingsView.swift`, replace the `LabeledField` `Group` body:

```swift
Group {
    if secure {
        SecureField(label, text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body.monospaced())
    } else {
        TextField(label, text: $text)
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
    }
}
```

- [ ] **Step 2: Add `testConnection()` to `APIClient`.**

```swift
/// Verifies the base URL + token reach a working backend for this user.
func testConnection() async throws {
    // /health needs no auth but confirms the origin; getToday confirms auth + user.
    var health = URLRequest(url: baseURL.appendingPathComponent("health"))
    health.timeoutInterval = 8
    _ = try await URLSession.shared.data(for: health)
    _ = try await getToday()
}
```

- [ ] **Step 3: Rework `OnboardingView` "Connect your API" card** to two fields + Advanced + Test connection.

Replace the SectionCard titled "1 · Connect your API" body with:

```swift
LabeledField(label: "API URL", text: $settings.apiBaseURL, keyboard: .URL)
LabeledField(label: "API token", text: $settings.apiToken, secure: true)
DisclosureGroup("Advanced") {
    LabeledField(label: "User ID", text: $settings.userId)
        .padding(.top, 4)
}
.font(.subheadline)
Button {
    Task { await testConnection() }
} label: {
    HStack {
        Image(systemName: testIcon)
        Text(isTesting ? "Testing…" : "Test connection")
        Spacer()
        if isTesting { ProgressView() }
    }
}
.buttonStyle(.bordered)
.disabled(isTesting || !settings.isConfigured)
Text("The score is computed on your API. Point this at your backend and use a private bearer token.")
    .font(.caption).foregroundStyle(.secondary)
```

- [ ] **Step 4: Add the Test-connection state + method to `OnboardingView`.**

Add `@State private var isTesting = false` and `@State private var testOK: Bool?`, plus:

```swift
private var testIcon: String {
    switch testOK {
    case .some(true): return "checkmark.circle.fill"
    case .some(false): return "xmark.circle.fill"
    case nil: return "bolt.horizontal.circle"
    }
}

private func testConnection() async {
    guard let client = settings.makeClient() else { return }
    isTesting = true; error = nil
    defer { isTesting = false }
    do { try await client.testConnection(); testOK = true }
    catch {
        testOK = false
        self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
```

- [ ] **Step 5: Build.** Run the Global-Constraints build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Verify in simulator.** Fresh install with empty prefs (uninstall+install), launch → Onboarding. Confirm: only API URL + token show (User ID under Advanced), token field does not capitalize, Test connection shows ✓ against the running backend. Screenshot.

- [ ] **Step 7: Commit.**

```bash
git add ios/ReadinessCoach/Views/OnboardingView.swift ios/ReadinessCoach/Views/SettingsView.swift ios/ReadinessCoach/Networking/APIClient.swift
git commit -m "feat: streamline onboarding (fix token field, 2 fields, test connection)"
```

---

### Task 2: Auto-sync on foreground + last-synced + progress

**Files:**
- Modify: `ios/ReadinessCoach/Services/SyncService.swift` — expose in-flight sample count + a debounced `syncIfStale`/`autoSync`.
- Modify: `ios/ReadinessCoach/Settings/AppSettings.swift` — add `lastSyncRelativeText`.
- Modify: `ios/ReadinessCoach/Views/RootView.swift` — observe `scenePhase`, trigger auto-sync.
- Modify: `ios/ReadinessCoach/Views/TodayView.swift` — show "Last synced …" and "Uploading N samples…".

**Interfaces:**
- Consumes: `SyncService.syncNow(_:)` (existing).
- Produces: `SyncService.autoSync(_ settings: AppSettings) async` (syncs at most once per foreground; sets `uploadingCount`), `SyncService.uploadingCount: Int?` (@Published), `AppSettings.lastSyncRelativeText: String?`.

- [ ] **Step 1: Add published upload state + autoSync to `SyncService`.**

```swift
@Published var uploadingCount: Int?
private var lastAutoSyncAt: Date?

/// Foreground-triggered sync, debounced so rapid app switches don't re-sync.
func autoSync(_ settings: AppSettings) async {
    if let last = lastAutoSyncAt, Date().timeIntervalSince(last) < 30 { return }
    lastAutoSyncAt = Date()
    await syncNow(settings)
}
```

In `syncNow`, set `uploadingCount = payload.samples.count` right before `client.sync(payload)` and reset to `nil` in the `defer`:

```swift
// inside the HealthKit branch, before client.sync:
uploadingCount = payload.samples.count
// ... after sync completes or in the outer defer:
defer { isSyncing = false; uploadingCount = nil }
```

- [ ] **Step 2: Add relative time to `AppSettings`.**

```swift
var lastSyncRelativeText: String? {
    guard let date = lastSyncAt else { return nil }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}
```

- [ ] **Step 3: Drive auto-sync from `scenePhase` in `RootView`.**

In `RootView`:

```swift
@Environment(\.scenePhase) private var scenePhase
@EnvironmentObject private var sync: SyncService
```

Attach to the `MainTabView` branch:

```swift
if settings.isReady {
    MainTabView()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await sync.autoSync(settings) } }
        }
        .task { await sync.autoSync(settings) }
}
```

- [ ] **Step 4: Show last-synced + upload progress in `TodayView`.**

Under the readiness/decision block, add:

```swift
if let count = sync.uploadingCount {
    Label("Uploading \(count) samples…", systemImage: "arrow.up.circle")
        .font(.caption).foregroundStyle(.secondary)
} else if let synced = settings.lastSyncRelativeText {
    Text("Last synced \(synced)")
        .font(.caption).foregroundStyle(.secondary)
}
```

Remove the now-redundant `.task { if sync.today == nil { await sync.refreshToday(settings) } }` from `TodayView` (auto-sync in RootView covers first load), but keep the toolbar Sync button and `.refreshable`.

- [ ] **Step 5: Build.** Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Verify.** Launch app (already onboarded) → confirm it syncs without tapping, Today shows "Last synced …". Background then foreground the app (simulator: `xcrun simctl` launch again) → confirm it refreshes. Screenshot.

- [ ] **Step 7: Commit.**

```bash
git add ios/ReadinessCoach/Services/SyncService.swift ios/ReadinessCoach/Settings/AppSettings.swift ios/ReadinessCoach/Views/RootView.swift ios/ReadinessCoach/Views/TodayView.swift
git commit -m "feat: auto-sync on foreground with last-synced and upload progress"
```

---

### Task 3: Navigation — 5 tabs, Ask + Settings as Today nav-bar buttons

**Files:**
- Modify: `ios/ReadinessCoach/Views/RootView.swift` — `MainTabView` to 5 tabs.
- Modify: `ios/ReadinessCoach/Views/TodayView.swift` — toolbar Ask + Settings buttons and sheets.

**Interfaces:**
- Consumes: `AskCoachView`, `SettingsView` (existing, unchanged APIs).
- Produces: none new; `MainTabView` now renders exactly Today/Sleep/Train/Body/Trends.

- [ ] **Step 1: Reduce `MainTabView` to 5 tabs.**

```swift
struct MainTabView: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "sun.max") }
            SleepView().tabItem { Label("Sleep", systemImage: "bed.double") }
            TrainView().tabItem { Label("Train", systemImage: "figure.run") }
            BodyView().tabItem { Label("Body", systemImage: "heart") }
            TrendsView().tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
        }
    }
}
```

- [ ] **Step 2: Add Ask + Settings sheets to `TodayView`.**

Add state:

```swift
@State private var showAsk = false
@State private var showSettings = false
```

Add toolbar items (alongside the existing sync button) and sheets on the `ScrollView`/`NavigationStack`:

```swift
.toolbar {
    ToolbarItem(placement: .topBarLeading) {
        Button { showSettings = true } label: { Image(systemName: "gearshape") }
    }
    ToolbarItem(placement: .topBarTrailing) {
        Button { showAsk = true } label: { Image(systemName: "bubble.left.and.text.bubble.right") }
    }
    // (existing sync button ToolbarItem stays)
}
.sheet(isPresented: $showAsk) { NavigationStack { AskCoachView() } }
.sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
```

- [ ] **Step 3: Add a prominent "Ask the coach" button** on the Today screen, below the advisor card:

```swift
Button { showAsk = true } label: {
    Label("Ask the coach", systemImage: "bubble.left.and.text.bubble.right")
        .frame(maxWidth: .infinity)
}
.buttonStyle(.bordered)
```

- [ ] **Step 4: Build.** Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Verify.** Launch → exactly 5 tabs, no "More". Tap the gear → Settings sheet; tap the chat icon or the Ask button → Ask Coach sheet works and shows the locked decision. Screenshot both.

- [ ] **Step 6: Commit.**

```bash
git add ios/ReadinessCoach/Views/RootView.swift ios/ReadinessCoach/Views/TodayView.swift
git commit -m "feat: 5-tab nav; move Ask Coach and Settings to Today toolbar"
```

---

### Task 4: Reusable ErrorCard + decision meaning line

**Files:**
- Create: `ios/ReadinessCoach/Views/Components.swift` — `ErrorCard`, `InfoBadge`.
- Modify: `ios/ReadinessCoach/Views/TodayView.swift` — decision meaning line; use `ErrorCard`.
- Modify: `ios/ReadinessCoach/Views/{SleepView,TrainView,BodyView,TrendsView}.swift` — swap raw red `Text` for `ErrorCard`.

**Interfaces:**
- Produces: `ErrorCard(message: String, retry: () -> Void)`, `InfoBadge(title: String, message: String)` (an ⓘ button opening a small popover/alert), `Decision.meaning: String`.

- [ ] **Step 1: Create `Components.swift`.**

```swift
import SwiftUI

/// A friendly error surface with a retry affordance.
struct ErrorCard: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
            Text(message).font(.footnote).foregroundStyle(.secondary)
            Button("Retry", action: retry).buttonStyle(.bordered).controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// An ⓘ button that explains a piece of state.
struct InfoBadge: View {
    let title: String
    let message: String
    @State private var show = false
    var body: some View {
        Button { show = true } label: { Image(systemName: "info.circle") }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .alert(title, isPresented: $show) { Button("OK", role: .cancel) {} } message: { Text(message) }
    }
}
```

- [ ] **Step 2: Add `Decision.meaning`** in `RootView.swift` (next to `tint`/`systemImage`):

```swift
var meaning: String {
    switch self {
    case .push: return "You're recovered — a hard session is on the table."
    case .maintain: return "Train, but keep intensity moderate; no maximal efforts."
    case .recover: return "Back off today — rest or light movement only."
    }
}
```

- [ ] **Step 3: Show the meaning line under the decision chip in `TodayView`** (in the ring/decision block):

```swift
Text(today.decision.meaning)
    .font(.subheadline).foregroundStyle(.secondary)
    .multilineTextAlignment(.center)
    .padding(.horizontal)
```

- [ ] **Step 4: Replace raw error `Text` with `ErrorCard`** in Today/Sleep/Train/Body/Trends. Example for `TodayView`:

```swift
if let error = sync.errorMessage {
    ErrorCard(message: error) { Task { await sync.syncNow(settings) } }
}
```

For the detail views, retry calls their `load()`:

```swift
if let error { ErrorCard(message: error) { Task { await load() } } }
```

- [ ] **Step 5: Build.** Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Verify.** Launch → Today shows the decision meaning line. Temporarily set a bad token in the sim prefs → confirm ErrorCard + Retry appears instead of red text. Restore token. Screenshot.

- [ ] **Step 7: Commit.**

```bash
git add ios/ReadinessCoach/Views/Components.swift ios/ReadinessCoach/Views/RootView.swift ios/ReadinessCoach/Views/TodayView.swift ios/ReadinessCoach/Views/SleepView.swift ios/ReadinessCoach/Views/TrainView.swift ios/ReadinessCoach/Views/BodyView.swift ios/ReadinessCoach/Views/TrendsView.swift
git commit -m "feat: friendly error cards and decision meaning line"
```

---

### Task 5: Tappable pillar detail sheet

**Files:**
- Create: `ios/ReadinessCoach/Views/PillarDetailSheet.swift`.
- Modify: `ios/ReadinessCoach/Views/TodayView.swift` — make `PillarRow` tappable, present sheet.

**Interfaces:**
- Consumes: `PillarScore` (existing), `Decision` (existing).
- Produces: `PillarDetailSheet(name: String, weight: String, description: String, pillar: PillarScore)`.

- [ ] **Step 1: Create `PillarDetailSheet.swift`.**

```swift
import SwiftUI

struct PillarInfo: Identifiable {
    let id = UUID()
    let name: String
    let weight: String
    let description: String
    let pillar: PillarScore
}

struct PillarDetailSheet: View {
    let info: PillarInfo
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("\(Int(info.pillar.score.rounded()))")
                            .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("weight \(info.weight)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(info.description).font(.body)
                    if !info.pillar.drivers.isEmpty {
                        Text("Today's drivers").font(.headline)
                        ForEach(info.pillar.drivers, id: \.self) { d in
                            Label(d, systemImage: "chevron.right.circle").font(.subheadline)
                        }
                    }
                }.padding()
            }
            .navigationTitle(info.name)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
```

- [ ] **Step 2: Make pillars tappable in `TodayView`.**

Add `@State private var pillarInfo: PillarInfo?`. Wrap each `PillarRow` in a `Button` that sets `pillarInfo` with its copy. Descriptions:
- Sleep (35%): "Last night's duration and quality vs your ~8h need, plus recent sleep debt and consistency."
- Recovery (40%): "HRV and resting heart rate vs your 30-day baseline — the strongest readiness signal."
- Load (25%): "Recent training strain and the acute:chronic ratio — how hard you've pushed lately vs your norm."

Present:

```swift
.sheet(item: $pillarInfo) { PillarDetailSheet(info: $0) }
```

Example wrap:

```swift
Button {
    pillarInfo = PillarInfo(name: "Sleep", weight: "35%",
        description: "Last night's duration and quality vs your ~8h need, plus recent sleep debt and consistency.",
        pillar: pillars.sleep)
} label: { PillarRow(name: "Sleep", weight: "35%", pillar: pillars.sleep) }
.buttonStyle(.plain)
```

- [ ] **Step 3: Build.** Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify.** Launch → tap a pillar row → sheet shows score, weight, explanation, drivers. Screenshot.

- [ ] **Step 5: Commit.**

```bash
git add ios/ReadinessCoach/Views/PillarDetailSheet.swift ios/ReadinessCoach/Views/TodayView.swift
git commit -m "feat: tappable pillar detail sheets"
```

---

### Task 6: Readiness sparkline on Today + info badges on banners

**Files:**
- Create: `ios/ReadinessCoach/Views/ReadinessSparkline.swift`.
- Modify: `ios/ReadinessCoach/Views/TodayView.swift` — fetch 7-day history, show sparkline; add `InfoBadge` to banners.

**Interfaces:**
- Consumes: `APIClient.getHistory(days:date:)` (existing), `ReadinessPoint` (existing), `InfoBadge` (Task 4).
- Produces: `ReadinessSparkline(points: [ReadinessPoint])`.

- [ ] **Step 1: Create `ReadinessSparkline.swift`.**

```swift
import SwiftUI
import Charts

struct ReadinessSparkline: View {
    let points: [ReadinessPoint]
    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Date", ChartDate.day(point.date)),
                     y: .value("Readiness", point.readiness))
                .foregroundStyle(.secondary)
            PointMark(x: .value("Date", ChartDate.day(point.date)),
                      y: .value("Readiness", point.readiness))
                .foregroundStyle(point.decision.tint).symbolSize(24)
        }
        .chartYScale(domain: 0 ... 100)
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .frame(height: 56)
    }
}
```

- [ ] **Step 2: Fetch 7-day history in `TodayView`.**

Add `@State private var recent: [ReadinessPoint] = []`, and in the existing load/sync flow add:

```swift
if let client = settings.makeClient() {
    recent = (try? await client.getHistory(days: 7).data) ?? []
}
```

(Call this in the same `.task`/refresh path that loads Today; failures are silent — the sparkline just hides.)

- [ ] **Step 3: Show the sparkline in a tappable card that jumps to Trends.**

Below the pillars card:

```swift
if recent.count > 1 {
    SectionCard(title: "Readiness trend") {
        ReadinessSparkline(points: recent)
        Text("Last \(recent.count) days · tap Trends for detail")
            .font(.caption).foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 4: Add `InfoBadge` to the calibrating and low-confidence banners.**

In the `banner(...)` helper, add a trailing `InfoBadge`:
- Calibrating: title "Calibrating", message "Your baselines are still forming from recent history. Scores are provisional until ~14 days of data exist."
- Low confidence: title "Low confidence", message "Some signals are missing today, so the decision stays conservative. Sync your Watch data to improve it."

Example: change the banner `HStack` to include `InfoBadge(title:message:)` before the trailing `Spacer()` is fine, or after the text `VStack`.

- [ ] **Step 5: Build.** Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Verify.** Launch → Today shows a 7-day sparkline with decision-colored points; calibrating/low-confidence banners (when present) show a working ⓘ. Screenshot.

- [ ] **Step 7: Commit.**

```bash
git add ios/ReadinessCoach/Views/ReadinessSparkline.swift ios/ReadinessCoach/Views/TodayView.swift
git commit -m "feat: readiness sparkline on Today and info badges on banners"
```

---

## Self-Review

**Spec coverage:**
- Onboarding token fix / 2 fields / prefill / test connection → Task 1. ✓ (Prefill: `apiBaseURL` already persists via `AppSettings`, so it is pre-filled on return; no extra work.)
- Auto-sync on foreground / last-synced / progress → Task 2. ✓
- 5 tabs / Ask + Settings off tab bar → Task 3. ✓
- Decision meaning / tappable pillars / friendly errors / ⓘ badges / sparkline → Tasks 4–6. ✓
- Non-goals (no background delivery, no backend changes) respected throughout. ✓

**Placeholder scan:** No TBD/TODO; each code step shows concrete code. ✓

**Type consistency:** `ErrorCard(message:retry:)`, `InfoBadge(title:message:)`, `PillarInfo`/`PillarDetailSheet(info:)`, `ReadinessSparkline(points:)`, `Decision.meaning`, `SyncService.autoSync(_:)`/`uploadingCount`, `AppSettings.lastSyncRelativeText`, `APIClient.testConnection()` — names are used consistently across tasks. `ChartDate.day` and `Decision.tint` already exist. ✓
