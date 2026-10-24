# Redesign v3: Whoop-grade look and instant sections

**Date:** 2026-10-23
**Status:** Draft for Shawn's approval
**Supersedes:** the visual layer of `2026-10-02-redesign-v2-design.md`. v2's four-tab information architecture, invariants and test target stay; its "quiet editorial" look and per-tab loading are replaced.

## Why

Shawn's words: every section "looks very beginner", it still looks like the old UI section by section, and moving between sections is slow. He wants it closer to **Whoop**, mixed with whatever else makes it look better, and to feel polished, professional and user-friendly.

What the code shows (2026-10-23, branch `redesign-v2-foundation-today`):

**Why it feels slow**

1. **Every tab refetches from scratch on every visit.** `BodyView`, `SleepView` and `TrainView` each own private `@State` and run `.task { await load() }`, which reruns every time the tab appears. Nothing is cached, so every switch waits on the network.
2. **Recovery makes a second full score computation.** `BodyView.load()` calls `getBody` and then `getToday()` just to read `pillars`, which the app already has in `SyncService.today`. On the server, `getToday` reruns `computeScore` (six queries over raw samples) and an advisor-note lookup.
3. **The Recovery endpoint ships raw heart rate through Node.** `getBodyDetails` loads every `heart_rate`, `hrv_sdnn` and `resting_heart_rate` sample for 30 days (tens of thousands of rows) and aggregates them in JavaScript.
4. **`getToday` is recomputed on every call.** Nothing is memoized between syncs; launch, foreground, pull-to-refresh and the Recovery tab all pay full price.
5. **Sleep ships up to 90 nights of hypnogram segments** (7/30/90 range) when the screen draws one night's hypnogram at a time.
6. **Whole-app re-renders.** `SyncService` is an `ObservableObject` injected everywhere. Any `@Published` change (for example `uploadingCount` ticking down during an upload) invalidates every view that holds it.
7. **Leftover Render cold-start code.** `wakeServer()` plus a fixed 2.5 s sleep-and-retry exist for a free host that no longer exists; the API now lives on Family Host.
8. **Formatter churn.** `ISO8601DateFormatter()` / `DateFormatter()` are constructed per call in `TrainView` (two helpers), `StatusLine` and `APIClient.deviceLocalDate`. (`SleepView` already uses a static parser.)
9. **History and Today can disagree.** `getReadinessHistory` backfills missing days with `computeScore` at tz=0 while Today passes the device offset, and each recompute overwrites the `DailyScore` row.

These are hypotheses ranked by likely impact. Phase 1 measures them first (see "Performance targets").

**Why it looks beginner**

- Every section is the same flat rounded rectangle with a small label on top (`SectionCard` + `Eyebrow`), so all screens read as a stack of identical boxes.
- No visual anchor per screen: pillar tabs open on a text header and a "Readout" card rather than a score.
- Numbers are body-sized; nothing is big, bold or confident.
- Mixed leftovers from three design eras (Aether chips and `AetherRowTone`, v2 editorial, original cards).
- Spinners instead of content-shaped placeholders; no transitions, no haptics.

## Goals

1. Every section opens **instantly** from cache and quietly refreshes.
2. A cohesive, premium, dark look in the spirit of Whoop (direction "C · Rings + plan", chosen by Shawn from three mockups): a big numeral and verdict word anchor each screen, content runs edge to edge on the black canvas, and sections are separated by hairlines and space, never by boxed cards.
3. Each of the four tabs follows the same template, so the app feels designed as one system.
4. Understandable at a glance: every number says what it is, whether it's good, and how it compares to normal for Shawn.

## Non-goals

- No change to how the score or decision is computed. The backend scoring is the source of truth.
- Web dashboard untouched.
- No light mode in this pass (tokens stay structured for it).
- No new data sources (no SpO₂/respiratory/skin temp screens unless already synced and exposed).
- No social, journal, or teams features from Whoop.

## Anti-goals (would be a failure even if it works)

