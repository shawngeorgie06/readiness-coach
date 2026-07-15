# Data Clarity v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace engineer-speak pillar drivers with concise plain-language text (exact detail on tap), and add a finger-drag scrubber to the Body and Trends charts.

**Architecture:** Backend scoring emits **structured drivers** `{ text, detail? }` (single source of truth) instead of bare strings; the advisor projects them back to strings via `detail ?? text` so its behavior is unchanged. iOS renders `text` on the pillar card and `text + detail` in the pillar sheet, humanizes the low-confidence banner, and gains a reusable Swift Charts scrub overlay applied to Body and Trends.

**Tech Stack:** TypeScript + Vitest (backend); SwiftUI + Swift Charts, iOS 17 (app).

## Global Constraints

- The deterministic score owns the decision (Push ≥75 / Maintain 50–74 / Recover <50). This work changes only how score **inputs are described**, never the score or decision.
- Tone: concise / scannable — keep a number plus a short qualifier on the card; no emoji; no coach-persona voice. Exact numbers, units, and timeframes live in `detail`.
- `DailyScore.drivers` is a `Json` column — no DB migration; the structured shape serializes as-is.
- Backend verification: `cd backend && npm test` → all suites pass.
- iOS: **no test target.** Verify with `cd ios && xcodebuild -project ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` → `** BUILD SUCCEEDED **`, then install to a booted simulator against the running backend (`PATH="$HOME/.local/node/bin:$PATH" npm --prefix backend run dev`, token `dev-token-change-me`, seeded user `user_1`) and screenshot.
- Out of scope: detail-tab metric labels, the UTC sleep-window fix, advisor note copy.
- Commit after each task with the message shown.

---

### Task 1: Backend structured drivers

Atomic because `PillarScore.drivers` is shared by all three scorers **and** the advisor; the type change ripples across them and must land green together.

**Files:**
- Modify: `backend/src/scoring/types.ts` (add `Driver`, change `PillarScore.drivers`)
- Modify: `backend/src/scoring/sleep.ts`, `backend/src/scoring/recovery.ts`, `backend/src/scoring/load.ts`
- Modify: `backend/src/services/advisorService.ts` (project `Driver[]` → `string[]`)
- Test: `backend/tests/scoring/sleep.test.ts`, `recovery.test.ts`, `load.test.ts`, `backend/tests/services/advisorService.test.ts`

**Interfaces:**
- Produces: `interface Driver { text: string; detail?: string }`; `PillarScore.drivers: Driver[]`. Card reads `driver.text`; sheet reads `driver.text` + `driver.detail`. Advisor consumes `driver.detail ?? driver.text`.

- [ ] **Step 1: Add the `Driver` type and change `PillarScore`.**

In `backend/src/scoring/types.ts`, replace the `PillarScore` interface (currently `drivers: string[]`) and add `Driver` above it:

```ts
export interface Driver {
  /** Concise, plain-language card line, e.g. "3h catch-up owed this week". */
  text: string;
  /** Exact explanation with units/timeframe for the tap sheet. */
  detail?: string;
}

export interface PillarScore {
  score: number;
  drivers: Driver[];
}
```

- [ ] **Step 2: Rewrite `scoreSleep` drivers.** In `backend/src/scoring/sleep.ts`, replace the `const drivers: string[] = [];` block (and the pushes through `if (drivers.length === 0) ...`) with:

```ts
  const drivers: Driver[] = [];
  if (durationRatio < 0.9) {
    drivers.push({
      text: `${input.durationHours.toFixed(1)}h sleep · below your ${input.needHours}h target`,
      detail: `You slept ${input.durationHours.toFixed(1)}h against your ${input.needHours}h nightly target.`,
    });
  }
  if (input.sleepDebtHours >= 1) {
    drivers.push({
      text: `${input.sleepDebtHours.toFixed(0)}h catch-up owed this week`,
      detail: `Total shortfall against your ${input.needHours}h nightly need across the last 7 nights.`,
    });
  }
  if (input.consistencyStdHours >= 1) {
    drivers.push({
      text: "Irregular sleep schedule",
      detail: `Your nightly sleep length swung about ${input.consistencyStdHours.toFixed(1)}h night-to-night this week; steadier timing improves recovery.`,
    });
  }
  if (drivers.length === 0) {
    drivers.push({ text: "Sleep on target", detail: "Duration, quality, and consistency all look good." });
  }
```

Add `Driver` to the type import: `import type { Driver, PillarScore, SleepInput } from "./types.js";`.

