# Redesign v2 — Design Proposal

**Date:** 2026-10-02
**Status:** Approved 2026-10-02. Decisions after review: keep a simplified ring around the score; dark-only for the first PR (tokens are structured so light can be added later); a small XCTest target for pure logic; foundation + Today ship as a standalone PR before the pillar tabs.
**Scope (locked with user):** iOS app only. New visual identity **and** new information architecture. The web dashboard and backend are untouched.
**Supersedes:** the July "Aether" redesign (`2026-07-14-aether-redesign-design.md`).

## Why change it

Problems in the current app, taken from the code:

1. **Six tabs, nine screens, no hierarchy.** Today, Insights, Sleep, Activity, Body and You sit in a page-swipe `TabView` behind a custom floating bar with 9pt labels. Horizontal page swipe also competes with chart scrubbing.
2. **The tabs don't map to the score.** Readiness is built from three pillars (Recovery 40%, Sleep 35%, Load 25%). The tabs are organised by data type instead (Body, Sleep, Activity, Insights), so the app never shows *why* the score is what it is.
3. **Today is overloaded.** Up to five banners, a hero card, a mini-stat row that repeats the tiles below it, four metric tiles, a sparkline, the advisor card and an Ask button. The one thing the user opens the app for (what to do today) competes with all of it.
4. **Duplication.** Strain and Load tiles overlap. Sleep appears in the hero mini-stats, in a tile, and as its own tab. Settings is reachable from both Today's gear icon and the You tab.
5. **Look.** Everything is a shadowed card. Mono uppercase eyebrows are on every section. The app is forced dark (`.preferredColorScheme(.dark)`). A `WidthPinnedVerticalScroll` hack exists because the hero's shadows overflow.

## Information architecture

Four tabs, one per scoring concept, using a native `TabView`:

| Tab | Role | Content (all existing endpoints) |
|---|---|---|
| **Today** | The decision | Decision, score, one-line meaning, the advisor prescription, a three-pillar breakdown, "Ask the coach" |
| **Recovery** | Pillar: 40% | Pillar score + drivers, HRV and resting HR trends, heart-rate daily range (the current Body tab) |
| **Sleep** | Pillar: 35% | Pillar score + drivers, last night with hypnogram, total sleep and stage charts |
| **Train** | Pillar: 25% | Pillar score + drivers, weekly strain/load, workout list with detail |

Everything else moves out of the tab bar:

- **Readiness history** (the current Insights tab: 7/30/90-day readiness trend and pillar scores over time) becomes a pushed screen, opened from the Today score.
- **Profile and settings** (the current You tab and the Settings sheet) become one screen, opened from an avatar button in Today's navigation bar. One entry point, not two.
- **Ask the coach** stays a sheet. It is docked at the bottom of Today and is a toolbar button on the three pillar tabs.

Each pillar tab has the same shape: **score and drivers first, then trends, then raw detail.** This is the "why" layer behind Today.

## Today layout

Top to bottom:

1. Native navigation bar: Today title, avatar button (profile and settings), sync control; date in the scroll content.
2. **Decision block.** A thin, flat ring (no glow, no card) holding the score numeral, beside the decision word in a serif face ("Maintain") and one line of meaning. Tapping the score opens History.
3. **Pillar breakdown.** Three rows (Recovery, Sleep, Load), each with its score, its weight, and a thin bar in the pillar colour. Tapping a row jumps to that pillar's tab.
4. **Advisor.** The prescription first, then the "why" lines, then "if ignored".
5. **Ask the coach** docked at the bottom.

Status banners (offline, stale, calibrating, low confidence, Health access, upload pending) collapse into **one** status line that expands on tap, instead of up to five stacked banners. The behaviour behind each state is unchanged.

The mini-stat row, the separate Strain tile and the Today sparkline are removed. Their content lives on the pillar tabs and the history screen.

## Visual identity

Direction: **quiet and editorial.** Large numerals, generous space, flat surfaces. A health app should feel calm, not like a game HUD.

