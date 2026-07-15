# Readiness Coach — Data Clarity v2 (design)

Date: 2026-07-12
Scope: iOS Today screen + backend pillar-driver copy, plus a chart scrubber on
the Body and Trends tabs. Follows the completed usability-v1 work.

## Goal

Make what the app shows understandable to a new user who has *not* already read
their Health data. Today the pillar "drivers" expose raw internal computations in
engineer-speak — e.g. `Sleep debt 3.0h`, `Acute:chronic 0.92`, `HRV -12% vs 30d
baseline` — with no units, timeframe, or plain meaning. Replace them with concise,
scannable plain language, backed by an exact explanation on tap. Separately, let
the user drag along the Body/Trends charts to read the precise value at any point.

## Decisions (locked)

- **Explanation level**: concise plain-language driver on the card; exact detail on tap.
- **Scope**: the whole Today screen (pillars + tap sheets, low-confidence banner,
  decision/score meaning). Plus a draggable scrubber on Body + Trends charts.
- **Tone**: concise / scannable — keep the number, add a short qualifier; not full
  sentences on the card, no emoji, no coach-persona voice.
- **Architecture**: backend emits **structured drivers** `{ text, detail? }` (single
  source of truth); iOS renders `text` on the card and `text + detail` in the sheet.
- **Out of scope** (separate items): detail-tab metric *labels* (Body "HRV SDNN",
  Sleep/Train/Trends axis copy); the UTC sleep-window timezone fix; the advisor note copy.

The product invariant is unchanged: the deterministic score owns the decision
(Push ≥75 / Maintain 50–74 / Recover <50). This work only changes how existing
score inputs are *described*; it never changes the score or the decision.

## 1. Structured drivers (backend)

### Type change

`backend/src/scoring/types.ts`:

```ts
export interface Driver {
  text: string;      // concise card line, e.g. "3h catch-up owed this week"
  detail?: string;   // exact tap-sheet explanation
}

export interface PillarScore {
  score: number;
  drivers: Driver[]; // was: string[]
}
```

This flows unchanged through storage (`DailyScore.drivers` is already a `Json`
column — no migration) and through the `/v1/today` DTO. `getReadinessHistory`
still produces drivers via `computeScore`; Trends ignores them, so no display impact.

### Driver rewrites

Each scorer builds `Driver` objects. `detail` embeds the exact numbers/timeframes.
`text` keeps a number where it aids scanning, plus a short qualifier.

**Sleep (`scoring/sleep.ts`)** — `need = input.needHours`, `dur =
input.durationHours`, `debt = input.sleepDebtHours`, `std = input.consistencyStdHours`:

| Condition | `text` | `detail` |
|---|---|---|
| `durationRatio < 0.9` | `` `${dur.toFixed(1)}h sleep · below your ${need}h target` `` | `` `You slept ${dur.toFixed(1)}h against your ${need}h nightly target.` `` |
| `debt >= 1` | `` `${debt.toFixed(0)}h catch-up owed this week` `` | `` `Total shortfall against your ${need}h nightly need across the last 7 nights.` `` |
| `std >= 1` | `Irregular sleep schedule` | `` `Your nightly sleep length swung about ${std.toFixed(1)}h night-to-night this week; steadier timing improves recovery.` `` |
| none of the above | `Sleep on target` | `Duration, quality, and consistency all look good.` |

**Recovery (`scoring/recovery.ts`)** — `hrvMs = input.hrvMs`, `hrvBase =
input.hrvBaseline30dMs`, `rhr = input.restingHrBpm`, `rhrBase =
input.restingHrBaseline30dBpm`; `hrvPct = hrvDelta*100`. Qualifier helper:
`hrvDelta >= 0.05 ? "above your normal" : hrvDelta <= -0.05 ? "below your normal" : "normal for you"`.

| Condition | `text` | `detail` |
|---|---|---|
| always (HRV) | `` `HRV ${hrvMs.toFixed(0)}ms · ${hrvQualifier}` `` | `` `Heart-rate variability is ${hrvMs.toFixed(0)}ms vs your 30-day average of ${hrvBase.toFixed(0)}ms (${hrvPct>=0?"+":""}${hrvPct.toFixed(0)}%). Higher usually means more recovered.` `` |
| `rhrDelta > 0.03` | `` `Resting pulse ${rhr.toFixed(0)} · elevated` `` | `` `Resting heart rate ${rhr.toFixed(0)} bpm is above your ${rhrBase.toFixed(0)} bpm baseline — often a sign of fatigue or oncoming illness.` `` |
| `hrvDelta >= 0 && rhrDelta <= 0` | `Recovery steady` | `HRV and resting pulse are both in your normal range.` |

**Load (`scoring/load.ts`)** — `yStrain = input.yesterdayStrain`, `acr =
input.acuteChronicRatio`. Strain qualifier: `yStrain < 4 ? "Rest day yesterday"
: yStrain < 10 ? \`Light day yesterday (strain ${yStrain.toFixed(0)})\` :
\`Hard day yesterday (strain ${yStrain.toFixed(0)})\``. Balance qualifier:
`acr > 1.3 ? "ramping up" : acr < 0.7 ? "backing off" : "balanced"`.