- [ ] **Step 3: Rewrite `scoreRecovery` drivers.** In `backend/src/scoring/recovery.ts`, update the import to `import type { Driver, PillarScore, RecoveryInput } from "./types.js";` and replace the `const drivers: string[] = []; ... ` block through the final `if` with:

```ts
  const drivers: Driver[] = [];
  const hrvPct = hrvDelta * 100;
  const hrvQualifier =
    hrvDelta >= 0.05 ? "above your normal" : hrvDelta <= -0.05 ? "below your normal" : "normal for you";
  drivers.push({
    text: `HRV ${input.hrvMs.toFixed(0)}ms · ${hrvQualifier}`,
    detail: `Heart-rate variability is ${input.hrvMs.toFixed(0)}ms vs your 30-day average of ${input.hrvBaseline30dMs.toFixed(0)}ms (${hrvPct >= 0 ? "+" : ""}${hrvPct.toFixed(0)}%). Higher usually means more recovered.`,
  });
  if (rhrDelta > 0.03) {
    drivers.push({
      text: `Resting pulse ${input.restingHrBpm.toFixed(0)} · elevated`,
      detail: `Resting heart rate ${input.restingHrBpm.toFixed(0)} bpm is above your ${input.restingHrBaseline30dBpm.toFixed(0)} bpm baseline — often a sign of fatigue or oncoming illness.`,
    });
  }
  if (hrvDelta >= 0 && rhrDelta <= 0) {
    drivers.push({ text: "Recovery steady", detail: "HRV and resting pulse are both in your normal range." });
  }
```

- [ ] **Step 4: Rewrite `scoreLoad` drivers.** In `backend/src/scoring/load.ts`, update the import to `import type { Driver, LoadInput, PillarScore } from "./types.js";` and replace the `const drivers: string[] = []; ...` block through the final `if` with:

```ts
  const drivers: Driver[] = [];
  const yStrain = input.yesterdayStrain;
  const strainText =
    yStrain < 4 ? "Rest day yesterday"
      : yStrain < 10 ? `Light day yesterday (strain ${yStrain.toFixed(0)})`
        : `Hard day yesterday (strain ${yStrain.toFixed(0)})`;
  drivers.push({
    text: strainText,
    detail: `Strain rates how hard training was, 0–21. Yesterday was ${yStrain.toFixed(1)}.`,
  });
  const balance =
    input.acuteChronicRatio > 1.3 ? "ramping up" : input.acuteChronicRatio < 0.7 ? "backing off" : "balanced";
  drivers.push({
    text: `Training load ${balance}`,
    detail: `Your last 7 days of training vs your usual 28-day level is ${input.acuteChronicRatio.toFixed(2)}× (0.8–1.3 is the healthy zone).`,
  });
  if (input.acuteChronicRatio > 1.3) {
    drivers.push({
      text: "Training load spiking",
      detail: `The last week is well above your norm (${input.acuteChronicRatio.toFixed(2)}×); injury risk rises above 1.3×.`,
    });
  }
```

- [ ] **Step 5: Project drivers to strings in the advisor.** In `backend/src/services/advisorService.ts`, add a helper near the top of the file (after the imports) and use it in `allDrivers` and `metricSummary` so the advisor keeps working on strings with the richest numbers:

```ts
import type { Driver } from "../scoring/types.js"; // add to existing scoring imports

/** The advisor works in strings; prefer the exact `detail` (has the real numbers). */
function driverText(driver: Driver): string {
  return driver.detail ?? driver.text;
}
```

In `allDrivers`, change the three pillar spreads to map:

```ts
    ...today.pillars.sleep.drivers.map(driverText),
    ...today.pillars.recovery.drivers.map(driverText),
    ...today.pillars.load.drivers.map(driverText),
```

In `metricSummary`, change the pillar mapping to:

```ts
      Object.entries(today.pillars).map(([name, pillar]) => [name, { score: pillar.score, drivers: pillar.drivers.map(driverText) }]),
```

`buildTemplateNote({ decision, drivers: string[] })` is unchanged — its callers still pass `string[]` (from `allDrivers`).

- [ ] **Step 6: Update scoring tests to assert the new shape.** The existing score-magnitude assertions still pass unchanged. Append a driver-shape assertion to one test in each scorer file.

In `backend/tests/scoring/sleep.test.ts`, inside the "scores low when short sleep and high debt" test, after the existing `expect`:

```ts
    expect(result.drivers.some((d) => d.text.includes("catch-up owed this week"))).toBe(true);
    expect(result.drivers.every((d) => typeof d.text === "string")).toBe(true);
```

