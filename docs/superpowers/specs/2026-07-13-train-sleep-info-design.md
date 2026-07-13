# Readiness Coach — Train & Sleep Info (design)

Date: 2026-07-13
Scope: iOS Sleep + Train tabs, plus one small backend addition to the sleep
detail endpoint. Follows data-clarity-v2.

## Goal

Make the Sleep and Train tabs both **clearer** (explain the jargon already shown
— strain 0–21, HR zones Z1–Z5, deep/REM/core/restorative) and **richer** (a plain
last-night sleep summary with bed/wake times & schedule consistency; a weekly
training summary). Same audience as data-clarity-v2: a user who hasn't already
read their Health data.

## Decisions (locked)

- **Direction**: both — explain existing metrics *and* add context.
- **Sleep depth**: include bed/wake times + schedule consistency (needs the small
  backend addition below).
- **Explanation style**: concise inline captions for everyday info; the existing
  `InfoBadge` (ⓘ) for the "what does this mean" glossary bits (strain scale, sleep
  stages, HR zones, why consistency matters).
- **Tone**: concise / scannable, no emoji — matches the rest of the app.
- **Invariant**: read-only HealthKit; the score/decision are unchanged. This work
  only presents existing data more clearly and adds bed/wake timestamps.

## 1. Backend — bed/wake times

`backend/src/services/todayService.ts`, `getSleepDetails`: add `sleepStart` and
`sleepEnd` (ISO strings, or `null`) to each night, via a new helper:

```ts
/** Earliest asleep-sample start and latest asleep-sample end within a night. */
export function sleepBounds(
  samples: SleepSample[],
  windowStart: Date,
  windowEnd: Date,
): { sleepStart: string | null; sleepEnd: string | null } {
  let start: number | null = null;
  let end: number | null = null;
  for (const sample of samples) {
    const stage = sleepStage(sample.metadata);
    if (stage.includes("awake") || stage.includes("inbed")) continue;
    const s = Math.max(sample.startAt.getTime(), windowStart.getTime());
    const e = Math.min(sample.endAt.getTime(), windowEnd.getTime());
    if (e <= s) continue;
    if (start === null || s < start) start = s;
    if (end === null || e > end) end = e;
  }
  return {
    sleepStart: start === null ? null : new Date(start).toISOString(),
    sleepEnd: end === null ? null : new Date(end).toISOString(),
  };
}
```

Each `getSleepDetails` day spreads `...sleepBounds(samples, window.start, window.end)`.
The `SleepDay`-shaped return type gains `sleepStart: string | null; sleepEnd: string | null`.

iOS `SleepDay` (`ios/ReadinessCoach/Models/DTOs.swift`) gains
`let sleepStart: String?` and `let sleepEnd: String?`.

## 2. Sleep tab (iOS)

New **"Last night" summary card** at the top of `SleepView`, above the charts,
driven by the most recent night (`nights.last`) plus the 30-day series:

- **Duration + target**: `"You slept 7.1h — <qualifier> your 8h target"`, qualifier:
  `>= 7.5 && <= 8.5 → "right on"`, `< 7.5 → "a bit below"` (or `"well below"` if `< 6`),
  `> 8.5 → "above"`. Target is the fixed 8h `needHours` the score uses.
- **Bed/wake**: `"Asleep 12:38 AM → woke 7:24 AM"` from `sleepStart`/`sleepEnd`
  parsed as ISO and formatted with a local-time `.dateTime.hour().minute()` formatter.
  Hidden if either is nil.
- **vs average**: `"vs your 7-day average of 7.6h"` — mean of the last 7 nights'
  `durationHours` (nights with sleep only), computed on-device.
