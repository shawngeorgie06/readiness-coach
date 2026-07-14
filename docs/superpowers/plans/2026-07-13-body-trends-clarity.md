# Body & Trends Clarity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the iOS Body and Trends tabs interpretable — each metric gains a plain-language summary saying what it means, which direction is healthy, and how the user is trending — without any backend change.

**Architecture:** A single pure Swift helper (`MetricTrend.swift`) computes a last-7-days-vs-prior-7-days trend and a per-metric verdict phrase. `BodyView` and `TrendsView` consume it to render a summary line above each chart, rename jargon titles, and add ⓘ glossary badges. All data already arrives from the existing `getBody`/`getHistory` endpoints.

**Tech Stack:** SwiftUI (iOS 17), Swift Charts, existing shared views (`SectionCard`, `InfoBadge`, `ScrubReadout`). No backend, no new dependencies.

## Global Constraints

- **iOS presentation layer only. No backend change, no new endpoint, no DTO change.** All fields consumed already exist: `BodyDaily { type, date, min, avg, max }`, `ReadinessPoint { readiness, decision, sleepScore, recoveryScore, loadScore }`.
- **The deterministic score owns the decision.** These tabs are read-only displays; nothing here computes or influences readiness. Do not add scoring or advisor logic.
- **No iOS test target exists** (consistent with the Sleep/Train features). Verification is `xcodebuild … -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build` plus the concrete manual behavioral checks each task lists. Do NOT create an XCTest target.
- **The project is file-system-synchronized (objectVersion 77):** a new `.swift` file placed under `ios/ReadinessCoach/` is picked up automatically — do NOT edit `project.pbxproj`.
- **Comparison window:** last 7 days' average vs the prior 7 days' average (elements −8…−14 of the ascending daily series).
- **Steady thresholds (verbatim):** HRV = `2` ms, resting heart rate = `1.5` bpm, readiness = `2` points.
- **Insufficient-data rule:** if the recent window has fewer than 3 values OR the prior window is empty, emit no trend phrase — show only the current average. Never fabricate a trend from one or two points.
- **Build command (verbatim):**
  `xcodebuild -project ios/ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
  Run from the repo root (`/Users/shawngeorgie/readiness-coach`).

---

### Task 1: Shared trend helper (`MetricTrend.swift`)

**Files:**
- Create: `ios/ReadinessCoach/Views/MetricTrend.swift`

**Interfaces:**
- Consumes: nothing (pure Swift, no SwiftUI import).
- Produces:
  - `enum TrendDirection { case up, down, flat }`
  - `enum GoodDirection { case higher, lower }`
  - `struct MetricTrend { let direction: TrendDirection; let recentAvg: Double; let phrase: String }`
  - `func metricTrend(values: [Double], goodDirection: GoodDirection, threshold: Double) -> MetricTrend?`
    where `values` is the full **ascending** daily series (one value per day). Returns `nil` when insufficient. `phrase` is the ready-to-print verdict for Body metrics; `direction` lets Trends compose its own sentence.

- [ ] **Step 1: Create the file with the full implementation**

Create `ios/ReadinessCoach/Views/MetricTrend.swift`:

```swift
import Foundation

enum TrendDirection { case up, down, flat }

/// Which way is healthy for a metric.
enum GoodDirection { case higher, lower }

struct MetricTrend {
    let direction: TrendDirection
    let recentAvg: Double
    /// Ready-to-print verdict, e.g. "trending up vs last week, a good sign".
    let phrase: String
}

/// Trend of a daily series: average of the last 7 values vs the prior 7.
/// `values` must be sorted oldest→newest, one value per day.
/// Returns nil when there is not enough data to judge a trend.
func metricTrend(values: [Double], goodDirection: GoodDirection, threshold: Double) -> MetricTrend? {
    let recent = Array(values.suffix(7))
    let prior = Array(values.dropLast(recent.count).suffix(7))
    guard recent.count >= 3, !prior.isEmpty else { return nil }

    let recentAvg = recent.reduce(0, +) / Double(recent.count)
    let priorAvg = prior.reduce(0, +) / Double(prior.count)
    let delta = recentAvg - priorAvg

    let direction: TrendDirection = abs(delta) < threshold ? .flat : (delta > 0 ? .up : .down)
    return MetricTrend(direction: direction, recentAvg: recentAvg, phrase: phrase(direction, goodDirection))
}

private func phrase(_ direction: TrendDirection, _ good: GoodDirection) -> String {
    switch (direction, good) {
    case (.flat, _):        return "holding steady vs last week"
    case (.up, .higher):    return "trending up vs last week, a good sign"
    case (.down, .higher):  return "trending down vs last week, worth watching"
    case (.up, .lower):     return "creeping up vs last week, worth watching"
    case (.down, .lower):   return "trending down vs last week, a good sign"
    }
}
```

- [ ] **Step 2: Verify it builds**

Run (from repo root): `xcodebuild -project ios/ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
Expected: `** BUILD SUCCEEDED **`. The new file compiles and is auto-included (file-system-synchronized project).

- [ ] **Step 3: Commit**