In `backend/tests/scoring/recovery.test.ts`, inside "scores low when HRV deeply suppressed and RHR elevated", after the existing `expect`:

```ts
    expect(result.drivers[0].text).toMatch(/^HRV \d+ms · below your normal$/);
    expect(result.drivers.some((d) => d.text.includes("Resting pulse"))).toBe(true);
```

In `backend/tests/scoring/load.test.ts`, inside "scores lower when acute:chronic is spiked", after the existing `expect`:

```ts
    expect(result.drivers.some((d) => d.text === "Training load spiking")).toBe(true);
    expect(result.drivers.some((d) => d.text.includes("day yesterday"))).toBe(true);
```

- [ ] **Step 7: Fix the advisor test fixtures to the `Driver` shape.** In `backend/tests/services/advisorService.test.ts`, the `generateAdvisorNote` call passes string-array drivers, which no longer typecheck. Change its `pillars` to:

```ts
        pillars: {
          sleep: { score: 20, drivers: [{ text: "Sleep 4.5h vs need 8h" }] },
          recovery: { score: 30, drivers: [{ text: "HRV -25% vs 30d baseline" }] },
          load: { score: 40, drivers: [{ text: "Yesterday strain 15.0" }] },
        },
```

The `buildTemplateNote` test still passes bare `drivers: ["HRV -12% vs baseline", "Sleep debt 1.6h"]` — that signature is unchanged, so leave it.

- [ ] **Step 8: Run the backend suite.**

Run: `cd backend && PATH="$HOME/.local/node/bin:$PATH" npm test`
Expected: all suites pass (scoring, integration, services, web unaffected). If a type error surfaces in `todayService.ts`, it is because `DailyScore.drivers` now stores `Driver[]` — that is expected and requires no code change (the column is `Json`).

- [ ] **Step 9: Commit.**

```bash
git add backend/src/scoring/types.ts backend/src/scoring/sleep.ts backend/src/scoring/recovery.ts backend/src/scoring/load.ts backend/src/services/advisorService.ts backend/tests/scoring/sleep.test.ts backend/tests/scoring/recovery.test.ts backend/tests/scoring/load.test.ts backend/tests/services/advisorService.test.ts
git commit -m "feat: structured plain-language pillar drivers (text + detail)"
```

---

### Task 2: iOS Driver DTO + Today rendering

**Files:**
- Modify: `ios/ReadinessCoach/Models/DTOs.swift` (add `Driver`, change `PillarScore.drivers`)
- Modify: `ios/ReadinessCoach/Views/TodayView.swift` (`PillarRow` render + banner copy)
- Modify: `ios/ReadinessCoach/Views/PillarDetailSheet.swift` (text + detail rows)

**Interfaces:**
- Consumes: backend `/v1/today` pillar `drivers: [{text, detail?}]` (Task 1).
- Produces: `struct Driver: Codable, Hashable { let text: String; let detail: String? }`; `PillarScore.drivers: [Driver]`.

- [ ] **Step 1: Add the `Driver` struct and change `PillarScore`.** In `ios/ReadinessCoach/Models/DTOs.swift`, replace the `PillarScore` struct (currently `let drivers: [String]`) with:

```swift
struct Driver: Codable, Hashable {
    let text: String
    let detail: String?
}

struct PillarScore: Codable, Hashable {
    let score: Double
    let drivers: [Driver]
}
```

- [ ] **Step 2: Render `text` lines in `PillarRow`.** In `ios/ReadinessCoach/Views/TodayView.swift`, replace the drivers block in `PillarRow.body` (currently `Text(pillar.drivers.joined(separator: " · "))`) with:

```swift
            if !pillar.drivers.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(pillar.drivers, id: \.self) { driver in
                        Text(driver.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
```

- [ ] **Step 3: Humanize the low-confidence banner.** In `ios/ReadinessCoach/Views/TodayView.swift`, replace the `today.isLowConfidence` banner call's message argument. Change the existing banner message string to use a friendly list, and add the helper. Replace the message line:

```swift
                "Some data is missing today\(Self.friendlyMissing(today.missing)), so we're keeping the call cautious.",
```

Add this static helper inside `struct TodayView` (e.g. above `body`):

```swift
    /// Maps raw missing-metric keys to human names for the banner.
    static func friendlyMissing(_ keys: [String]) -> String {
        let names = keys.map { key -> String in
            switch key {
            case "hrv": return "heart-rate variability"
            case "resting_heart_rate": return "resting pulse"
            case "sleep": return "sleep"
            default: return key
            }
        }
        return names.isEmpty ? "" : " (\(names.joined(separator: ", ")))"
    }
```