- A copy of Whoop's branding, fonts or exact colors.
- Fabricated or decorative numbers. Every figure comes from an endpoint or a clearly labeled client-side average of endpoint data.
- A redesign that is slower, or that hides calibrating, low-confidence, stale or offline states to look cleaner.
- Busy screens: glows, gradients and animation everywhere.

## Invariants (carried over from v2)

- Decision and readiness rendered verbatim from `today.decision` / `today.readiness`; the advisor can never make the call more aggressive.
- Pillar weights shown are the real ones (Recovery 40, Sleep 35, Load 25).
- Calibrating, low-confidence, stale, offline and Health-access states stay visible.
- Sync, background delivery, notifications, onboarding auth flow keep their behavior.
- Health data cached on disk keeps complete file protection and is excluded from backups.

## Information architecture

Unchanged from v2: native `TabView` with **Today, Recovery, Sleep, Train**; History is pushed from the Today head numeral; Profile & settings from the avatar; Ask the coach is a sheet.

**Past days live in History, not on Today.** Calling `/v1/today` for a past date overwrites that day's `DailyScore` and can trigger a paid LLM note, so Today stays on today. History rows open a read-only **Day summary** built from the history response (score, decision, three pillar scores) with no coach note and no recompute.

## Screen template (all four tabs)

Shawn's feedback on the first mockup was that the boxed sections still looked like the current app. So: **no cards.** Nothing sits in a rounded rectangle except the Ask bar and segmented controls. Sections are open, edge to edge within 20pt side margins, separated by 1px hairlines and spacing.

```
[ nav: date (Today) or title + date (pillar tabs) · avatar ]
[ HEAD: huge condensed numeral (~64pt) left; verdict word in band/decision color + one-line meaning to its right ]
[ STATUS LINE (only when something needs attention) ]
[ tab-specific hero visual: pillar rings (Today), trend chart (Recovery), night strip (Sleep), week bars (Train) ]
[ sections: sentence-case 15pt semibold title, optional segmented control at the right, content below ]
[ "Compared with normal": hairline rows of metric · today · normal · ▲/▼ delta ]
```

### Today

- Head: readiness numeral, decision word (Push / Maintain / Recover) in decision color, "Readiness · <one-line meaning>". Tap → History.
- **Three equal pillar rings** (Recovery, Sleep, Load), ~96pt, ring in pillar identity color, numeral white when ≥75 and amber/red when below; tap → that tab. Weights live in the ring's VoiceOver label and the pillar tab, not on the ring.
- **Today's plan**: the advisor prescription as a 20pt bold headline, one "why" line with a chevron that expands the full reasons and "If ignored".
- **Vitals strip**: horizontally scrolling columns (HRV, resting HR, sleep, 7-day load), each with value, unit and a 14-day sparkline colored by whether the trend is good (green/red/gray). Values, normals and sparkline series come from the `baselines` field on `/v1/today`.
- **Ask bar**: a docked "Ask the coach anything…" field that opens the Ask sheet.

### Recovery (pillar 40%)

- Head: Recovery score, "RECOVERY" in band color, one-line meaning; driver chips (outlined pills) under it.
- Hero: 30-day HRV/RHR area chart with a metric toggle and a dashed 30-day-normal line; 7D/30D via tap-and-hold scrub range.
- Compared with normal: HRV and resting HR, from `/v1/today` `baselines`. Heart-rate daily range is shown only once the server supplies its normal (see Backend, "Comparison normals not yet supplied").
- Detail: daily list of the last 7 days as hairline rows.

### Sleep (pillar 35%)

- Head: Sleep score, "SLEEP" in band color, "7h 12m · 11:48 PM – 7:20 AM".
- Nights strip: bars of hours per night for the 7/30/90 range (segmented control at the right of the section title), latest highlighted; selecting a night updates everything below.
- Selected night: hypnogram with time axis, then a stacked stage bar with Deep / REM / Core / Awake durations.
- Sleep stage colors (hypnogram, stage bar and legend dots): Awake `#F5A35C` (warm orange), REM `#7DD3FC` (sky), Core `#3F7FE8` (blue), Deep `#6A4BD8` (indigo). Lighter means lighter sleep; Awake is the only warm color so wake-ups stand out. These replace the earlier all-purple shades, which were hard to tell apart. The Sleep identity purple `#8474CE` stays on the nights bars and the Today ring.
- Compared with normal: total sleep, from `/v1/today` `baselines`. Restorative sleep and bedtime are shown only once the server supplies their normals (see Backend, "Comparison normals not yet supplied").