```bash
git add ios/ReadinessCoach/Views/MetricTrend.swift
git commit -m "feat(ios): shared MetricTrend trend helper for Body/Trends"
```

---

### Task 2: Body tab summaries, titles, and badges

**Files:**
- Modify: `ios/ReadinessCoach/Views/BodyView.swift`

**Interfaces:**
- Consumes from Task 1: `metricTrend(values:goodDirection:threshold:)`, `MetricTrend`, `GoodDirection`.
- Consumes existing: `InfoBadge(title:message:)`, `SectionCard(title:)`, `BodyDaily`, the existing `fmt(_:)` helper in `BodyView`.

The current `lineCard(_:type:color:rows:selection:)` renders HRV and resting-heart-rate cards; `heartRateCard(_:)` renders the min/avg/max band. Add a summary line and ⓘ badge to each, and pass per-metric trend inputs into `lineCard`.

- [ ] **Step 1: Extend `lineCard` to take trend inputs and render a summary + badge**

Replace the `lineCard(...)` signature and body in `ios/ReadinessCoach/Views/BodyView.swift`. Change the signature to add `unit`, `goodDirection`, `threshold`, and `badge` parameters, and render a summary line above the chart:

```swift
    /// Daily-average line for a single metric type, with a plain-language trend summary.
    @ViewBuilder
    private func lineCard(_ title: String, type: String, color: Color, unit: String,
                          goodDirection: GoodDirection, threshold: Double,
                          badge: (title: String, message: String),
                          rows: [BodyDaily], selection: Binding<Date?>) -> some View {
        let series = rows.filter { $0.type == type }.sorted { $0.date < $1.date }
        if !series.isEmpty {
            SectionCard(title: title) {
                if let trend = metricTrend(values: series.map { $0.avg }, goodDirection: goodDirection, threshold: threshold) {
                    HStack(spacing: 6) {
                        Text("Averaging \(fmt(trend.recentAvg)) \(unit) — \(trend.phrase).")
                            .font(.subheadline.weight(.medium))
                        InfoBadge(title: badge.title, message: badge.message)
                    }
                } else if let latest = series.last {
                    HStack(spacing: 6) {
                        Text("Latest \(fmt(latest.avg)) \(unit).")
                            .font(.subheadline.weight(.medium))
                        InfoBadge(title: badge.title, message: badge.message)
                    }
                }
                Chart(series) { day in
                    LineMark(x: .value("Date", ChartDate.day(day.date)), y: .value("Avg", day.avg))
                        .foregroundStyle(color)
                    PointMark(x: .value("Date", ChartDate.day(day.date)), y: .value("Avg", day.avg))
                        .foregroundStyle(color).symbolSize(18)
                    if let sel = selection.wrappedValue {
                        RuleMark(x: .value("Date", sel))
                            .foregroundStyle(.gray.opacity(0.4))
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                if let snapped = nearestDate(sel, in: series.map { ChartDate.day($0.date) }),
                                   let hit = series.first(where: { ChartDate.day($0.date) == snapped }) {
                                    ScrubReadout(date: snapped, lines: ["\(fmt(hit.avg)) avg"])
                                }
                            }
                    }
                }
                .frame(height: 190)
                .chartXSelection(value: selection)
                if let latest = series.last {
                    Text("Latest avg \(fmt(latest.avg))  (range \(fmt(latest.min))–\(fmt(latest.max)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
```

- [ ] **Step 2: Update the two `lineCard` call sites with renamed titles and badge copy**

In the `body` of `BodyView`, replace the two `lineCard(...)` calls:

```swift
                        lineCard("Heart rate variability", type: "hrv_sdnn", color: .teal, unit: "ms",
                                 goodDirection: .higher, threshold: 2,
                                 badge: (title: "Heart rate variability",
                                         message: "The beat-to-beat variation in your heart rate, a read on nervous-system recovery. Higher — and rising — generally means better recovered. Shown as SDNN in milliseconds."),
                                 rows: response.daily, selection: $hrvSelection)
                        lineCard("Resting heart rate", type: "resting_heart_rate", color: .pink, unit: "bpm",
                                 goodDirection: .lower, threshold: 1.5,
                                 badge: (title: "Resting heart rate",
                                         message: "Your heart rate at rest. A lower resting heart rate usually signals better fitness and recovery."),
                                 rows: response.daily, selection: $rhrSelection)
```

- [ ] **Step 3: Add a descriptive ⓘ badge to the heart-rate band card (no verdict)**

In `heartRateCard(_:)`, change the `SectionCard` header row so the title carries an ⓘ badge. Replace the `SectionCard(title: "Heart rate (bpm) — daily min · avg · max") {` opening so the first child is a badge row (keep the rest of the card body unchanged):

```swift
            SectionCard(title: "Heart rate — daily range") {
                HStack(spacing: 6) {
                    Text("The lowest, average, and highest heart rate each day.")
                        .font(.caption).foregroundStyle(.secondary)
                    InfoBadge(title: "Daily heart rate",
                              message: "The lowest, average, and highest heart rate recorded each day. Useful context, not a readiness score on its own.")
                }
```