- **Dark first.** The first PR stays dark-only (it is how the app is used — mornings, gym). Tokens live in one place so a light scheme is a token change, not a rewrite.
- **Flat surfaces.** Grouped-background plus white/near-black surfaces with hairline separators. No card shadows, no radial glows.
- **Type.** SF Pro for UI, native titles and numerals, with tabular figures. The New York serif (`.design(.serif)`, a system font, so no licensing or bundling) for the decision word. Mono uppercase eyebrows are replaced by sentence-case labels.
- **Colour.** One hue per pillar, plus a separate green/amber/red decision set. The dark categorical values were tuned with all-pairs colour-vision-deficiency validation and contrast checks against the dark surface. Light values remain unimplemented starting points:

| Token | Dark (this PR) | Light (later) |
|---|---|---|
| background | `#0E0F12` | `#F6F4EF` |
| surface | `#17191E` | `#FFFFFF` |
| ink | `#F2F2F0` | `#16181D` |
| Recovery | `#2CA5BF` | `#00A2C7` |
| Sleep | `#8474CE` | `#6E56CF` |
| Load | `#9C477B` | `#D6409F` |
| Push / Maintain / Recover | `#3DD68C` / `#F0B429` / `#F0605B` | `#30A46C` / `#E5A00D` / `#E5484D` |

- **Motion.** The score numeral immediately shows the server value; the ring arc and pillar bars fill on appear. Reduce Motion disables those entrance animations and status expansion animation.
- **Navigation chrome.** Native `TabView` and `NavigationStack`, with inline native navigation titles on migrated screens. Large titles were absent while reserving header space in the iOS 26.5 simulator; inline titles rendered correctly. Native chrome adapts to the OS; minimum iOS remains 17. The custom `AetherTabBar`, `liquidGlassChrome()` and page-swipe `TabView` are deleted.
- **Accessibility.** New Today components use semantic Dynamic Type, a scaled ring and stacked layouts at accessibility sizes, and VoiceOver labels that include pillar drivers. Existing pillar-screen typography is deferred to phase 3.

## Invariants (unchanged)

- The decision and score are rendered verbatim from `today.decision` / `today.readiness`. Nothing in the UI computes or overrides them, and the advisor can never make the call more aggressive.
- No fabricated metrics. Only data from existing endpoints is shown. Pillar weights shown (40/35/25) are the real ones used by the backend.
- Calibrating and low-confidence states stay visible and honest, not hidden by the status-line collapse.
- Sync, freshness, background delivery, the daily notification and onboarding keep their current behaviour. This pass restyles them but does not change the services.

## What changes in the codebase

- `Theme.swift` and `Components.swift`: dark-only tokens and flat shared styling, plus new `PillarRow`, `DecisionBlock` (including the simplified ring) and `StatusLine` components. Light-mode tokens are deferred.
- `RootView.swift`: new 4-tab `MainTabView`. `AetherTabBar`, `liquidGlassChrome`, `WidthPinnedVerticalScroll` and the `TabRouter` page indices are removed or reduced.
- `TodayView.swift`: rebuilt.
- `BodyView` becomes the Recovery tab. `SleepView` and `TrainView` gain the pillar header. `TrendsView` becomes the pushed History screen. `YouView` and `SettingsView` merge into one Profile screen.
- No changes to `Models/`, `Networking/`, `Services/`, or anything under `backend/` and `web/`.

## Phasing

Each phase ends with passing simulator checks and screenshot inspection. UI verification uses a localhost-only synthetic fixture API, not seeded production Health data.

1. **Foundation (first PR):** dark tokens, type styles, base components, native four-tab shell. Existing pillar screens still render.
2. **Today (first PR):** decision block, pillar breakdown, single status line, advisor, docked Ask. The score pushes History; the avatar pushes existing Settings; duplicate You is removed. A Details menu keeps every scoring driver reachable without rebuilding pillar screens. History also remains reachable when Today has no score.
3. **Pillar tabs (later):** Recovery, Sleep, Train with the shared pillar header. Existing Body/Activity in-content titles remain until this phase.
4. **History and Profile (later):** deeper polish of the pushed History and combined Profile/settings screens. The first PR includes migration fixes: request supersession, dated latest-snapshot cards, local calendar-day parsing and an accessible daily-score list.
5. **Onboarding and polish (later):** onboarding restyle, full-screen accessibility pass, light mode, app icon review. The first PR only corrects prominent-button contrast on onboarding and keeps the current icon.

## Verification