### Train (pillar 25%, "Load")

- Head: Load score, "LOAD" in band color, "412 strain this week · 361 last".
- This week: 7 daily strain bars (rest days as a flat stub).
- Workouts: sport filter as a segmented control at the right of the title; list grouped under day labels; each row has a circular SF Symbol badge tinted by sport, name, "duration · avg HR", strain numeral. Tap → workout detail with HR zones bar.

### History (pushed)

Readiness 7/30/90 bars colored by decision, scrub to see that day's three pillar scores; tapping a day opens the read-only Day summary.

### Profile & settings, Ask, Onboarding

Restyled with the same tokens and components; behavior unchanged. Ask shows the locked decision chip at top and the answer as a styled message.

## Visual system

**Direction:** dark, confident, data-first. Big condensed numerals, bright color reserved for scores, everything else monochrome.

- **Canvas:** near-black `#07080A`, flat. **No cards**: content sits on the canvas, separated by 1px hairlines `#FFFFFF10`-`#FFFFFF12` and spacing. The only filled surface is `#15171B` for the Ask bar, segmented controls and sheets. No shadows; the one glow is a soft one on ring fills.
- **Numerals:** SF Pro **Compressed/Condensed** (`.fontWidth(.compressed)` / `.condensed`, iOS 16+, system font, no licensing), heavy weight, tabular. Head numeral ~64pt, ring numerals ~26pt, row values ~20pt. Scaled with Dynamic Type.
- **Text:** SF Pro for body. Section titles are sentence case, 15pt semibold, white; no uppercase eyebrow labels. The only uppercase, letter-spaced text is the verdict word next to the head numeral.
- **Score color bands** apply to 0-100 scores only (pillar-tab verdict words and the colors below 75 on ring numerals): ≥75 green `#3DD68C`, 50-74 amber `#F0B429`, <50 red `#F0605B`, matching the backend's `decisionFromScore` thresholds and the existing `Palette.band(for:)`. A ring numeral at ≥75 is always white, never green. Comparison deltas are not scores and never use these thresholds; they use each metric's server neutral band (see Baseline arrows).
- **Today's verdict word is colored by `today.decision`, not by its score band.** Overrides (for example under 5 h of sleep) can make the decision more conservative than the score alone; it must never look greener than the locked call.
- **Pillar identity colors** (v2's CVD-validated set) are used for icons, chart lines and pillar labels, never for good/bad meaning.
- **Rings:** used only for the three pillars on Today. 270° arc, rounded caps, track at 8% white, fill in the pillar identity color with a soft glow; the numeral inside carries the band (white ≥75, amber 50-74, red <50) so a weak pillar still reads as weak.
- **Verdict word:** next to each head numeral, uppercase and letter-spaced, in the band color (pillar tabs) or decision color (Today).
- **Baseline arrows:** green when the change is good for that metric (HRV up, RHR down), red when bad, gray within the neutral band. Baselines and neutral bands come from the server (the same numbers the scoring uses), never a client-side average, so an arrow can't contradict a driver. Never color alone: arrow direction + "+6 ms" text.
- **Charts:** Swift Charts, edge to edge within margins, no gridlines or axes except a dashed 30-day-normal rule and sparse time labels; rounded bars; line with soft area fill. Sparklines on Today have no axes.
- **Motion:** ring sweeps and numeral counts up on first appearance per session (not on every tab switch); skeleton placeholders shaped like the final layout while loading; `.sensoryFeedback` on refresh completion and tab-to-pillar jumps; numeric `contentTransition` when values update. Reduce Motion turns sweeps and count-ups off.
- **Accessibility:** WCAG AA contrast on all text; Dynamic Type through accessibility sizes (ring row stacks vertically, vitals strip becomes a vertical list); VoiceOver labels read "Recovery 72 of 100, 40 percent of readiness, HRV above baseline".
- **Icon:** kept.

## Data and performance architecture

### iOS

1. **One `AppStore`** (`@Observable`, iOS 17) owns `today`, `body`, `sleep`, `train`, `history` as `Resource<T>` values: `{ value, fetchedAt, isRefreshing, error }`. Views read only the fields they need, so an upload counter no longer re-renders charts. `SyncService` keeps sync/upload logic and writes into the store.
2. **Stale-while-revalidate disk cache per resource**, generalizing today's `cached-today.json` (same file protection and backup exclusion), keyed by user and date. Tabs render cached data immediately. The old `cached-today.json` records no owner, so it is deleted rather than migrated; the first launch after upgrading fetches Today once.
3. **Prefetch:** after Today loads (launch, foreground, post-sync), fetch body, sleep and train in parallel in the background. Revalidate a resource on tab appear only if older than 5 minutes or a sync uploaded new samples since it was fetched.
4. **Remove** the extra `getToday` in Recovery, `wakeServer()`, and the fixed 2.5 s retry sleep (replace with one immediate retry on transport error). Lower the read timeout from 60 s to 15 s; uploads keep their longer timeout.
5. **Precompute view models** (chart series, baselines, arrows) once when a resource changes, not inside `body`. Shared static formatters.
6. `LazyVStack` for long lists (workouts, history days).

### Backend

1. **Memoize `getToday`** in an in-process LRU keyed `(userId, date, tz)`. An entry expires at the earliest of: 10 minutes, the end of that date's sleep window (when `sleepPending` flips), any sync for the user, a change to `sleepNeedHours`, or account deletion. The builder confirms Family Host runs a single API instance; if it runs more, use a short TTL only and skip cross-instance invalidation.
2. **Add `baselines` to `/v1/today`** (additive): for HRV, resting HR, sleep hours and 7-day load, `{ today, baseline30d, neutralBand, recent14d }` taken from the values `computeScore` already uses; `recent14d` is the daily series (oldest first, nulls for missing days) that feeds the Today sparklines. Phase 1 covers these four metrics only.
3. **History uses the caller's tz** (additive `tz` param, defaulting to today's 0 behavior) so History and Today agree.
4. **Aggregate body metrics in SQL** (`GROUP BY` local day with `min/avg/max`, plus latest via `DISTINCT ON`) instead of loading raw rows into Node.
5. **Optional sleep timeline trim:** an additive `timelineNights=N` param; when absent, behavior is unchanged so the installed build keeps every hypnogram. The app asks for timelines only for the visible window and fetches an older night's timeline on demand. Only ship this if measurement shows Sleep payload matters.
6. Keep `Cache-Control: private, no-store`; add **ETag/If-None-Match** on read endpoints so unchanged revalidations return 304.
7. **Request timing log** middleware (method, route, status, ms; no user IDs or bodies) so server p95 can be measured.
8. No change to scoring logic or response fields the app relies on; additive changes only, so the current App Store-less build on Shawn's phone keeps working until updated.

