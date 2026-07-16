# Dedicated Sleep Tab — Design

Date: 2026-07-15  
Status: Approved — implementing  
Branch target: `ios-app-tasks-10-12`

## Goal

Make **Sleep** a first-class section of the app — its own bottom tab — with the same interaction pattern as **Insights** (7d / 30d / 90d, tappable nights, detailed stage readouts). Sleep must no longer live primarily as a sheet tucked under Insights.

## Decision lock

| Choice | Result |
|--------|--------|
| Tab bar | **A** — sixth tab: Today · Insights · **Sleep** · Activity · Body · You |
| Approach | Rebuild Sleep as an Insights-style screen (not a thin sheet wrapper) |
| Visual language | Match Aether: `Palette`, screen-head (Eyebrow + title), `SegmentedRange`, `SectionCard` / `.card()`, `pageWidthLocked` + `verticalScrollLocked`, hidden nav bar |

## Non-goals

- Backend API redesign (existing `/v1/sleep?days=1…90` is enough)
- Changing readiness scoring weights
- Watch complication / widgets
- Replacing Body or Activity tabs

## Navigation

### Tab bar order & tags

```
0 Today
1 Insights
2 Sleep      ← new (bed.double.fill)
3 Activity   ← was 2
4 Body       ← was 3
5 You        ← was 4
```

Update `AppTab` raw values and `MainTabView` accordingly. Bump version stamp so device installs are verifiable.

### Cross-links (no sheets as primary path)

- **Today → Sleep tile:** `tabs.go(to: .sleep)` (remove `showSleepDetail` sheet)
- **Insights → Sleep insight card / Sleep details row:** `tabs.go(to: .sleep)` (remove sheet)
- Remove Insights `SleepChartsSection` / sleep entry sheet path entirely (Insights stays readiness + pillars only)

## Sleep screen structure (top → bottom)

Matches Insights rhythm: one composition per section; warm Aether palette; no purple-on-white chrome; lavender is already the sleep token (`Palette.lavender`).

1. **Screen head** — Eyebrow `Rest` · title `Sleep` (30pt rounded bold, same as Insights/Activity)
2. **Range control** — shared `SegmentedRange(["7d","30d","90d"], …)`; default **30d** (same default index as Insights)
3. **Selected-night card** — defaults to latest night with `durationHours > 0`
   - Duration vs 8h need + qualifier copy
   - Bed → wake clocks when available
   - Consistency line (± minutes) when ≥3 bedtimes in window
   - Stage rows: Deep / REM / Core / Awake (hours) + restorative (deep+REM)
   - Short explainers via existing `InfoBadge` pattern
4. **Night strip** — tappable bars for nights in range (Insights-style day bars), selecting updates the card above
5. **Total sleep chart** — bar marks: total hours + restorative overlay for selected range
6. **Stages by night chart** — stacked / series bars Deep · REM · Core · Awake for selected range
7. **Empty / loading / error** — `ContentUnavailableCompat` + `ErrorCard` (sync from Today messaging)

### Range behavior

- On range change: reload `client.getSleep(days:)` with 7 / 30 / 90; clear selection then default to last night with data
- Chart X-axis uses existing `ChartDate.day`
- Chart styling uses `Palette.lavender` (and stage colors consistent with current Sleep charts: lavender / purple / blue / warn) — not Insights coral for sleep-primary ink

## Visual / UX parity checklist (match rest of app)

- [ ] `NavigationStack` + hidden toolbar for custom screen-head
- [ ] `ScrollView(.vertical)` + `.pageWidthLocked()` + `.padding()` + `.verticalScrollLocked()` + `.screenBackground()`
- [ ] `.refreshable` + `.task` load pattern like Insights/Body
- [ ] Cards via `SectionCard` / `.card()` (shadows on background shapes — do not inflate horizontal scroll)
- [ ] Typography: rounded titles, caption secondary, monospaced digits where appropriate
- [ ] No horizontal page drag regressions (same scroll shell as Insights)

## Data

- **Endpoint:** `GET /v1/sleep?days={7|30|90}` (already capped 1…90 in backend)
- **DTO:** existing `SleepDetailResponse` / `SleepDay` / `SleepStages`
- **Filter:** treat `durationHours <= 0` as empty nights for strip/selection
- No new backend work unless device testing finds `days=90` missing stages (then investigate sync, not UI)

## Files likely touched

| File | Change |
|------|--------|
| `RootView.swift` | Insert Sleep tab; renumber `AppTab` |
| `SleepView.swift` | Full Insights-parity rebuild; drop sheet-dismiss mode as primary |
| `TrendsView.swift` | Remove sleep sheet + entry card; Sleep insight → `tabs.go(.sleep)` |
| `TodayView.swift` | Sleep tile → `tabs.go(.sleep)`; remove sleep sheet |
| `Theme.swift` + `project.pbxproj` + `project.yml` | Stamp **1.2.0 (9)** (feature-level bump) |

## Testing / accept criteria

1. You/Today show **v1.2.0 (9)** after Clean + Run  
2. Tab bar shows six items; Sleep opens dedicated screen  
3. 7d / 30d / 90d reload charts and night strip  
4. Tapping a night updates stages + summary for that night  
5. Today Sleep tile and Insights Sleep card switch to Sleep tab  
6. Insights no longer embeds long sleep charts or a sleep sheet  
7. Sleep tab does not rubber-band left/right  

## Out of scope follow-ups

- Hypnogram / timeline for a single night (needs richer sample timeline than daily stage totals)
- Coach narrative specific to sleep stages