- `xcodebuild` for the iPhone simulator, green at the end of each phase. The simulator app is killed before each relaunch so a stale binary can't hide a change.
- Screenshots of every screen in dark, at the default size, plus the largest Dynamic Type size on Today; and the loading, empty, error, offline, low-confidence and calibrating states.
- The app-hosted XCTest target now has 31 tests: duration formatting, pillar weights/routing, status selection and collapsed summary, missing-signal Health remediation, text/action/mark/pill-label contrast, Gregorian server-day parsing across time zones/calendars, dated Ask context, History range isolation and unit-test launch isolation. The test host bypasses live app startup without instantiating account/sync state or starting notifications. See `ios/README.md` for the command.
- Unsigned simulator verification covers the Health authorization error alert, not real read permissions. HealthKit request completion cannot prove read authorization; missing signals offer a Health-settings check without claiming permission denial. Real Watch uploads, background delivery and notification behavior remain signed physical-device checks.
- XcodeGen regeneration and runtime behavior on iOS 17 are not verified here; the checked-in project builds/tests on iOS 26.5, with its deployment target still 17.
- Independent review of the assembled diff before any PR, per the repo's review rules.

### First-phase verification record — 2026-10-03

- 31 XCTest tests pass on the iPhone 17 / iOS 26.5 simulator. No services, backend or networking implementation was changed. Date parsing and freshness display use Gregorian server-day semantics without constructing a formatter per mark. Chart selections retain their source time zone in parent state, including while empty responses remove their overlays; a regression verifies restored data matches the selected day after travel. Recovery is changed only for that shared selection binding, not redesigned.
- The actual app was driven on iPhone 17 Pro with localhost-only synthetic responses: all three pillar-row destinations; pushed History and Settings; all scoring drivers (including a second driver/detail); Ask disabled-empty, loading, server-error and retry-success states; and an explicitly dated stale Ask request.
- Today loading, no-cache error with History still reachable, cached-offline and expanded stale explanations were exercised. History empty/error states, rapid range changes and a real 60-second request timeout were exercised; old-range data stays hidden when the selected range fails.
- Default and largest Dynamic Type screenshots were inspected. The final installed build's Recovery and History charts were tapped to select another day and their readouts checked; Recovery retained that day after an empty response removed the charts and a retry restored them. Actual system time-zone travel was not exercised; zone rebasing is covered by the model tests.
- Independent review findings were resolved, and the final focused cold review of chart selection returned no findings.
- Real Health read authorization, Watch/background sync, iOS 17 runtime, and system Reduce Motion behavior were not verified on a signed physical device. Reduce Motion branches were inspected, not toggled in system settings.

### Existing API issue, outside this iOS-only PR

The committed baseline's Ask contract already lacks a scoring time-zone offset:
`APIClient.ask` sends `userId`, `question` and `date`, and
`backend/src/routes/coach.ts` calls `getToday` without an offset (UTC default).
Today requests do send the device's offset. The same dated Health data can
therefore yield different sleep windows/decisions between Today and Ask for
non-UTC users. The redesigned sheet preserves and displays its snapshot **date**
and shows the returned server decision, but cannot repair the missing server
contract from the UI. A backend/client contract follow-up is required; no
backend change is included here, and fixture Ask verification is not evidence
that the production scoring contexts match.

### Existing Recovery refresh behavior, deferred with the pillar screens

Simulator pull-to-refresh on the existing Recovery screen surfaced a `cancelled`
error; Retry succeeded and restored the selected day. This phase leaves its
baseline `load()` implementation unchanged. Cancellation handling should be
rechecked during the detailed pillar-screen phase rather than silently changed
as part of the visual foundation.

## Resolved questions

1. **XCTest target:** added, kept small (status-line resolution, duration formatting, missing-metric naming).
2. **Minimum iOS:** stays 17. Liquid Glass chrome arrives automatically on 26 through the native `TabView`.
3. **App icon:** kept.
4. **Palette:** the dark values above pass all-pairs CVD separation (worst simulated ΔE 8.2), normal-vision separation (worst ΔE 15.1) and mark contrast ≥3:1 on `#17191E`. Primary, secondary and tertiary text pass ≥4.5:1 on all three dark surfaces; prominent actions use dark text on the bone-white fill. Light values are still proposals.
