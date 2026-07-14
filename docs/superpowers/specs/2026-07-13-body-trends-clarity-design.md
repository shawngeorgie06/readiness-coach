# Body & Trends Clarity — Design

**Date:** 2026-07-13
**Follows:** data-clarity-v2 (2026-07-12), train-sleep-info (2026-07-13)
**Layer:** iOS presentation only — no backend change.

## Goal

Make the **Body** and **Trends** tabs interpretable for a user who has never
read this data before. Today both tabs render correct charts but leave the
numbers uninterpreted: nobody tells the user that higher HRV is good, that a
lower resting heart rate is good, or whether their own trend is improving.
This adds plain-language meaning, direction, and trend to each metric —
matching the depth of the Sleep tab's "Last night" card.

## Non-Goals / Invariants

- **No backend change.** All data already arrives via `getBody(days:)` and
  `getHistory(days:)`. This is display copy and derived-from-existing-data
  summaries only.
- **The deterministic score still owns the decision.** Nothing here computes
  or influences readiness; Body/Trends are read-only displays. No advisor,
  no new scoring.
- **iOS-only**, SwiftUI, iOS 17 patterns already in use (Swift Charts,
  `.chartXSelection`, `InfoBadge`, `SectionCard`, `ScrubReadout`).

## Shared Trend Engine

A small pure helper, reused by every verdict metric:

```
enum TrendDirection { case up, down, flat }

struct MetricTrend {
    let direction: TrendDirection
    let recentAvg: Double
    /// Plain verdict phrase, e.g. "trending up vs last week, a good sign".
    let phrase: String
}
```

- **Comparison window:** average of the **last 7 days** vs average of the
  **prior 7 days** (days −8…−14). This matches the "vs 7-day average"
  language already used in the Sleep tab.
- **Steady threshold:** if `abs(recentAvg - priorAvg)` is below a per-metric
  epsilon, direction is `.flat` ("holding steady"). Thresholds:
  HRV = 2 ms, resting heart rate = 1.5 bpm.
- **Good direction is per metric.** The verdict phrase combines
  `TrendDirection` with the metric's healthy direction:
  - HRV: up = good. Phrases: up → "trending up vs last week, a good sign";
    down → "trending down vs last week, worth watching"; flat → "holding
    steady vs last week".
  - Resting heart rate: down = good. up → "creeping up vs last week, worth
    watching"; down → "trending down vs last week, a good sign"; flat →
    "holding steady vs last week".
- **Insufficient data:** if fewer than 3 days exist in the recent window OR
  the prior window is empty, emit no trend phrase (show only the current
  average). Never fabricate a trend from one or two points.

## Body Tab

Each metric card gains a **summary line above the chart** (same slot the
Sleep "Last night" card uses), built from `MetricTrend`.

1. **Heart rate variability** — card title renamed from `"HRV (SDNN, ms)"` to
   `"Heart rate variability"`.
   - Summary: `"Averaging {recentAvg} ms — {trend phrase}."`
   - ⓘ badge "Heart rate variability": *The beat-to-beat variation in your
     heart rate, a read on nervous-system recovery. Higher — and rising — generally means better recovered. Shown as SDNN in milliseconds.*
   - Existing "Latest avg … (range …)" caption stays.

2. **Resting heart rate** — title `"Resting heart rate"` (drop the "(bpm)"
   from the title; unit stays in the copy).
   - Summary: `"Averaging {recentAvg} bpm — {trend phrase}."`
   - ⓘ badge "Resting heart rate": *Your heart rate at rest. A lower resting
     heart rate usually signals better fitness and recovery.*

3. **Heart rate (min · avg · max)** — **descriptive only, no verdict.** Daily
   heart-rate range is not a clean readiness signal, so no good/bad phrase.
   - Plainer caption retained ("Latest — min … · avg … · max … bpm").
   - ⓘ badge "Daily heart rate": *The lowest, average, and highest heart rate
     recorded each day. Useful context, not a readiness score on its own.*

## Trends Tab

1. **Readiness** — add a plain summary line derived from the readiness series
   over the window (last 7d avg vs prior 7d avg of the `readiness` value,
   up = good):
   - `"Your readiness is improving / holding steady / sliding lately."`
     (up → improving, flat → holding steady, down → sliding). Same
     insufficient-data rule.
   - ⓘ badge "Readiness score": *A 0–100 daily score. 75+ means Push, 50–74
     Maintain, under 50 Recover. The score decides; the coach only ever plays
     it safer.*
   - Existing decision-color legend and "Latest …" caption stay.

2. **Pillar scores** — add a one-line explainer + ⓘ badge (no per-pillar
   trend verdicts; the three lines already show direction visually):
   - Caption: *"Sleep, Recovery, and Load are the three inputs to your
     readiness — watch which one is dragging the others down."*
   - ⓘ badge "Pillars": same one-line explanation, expanded slightly:
     *Each pillar is scored 0–100. Your readiness is built from all three, so
     a low pillar here explains a low score on Today.*

## Files

- `ios/ReadinessCoach/Views/BodyView.swift` — summary lines, renamed titles,
  ⓘ badges; add the trend helper (or a shared file, see below).
- `ios/ReadinessCoach/Views/TrendsView.swift` — readiness summary line, ⓘ
  badges, pillar explainer caption.
- **Trend helper location:** put `MetricTrend` / `TrendDirection` and the
  `metricTrend(recent:prior:goodDirection:)` function in a new
  `ios/ReadinessCoach/Views/MetricTrend.swift` so both views share one
  implementation (Body uses it 2×, Trends 1×). Pure function, no SwiftUI.

## Verification

- **iOS:** `xcodebuild -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
  succeeds; both tabs render with summary lines and badges against the local
  backend. No iOS test target for these views (consistent with Sleep/Train).
- **No backend tests** — backend untouched.
- Manual: on the simulator, confirm HRV shows a "good sign / worth watching /
  holding steady" verdict, resting HR inverts the good direction, the HR band
  shows no verdict, and Trends shows the readiness summary + pillar explainer.