Leave the existing `Chart(series) { … }`, `.frame`, `.chartXSelection`, and the "Latest — min … · avg … · max … bpm" caption exactly as they are.

- [ ] **Step 4: Verify it builds**

Run (from repo root): `xcodebuild -project ios/ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual behavioral check (simulator or device, against local backend)**

Confirm on the Body tab:
- HRV card titled "Heart rate variability" shows "Averaging N ms — …" with a good/bad verdict that reads *up = good* (up → "a good sign").
- Resting heart rate shows the inverted sense (*up → "creeping up … worth watching"*, down → "a good sign").
- The heart-rate range card shows the descriptive caption and ⓘ badge, and **no** good/bad verdict.
- With very short history (<3 recent days) the summary falls back to "Latest N …" with no trend phrase.

- [ ] **Step 6: Commit**

```bash
git add ios/ReadinessCoach/Views/BodyView.swift
git commit -m "feat(ios): plain-language trend summaries and glossary on Body tab"
```

---

### Task 3: Trends tab summary and badges

**Files:**
- Modify: `ios/ReadinessCoach/Views/TrendsView.swift`

**Interfaces:**
- Consumes from Task 1: `metricTrend(values:goodDirection:threshold:)`, `TrendDirection`, `GoodDirection`.
- Consumes existing: `InfoBadge(title:message:)`, `SectionCard(title:)`, `ReadinessPoint`, `Decision`.

- [ ] **Step 1: Add a readiness trend summary line + ⓘ badge**

In `readinessCard(_:)` in `ios/ReadinessCoach/Views/TrendsView.swift`, insert a summary row as the first child of the `SectionCard` (before the `Chart`). Compose the sentence from the trend direction (readiness: higher = good, threshold 2):

```swift
        SectionCard(title: "Readiness — last \(response?.days ?? 0) days") {
            HStack(spacing: 6) {
                Text(readinessSummary(points))
                    .font(.subheadline.weight(.medium))
                InfoBadge(title: "Readiness score",
                          message: "A 0–100 daily score. 75+ means Push, 50–74 Maintain, under 50 Recover. The score decides; the coach only ever plays it safer.")
            }
```

Then add this helper method inside `TrendsView` (e.g. below `points`):

```swift
    /// Plain-language readiness trend for the summary line.
    private func readinessSummary(_ points: [ReadinessPoint]) -> String {
        guard let trend = metricTrend(values: points.map { $0.readiness }, goodDirection: .higher, threshold: 2) else {
            return "Not enough history yet to call a trend."
        }
        switch trend.direction {
        case .up:   return "Your readiness is improving lately."
        case .flat: return "Your readiness is holding steady lately."
        case .down: return "Your readiness is sliding lately."
        }
    }
```

Leave the existing `Chart`, `.chartYScale`, `.chartXSelection`, the decision legend `HStack`, and the "Latest …" caption unchanged.

- [ ] **Step 2: Add the pillar explainer caption + ⓘ badge**

In `pillarsCard(_:)`, add an explainer row as the first child of the `SectionCard` (before the `Chart`):

```swift
        SectionCard(title: "Pillar scores over time") {
            HStack(spacing: 6) {
                Text("Sleep, Recovery, and Load are the three inputs to your readiness — watch which one is dragging the others down.")
                    .font(.caption).foregroundStyle(.secondary)
                InfoBadge(title: "Pillars",
                          message: "Each pillar is scored 0–100. Your readiness is built from all three, so a low pillar here explains a low score on Today.")
            }
```

Leave the existing `Chart { … }`, `.chartForegroundStyleScale`, `.chartYScale`, and `.chartXSelection` unchanged.

- [ ] **Step 3: Verify it builds**

Run (from repo root): `xcodebuild -project ios/ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual behavioral check (simulator or device, against local backend)**

Confirm on the Trends tab:
- Readiness card shows an "improving / holding steady / sliding" sentence plus the ⓘ badge whose copy states the score owns the decision.
- With little history it reads "Not enough history yet to call a trend."
- Pillar card shows the one-line explainer and ⓘ badge.

- [ ] **Step 5: Commit**

```bash
git add ios/ReadinessCoach/Views/TrendsView.swift
git commit -m "feat(ios): readiness trend summary and pillar explainer on Trends tab"
```

---

## Self-Review Notes

- **Spec coverage:** Trend engine → Task 1. Body HRV/RHR summaries + renamed titles + badges → Task 2 (steps 1–2). HR band descriptive-only + badge → Task 2 step 3. Readiness summary + badge → Task 3 step 1. Pillar explainer + badge → Task 3 step 2. Insufficient-data rule → Task 1 (`nil`) with fallbacks in Tasks 2/3.
- **Type consistency:** `metricTrend(values:goodDirection:threshold:)`, `MetricTrend { direction, recentAvg, phrase }`, `GoodDirection { higher, lower }`, `TrendDirection { up, down, flat }` are used identically across Tasks 2 and 3.
- **Thresholds:** HRV 2, resting HR 1.5, readiness 2 — matches the spec verbatim.