- [ ] **Step 4: Show `text` + `detail` in the pillar sheet.** In `ios/ReadinessCoach/Views/PillarDetailSheet.swift`, replace the drivers `ForEach` (currently `ForEach(info.pillar.drivers, id: \.self) { d in Label(d, systemImage: ...) }`) with:

```swift
                        ForEach(info.pillar.drivers, id: \.self) { driver in
                            VStack(alignment: .leading, spacing: 2) {
                                Label(driver.text, systemImage: "chevron.right.circle")
                                    .font(.subheadline)
                                if let detail = driver.detail {
                                    Text(detail)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 26)
                                }
                            }
                        }
```

- [ ] **Step 5: Build.**

Run: `cd ios && xcodebuild -project ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Verify in simulator.** With the backend running and `user_1` seeded, install + launch, screenshot Today. Confirm each pillar shows plain lines (e.g. "Training load balanced", "Rest day yesterday", no "Acute:chronic 0.92"); tap a pillar → each driver shows its concise line plus an exact detail sentence; the low-confidence banner (when present) names missing data in words.

- [ ] **Step 7: Commit.**

```bash
git add ios/ReadinessCoach/Models/DTOs.swift ios/ReadinessCoach/Views/TodayView.swift ios/ReadinessCoach/Views/PillarDetailSheet.swift
git commit -m "feat: render plain-language drivers and friendly low-confidence banner"
```

---

### Task 3: iOS chart scrubber on Body + Trends

**Files:**
- Create: `ios/ReadinessCoach/Views/ChartScrubber.swift`
- Modify: `ios/ReadinessCoach/Views/BodyView.swift`, `ios/ReadinessCoach/Views/TrendsView.swift`

**Interfaces:**
- Consumes: `ChartDate.day(_:)` (existing) to produce the `Date` x-values the charts already plot.
- Produces: `View.chartScrub(dates: [Date], selected: Binding<Date?>)` — a drag overlay that snaps the touched x to the nearest of `dates` and writes it to `selected`.

- [ ] **Step 1: Create the reusable scrub modifier.** Create `ios/ReadinessCoach/Views/ChartScrubber.swift`:

```swift
import SwiftUI
import Charts

/// Finger-drag scrubbing for a Swift Chart: maps the touch x-position to the
/// nearest plotted date and reports it via `selected`. The marker persists after
/// release (until the next drag) so the last reading stays visible.
struct ChartScrub: ViewModifier {
    let dates: [Date]
    @Binding var selected: Date?

    func body(content: Content) -> some View {
        content.chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let originX = geo[plotFrame].origin.x
                                let x = value.location.x - originX
                                guard let date: Date = proxy.value(atX: x) else { return }
                                selected = nearest(to: date)
                            }
                    )
            }
        }
    }

    private func nearest(to date: Date) -> Date? {
        dates.min(by: {
            abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date))
        })
    }
}

extension View {
    func chartScrub(dates: [Date], selected: Binding<Date?>) -> some View {
        modifier(ChartScrub(dates: dates, selected: selected))
    }
}

/// Shared floating readout drawn at the selected point.
struct ScrubReadout: View {
    let date: Date
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(date, format: .dateTime.month().day())
                .font(.caption2.weight(.semibold))
            ForEach(lines, id: \.self) { Text($0).font(.caption2) }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
```

- [ ] **Step 2: Add scrubbing to the Body charts.** In `ios/ReadinessCoach/Views/BodyView.swift`, add selection state and wire each chart.

Add to `struct BodyView` state:

```swift
    @State private var lineSelection: Date?
    @State private var hrSelection: Date?
```

In `lineCard`, add a `RuleMark` inside the `Chart(series)` builder (after the existing `PointMark`) and the modifier after `.frame(height: 190)`:

```swift
                    if let sel = lineSelection, let hit = series.first(where: { ChartDate.day($0.date) == sel }) {
                        RuleMark(x: .value("Date", sel))
                            .foregroundStyle(.gray.opacity(0.4))
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                ScrubReadout(date: sel, lines: ["\(fmt(hit.avg)) avg"])
                            }
                    }
```

and after `.frame(height: 190)`:

```swift
                .chartScrub(dates: series.map { ChartDate.day($0.date) }, selected: $lineSelection)