- **Consistency**: `"Schedule: <label> (±<N> min this week)"` with an `InfoBadge`
  (title "Sleep consistency", message "Going to bed and waking at similar times
  helps recovery. This is how much your bedtime varied over the past week.").
  Computed on-device (see algorithm below). Hidden if fewer than 3 nights have `sleepStart`.
- **Restorative**: `"Deep + REM \(fmt(deep+rem))h — the recovery stages"` with an
  `InfoBadge` (title "Sleep stages", message "Deep and REM are when your body and
  brain recover. Core is lighter sleep; Awake is brief wake-ups. Restorative = deep + REM.").

**Consistency algorithm** (bedtime spread, midnight-safe): for each of the last 7
nights with `sleepStart`, take the local time-of-day in minutes, re-anchored to
"minutes since noon" (`(minutesSinceMidnight + 720) % 1440`) so bedtimes on either
side of midnight cluster; compute the standard deviation in minutes. Label:
`<= 30 → "very consistent"`, `<= 60 → "fairly consistent"`, `<= 90 → "a little irregular"`,
`else → "irregular"`. Show `±<round(std)> min`.

The existing **total-sleep** and **stages-by-night** charts stay, with clearer
captions: total → `"Blue is total sleep; darker is deep + REM (restorative)."`;
stages → keep the per-stage legend.

## 3. Train tab (iOS only)

New **weekly summary card** at the top of `TrainView` (last 7 days, from
`response.data` filtered to workouts in the last 7 days by `startAt`):

- `"\(count) sessions · \(totalTime) · \(round(totalStrain)) total strain"` then a
  second line `"Hardest: \(weekdayOf(maxStrainWorkout)) (\(round(maxStrain)))"`.
- `totalTime` formatted `"Xh Ym"` (or `"Ym"` under an hour) from summed `durationMin`.
- Hidden if no workouts in the last 7 days.

**Plainer per-workout metrics** in `WorkoutRow`:

- Strain: `"Strain \(round) · \(band)"` where band: `< 8 → "easy"`, `< 14 → "moderately hard"`,
  `< 18 → "hard"`, `else → "all-out"`. A single `InfoBadge` in the "Workouts" card
  header (title "Strain", message "Strain rates how hard a session was, 0–21, from
  heart rate and duration.").
- HR zones: relabel the caption from `Z1…Z5` to **Easy · Light · Moderate · Hard · Max**
  (`zoneNames = ["Easy","Light","Moderate","Hard","Max"]`), same colored bar; an
  `InfoBadge` (title "Heart-rate zones", message "Zones are shares of your session
  spent at rising heart rates — Easy is a warm-up pace, Max is near your ceiling.").

**Strain chart** (`TrainView`): aggregate **per day** instead of per workout — sum
each day's workout strain into one bar keyed by the calendar day — and title it
`"Daily strain — last \(days) days"`. Keeps the chart readable when a day has two
sessions.

## Components (new/changed)

- Backend: `sleepBounds` in `todayService.ts`; `getSleepDetails` day shape +2 fields; unit test.
- iOS DTO: `SleepDay.sleepStart/sleepEnd` optional strings.
- iOS: `SleepView` (new summary card + consistency/qualifier helpers + captions);
  `TrainView` (weekly summary card + per-day strain aggregation); `WorkoutRow`
  (strain band + zone names + InfoBadges). Reuses existing `InfoBadge`, `SectionCard`.

## Non-goals

- No new HealthKit types or entitlements; no background delivery.
- No sleep/heart-rate scrubber on these charts (Body/Trends already have it; can be
  added later if wanted).
- No change to scoring, decisions, or the sleep window (timezone fix already shipped).

## Success criteria

- Sleep tab opens with a plain last-night summary: hours vs target, bedtime→wake,
  vs 7-day average, and schedule consistency — no HealthKit reading required to
  understand it.
- Every jargon term (strain, HR zones, sleep stages, consistency) has a plain
  inline phrasing and an ⓘ that explains it.
- Train tab shows a weekly summary and per-workout strain in plain "how hard" terms.
- Backend `npm test` green (incl. a `sleepBounds` test); iOS builds clean.