**Comparison normals not yet supplied.** The Recovery heart-rate daily range row and the Sleep restorative sleep and bedtime rows have no server normal today: `baselines` carries only HRV, resting HR, sleep hours and 7-day load, and no other endpoint returns a 30-day normal or neutral band for these three. The app must not compute one client-side. These rows are deferred until a data contract exists. Adding it is a prerequisite at the start of Phase 2, before any screen shows the rows:

- Additive fields in `baselines` on `/v1/today`: `hrDailyRange`, `restorativeSleep` and `bedtime`, each in the same `{ today, baseline30d, neutralBand, recent14d, goodDirection }` shape. Units: bpm (daily max minus min), hours, and minutes from the local midnight that begins the wake day for bedtime (so 23:30 is -30 and 00:30 is 30).
- Source: heart-rate samples per local day for the range; the same night summaries `computeScore` uses for restorative hours; the start of the main sleep for bedtime. Each value states which of these it came from in the backend contract and tests.
- Null semantics: `today` is `null` when there is no data for the day; `baseline30d` and `neutralBand` are `null` when fewer than a minimum number of days (set with the band rules) have data. The app hides the row when `today` is `null`, shows "Not enough data yet" with no arrow when `baseline30d` is `null`, and never shows an arrow without a band.
- The band values and minimum-day counts are set and tested with the backend change; this spec does not claim they already exist.