```

In `heartRateCard`, add a `RuleMark` inside the `Chart(series)` builder (after the `LineMark`) and the modifier after `.frame(height: 200)`:

```swift
                    if let sel = hrSelection, let hit = series.first(where: { ChartDate.day($0.date) == sel }) {
                        RuleMark(x: .value("Date", sel))
                            .foregroundStyle(.gray.opacity(0.4))
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                ScrubReadout(date: sel, lines: [
                                    "min \(fmt(hit.min))", "avg \(fmt(hit.avg))", "max \(fmt(hit.max))",
                                ])
                            }
                    }
```

```swift
                .chartScrub(dates: series.map { ChartDate.day($0.date) }, selected: $hrSelection)
```

Note: `lineCard` is used for two metrics (HRV and RHR). Sharing one `lineSelection` is intentional — only the chart under the finger updates its own `series` lookup, and both cards reading the same date is acceptable; the readout only renders where a matching point exists.

- [ ] **Step 3: Add scrubbing to the Trends charts.** In `ios/ReadinessCoach/Views/TrendsView.swift`, add state:

```swift
    @State private var readinessSelection: Date?
    @State private var pillarSelection: Date?
```

In `readinessCard`, add inside the `Chart(points)` builder (after `PointMark`):

```swift
                if let sel = readinessSelection, let hit = points.first(where: { ChartDate.day($0.date) == sel }) {
                    RuleMark(x: .value("Date", sel))
                        .foregroundStyle(.gray.opacity(0.4))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            ScrubReadout(date: sel, lines: ["\(Int(hit.readiness.rounded())) · \(hit.decision.title)"])
                        }
                }
```

and after `.frame(height: 200)`:

```swift
            .chartScrub(dates: points.map { ChartDate.day($0.date) }, selected: $readinessSelection)
```

In `pillarsCard`, add inside the `Chart { ... }` builder (after the `ForEach(points)` block):

```swift
                if let sel = pillarSelection, let hit = points.first(where: { ChartDate.day($0.date) == sel }) {
                    RuleMark(x: .value("Date", sel))
                        .foregroundStyle(.gray.opacity(0.4))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            ScrubReadout(date: sel, lines: [
                                "Sleep \(Int(hit.sleepScore.rounded()))",
                                "Recovery \(Int(hit.recoveryScore.rounded()))",
                                "Load \(Int(hit.loadScore.rounded()))",
                            ])
                        }
                }
```

and after `.chartYScale(domain: 0 ... 100)` / `.frame(height: 200)` on that chart:

```swift
            .chartScrub(dates: points.map { ChartDate.day($0.date) }, selected: $pillarSelection)
```

- [ ] **Step 4: Build.**

Run: `cd ios && xcodebuild -project ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Verify in simulator.** Install + launch, open Body and Trends. Drag across each chart and confirm a vertical marker follows the finger with a floating readout showing the date and the exact value(s) (HRV avg; HR min/avg/max; readiness + decision; the three pillar scores). Screenshot Body and Trends mid-scrub. (Simulator: click-drag with the mouse simulates the finger.)

- [ ] **Step 6: Commit.**

```bash
git add ios/ReadinessCoach/Views/ChartScrubber.swift ios/ReadinessCoach/Views/BodyView.swift ios/ReadinessCoach/Views/TrendsView.swift
git commit -m "feat: draggable scrubber on Body and Trends charts"
```

---

## Self-Review

**Spec coverage:**
- Structured drivers `{text, detail}` at the backend source → Task 1. ✓
- Concrete driver rewrites (sleep debt, HRV, acute:chronic, strain) → Task 1 Steps 2–4, verbatim from spec §1. ✓
- Advisor keeps working (projects `detail ?? text`) → Task 1 Step 5. ✓
- iOS card renders `text`; sheet renders `text + detail` → Task 2 Steps 2, 4. ✓
- Friendly low-confidence banner → Task 2 Step 3. ✓
- Decision/score meaning line — already shipped in usability-v1; no task needed (spec §2 notes "keep as-is"). ✓
- Chart scrubber on Body + Trends, all charts, date + exact values, persist-after-release → Task 3. ✓
- Out-of-scope items (detail-tab labels, tz fix, advisor copy) — not touched. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code. ✓

**Type consistency:** `Driver { text, detail? }` identical in TS (Task 1 Step 1) and Swift (Task 2 Step 1). `PillarScore.drivers: Driver[]`/`[Driver]` consistent. `chartScrub(dates:selected:)` and `ScrubReadout(date:lines:)` used with matching signatures in Task 3 Steps 2–3. `ChartDate.day` and `Decision.title` already exist. Backend `driverText` is file-local and used only where strings are required. ✓