| Condition | `text` | `detail` |
|---|---|---|
| always (freshness) | strain qualifier above | `` `Strain rates how hard training was, 0–21. Yesterday was ${yStrain.toFixed(1)}.` `` |
| always (balance) | `` `Training load ${balanceQualifier}` `` | `` `Your last 7 days of training vs your usual 28-day level is ${acr.toFixed(2)}× (0.8–1.3 is the healthy zone).` `` |
| `acr > 1.3` | `Training load spiking` | `` `The last week is well above your norm (${acr.toFixed(2)}×); injury risk rises above 1.3×.` `` |

Ordering within each pillar is preserved from the current code so the primary
driver stays first.

## 2. Today rendering (iOS)

- `PillarScore.drivers` becomes `[Driver]` in `ios/ReadinessCoach/Models/DTOs.swift`:
  `struct Driver: Codable, Hashable { let text: String; let detail: String? }`.
- **Pillar card** (`TodayView.PillarRow`): render each `driver.text` on its own line
  (replaces the current `drivers.joined(separator: " · ")`).
- **Pillar tap sheet** (`PillarDetailSheet`): under "Today's drivers", render each
  driver as `text` in the row title with `detail` as a secondary line beneath it
  (when present). Falls back to `text` only when `detail` is nil.
- **Low-confidence banner** (`TodayView`): map raw missing keys to friendly names via
  a small helper — `sleep → "sleep"`, `hrv → "heart-rate variability"`,
  `resting_heart_rate → "resting pulse"` — and use plain copy:
  `"Some data is missing today (<friendly list>), so we're keeping the call cautious."`
  The existing `InfoBadge` on the banner stays.
- **Decision/score meaning**: `Decision.meaning` (added in usability-v1) already gives
  the plain "what this means" line under the chip; keep as-is. No score-math text added.

## 3. Chart scrubber (iOS, Body + Trends)

New reusable component `ios/ReadinessCoach/Views/ChartScrubber.swift`:

- A generic value type `ScrubPoint { date: Date; label: String }` and a view modifier
  `func chartScrub(points: [Date], selection: Binding<Date?>) -> some View` that adds a
  `chartOverlay { proxy in ... }` containing a clear, `contentShape(Rectangle())` drag
  surface with `DragGesture(minimumDistance: 0)`. On change: convert the touch x to a
  plot value via `proxy.value(atX:) as Date?`, snap to the nearest element of `points`,
  and write it to `selection`; on end: leave the selection (persists until next drag) —
  a tap elsewhere / new drag moves it. (Rationale: keeping the last reading visible is
  friendlier than clearing on release.)
- Each chart adds a `RuleMark(x: .value("Date", selected))` with a `.annotation` that
  shows the date plus the exact value(s) at that date, looked up from the chart's own
  data. Multi-series charts (Trends pillars) show all three series values in the
  annotation; the Body HR band shows min/avg/max.
- Applied in `BodyView` (HRV line, RHR line, HR min/avg/max band — each with its own
  `@State private var selected: Date?`) and `TrendsView` (readiness line, pillar
  multi-series). Each chart owns its selection state; selections are independent.

## Components (new/changed)

- Change: `backend/src/scoring/types.ts` (`Driver`, `PillarScore.drivers`),
  `scoring/sleep.ts`, `scoring/recovery.ts`, `scoring/load.ts` (build `Driver[]`).
- Change: `backend` scoring unit tests that assert driver strings → assert `{text, detail}`.
- Change: `ios/.../Models/DTOs.swift` (`Driver`, `PillarScore.drivers: [Driver]`).
- Change: `ios/.../Views/TodayView.swift` (`PillarRow` render, banner copy),
  `ios/.../Views/PillarDetailSheet.swift` (text + detail rows).
- New: `ios/.../Views/ChartScrubber.swift`; changes to `BodyView.swift`, `TrendsView.swift`.

## Testing & verification

- **Backend**: `npm test` — update the sleep/recovery/load scoring tests to the new
  `Driver` shape; confirm each condition yields the expected `text`/`detail`. All other
  suites (integration, web) must stay green.
- **iOS** (no test target): build with the usability-v1 command
  (`xcodebuild ... -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build` → `** BUILD SUCCEEDED **`),
  install to a booted simulator against the running backend, screenshot Today (plain
  drivers), a pillar sheet (text + detail), and Body/Trends with the scrubber active.

## Success criteria

- No raw jargon on Today: every pillar line reads as plain language with a number and a
  qualifier; "Sleep debt 3.0h" is gone in favor of "3h catch-up owed this week".
- Tapping a pillar shows, per driver, the concise line plus an exact explanation with
  units and timeframe.
- The low-confidence banner names missing data in human terms.
- Dragging across a Body or Trends chart shows a marker with the date and precise
  value(s) at the touched point, on every chart on those two tabs.