### Performance targets (measured, before and after)

Phase 1 starts by measuring the current numbers on Shawn's iPhone 15 Pro against production, then holds the result to these:

| Measure | Target |
|---|---|
| Tab switch to content, cached | < 100 ms, no spinner |
| Cold launch to cached Today on screen | < 1 s |
| Each read endpoint, server p95 | < 300 ms |
| `/v1/body` response size | < 50 KB |
| Re-renders of chart views during an upload | 0 |

**How to measure.** Server: the new timing middleware, run locally against a production-shaped database (the builder seeds 90 days of synthetic samples at realistic density, about one heart-rate sample per 5 minutes), plus Family Host logs after deploy. App: `os_signpost` intervals read with `xcrun xctrace` on the simulator, then one confirmation run on Shawn's iPhone 15 Pro, which is connected to this Mac and installs via `devicectl`. The localhost synthetic fixture API described in v2 is not in the repo; rebuild it under `ios/Fixtures/` and commit it.

**When to drop a fix.** If a fix's target interval is already under its target, or the fix would cut less than 10% of the measured time, skip it and record the measurement.

## Phasing (each phase is its own PR, reviewed and verified)

Work starts from the latest `origin/main` (v2 was merged as PR #13) in a separate worktree. The uncommitted `lockGuard`/advisor/`Info.plist` edits in the main checkout are separate in-progress work and are not touched or included.

1. **Speed (no visual change):** timing middleware, fixture API and baseline measurements; `AppStore` + caches + prefetch; backend memo, `baselines` field, history tz, SQL aggregation, ETag (sleep trim only if measured); remove Render leftovers. Report before/after numbers.
2. **Design system + Today:** tokens, condensed numerals, head, ring, comparison row, section header, skeletons, chart styles; rebuild Today including the pillar rings, plan section and vitals strip; History Day summary.
3. **Pillar tabs:** Recovery, Sleep, Train on the shared template.
4. **History, Profile & settings, Ask, Onboarding** restyle, final accessibility and Reduce Motion pass.

## Verification

- `xcodebuild test` (existing 31 tests plus new tests for resource staleness, cache keying, arrow direction/color and band mapping); backend `npm test` plus tests for SQL aggregation parity with the current JS aggregation, every memo-expiry trigger, `baselines` matching the drivers, and History/Today agreement for a non-UTC tz.
- Simulator screenshots of every screen at default and largest Dynamic Type, plus loading, empty, error, offline, low-confidence and calibrating states, using the localhost synthetic fixture API from v2.
- Real-device check on the iPhone 15 Pro: before/after timings, tab switching with the network off (cached content still shows), and a full sync.
- Independent cross-family review (Astra) of each PR before merge.

## Decisions I made (for Shawn to check)

- Keep the four tabs from v2; change the look and loading, not the structure.
- Direction C (rings + plan) is Shawn's pick; I extended it to the pillar tabs as: big numeral head, one hero visual, then open sections. Rings appear only on Today.
- Pillar rings use the pillar's own color. The numeral is white at scores of 75 or higher, amber at 50–74, and red below 50, so a weak score remains visible.
- Today's sparklines need 14 days of history, so `baselines` also carries `recent14d`.
- No day stepping on Today; past days open as a read-only summary from History (avoids recompute writes and LLM cost).
- Baseline arrows use server-provided baselines, so they always agree with the score's drivers.
- SF Pro Compressed for numerals instead of a bundled custom font.
- Band colors reuse the decision green/amber/red at the backend's 75/50 cutoffs; Today's verdict follows the locked decision.
- Speed work ships first, before any visual change, so we can prove it got faster.

## Left to the builder

Exact spacing values, chart animation curves, `Resource` API shape, skeleton shapes, SF Symbol per sport (existing `WorkoutSport` mapping), sport badge tints, and the neutral-band values per metric (derived from the existing driver thresholds in `backend/src/scoring`).
