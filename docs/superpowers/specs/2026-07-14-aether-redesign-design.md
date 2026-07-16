# Aether Redesign — Design Spec

**Date:** 2026-07-14
**Source of truth:** the "Aether" design in Open Design (`css/tokens.css`, `css/app.css`, `mobile-ios.html`) — a warm, human, approachable dark redesign that replaces the current cold "Deep Ink" `Theme.swift`.
**Scope decision (locked with user):** match Aether's *structure and visuals exactly*, but include **only modules backed by real data** — no fabricated metrics (this is a health app; honesty is the core invariant). Sourceless Aether modules are dropped, not faked.

## Goals

1. The iOS app looks and is structured like the Aether mockup — warm charcoal, coral/mint/lavender, SF Pro Rounded, rounded soft-elevated cards, hero ring, metric tiles, list rows, pills, segmented controls.
2. Every visible number is real (from existing endpoints). Modules with no data source are omitted.
3. The deterministic-score invariant is untouched: the ring/decision display the server's `readiness`/`decision`; nothing computes or overrides it; low-confidence still surfaces honestly.

## Visual System (replaces `Theme.swift` "Deep Ink" → "Aether")

**Palette** (converted from the Aether `oklch` tokens to sRGB):

| Token | Hex | Role |
|---|---|---|
| `bg` | `#150E0A` | warm charcoal canvas |
| `bgElevated` | `#1F1612` | raised ground |
| `surface` | `#271D18` | card |
| `surface2` | `#322621` | nested fill / hero gradient top |
| `fg` | `#F6F1EC` | primary text |
| `muted` | `#B2A9A2` | secondary text |
| `muted2` | `#877E78` | tertiary text |
| `border` | `#3D332F` | card stroke |
| `borderSoft` | `#322926` | soft divider |
| `accent` (coral) | `#F9875E` | primary / strain / chrome accent |
| `secondary` (mint) | `#5ED8A9` | recovery |
| `sleep` (lavender) | `#B2A6EC` | sleep |
| `success` | `#5BD295` | good status |
| `warn` | `#F2B95A` | warning / maintain |
| `danger` | `#F05F5A` | critical / recover |

**Decision → color mapping** (state colors, kept separate from the coral chrome accent):
`push → success/mint (#5BD295)`, `maintain → warn/amber (#F2B95A)`, `recover → danger (#F05F5A)`. The hero ring, decision chip, and score numbers use these.

**Typography:** display = **SF Pro Rounded** (`.system(design: .rounded)`) for scores, titles, numbers; body = system (SF Pro Text); mono = `.monospaced` for pills/tabular metrics. Big scores use rounded bold with `monospacedDigit()`.

**Radii:** sm 14, md 20, lg 26, xl 32 (`.continuous`). Cards use 20–26; the hero uses 32.

**Elevation:** soft shadows (`shadow-md: 0 6px 22px black@34%`), not flat. Cards get a subtle border + soft shadow.

**Motion:** orchestrated, restrained — ring draws from 0, bars/fills grow in on appear, honor reduced-motion. Reuse the existing `MetricBar` animate-on-appear pattern.

## Component Library (Aether → SwiftUI)

Rewrite `Theme.swift` + `Components.swift` to provide:

- `Palette` — the tokens above + `gradient(for:)`/`band(for:)` remapped to Aether decision colors.
- `card()` — surface, radius 24, border `border`, `shadow-md`.
- `heroCard()` — `card-glow`: radial coral glow at top over a `surface2→surface` vertical gradient, coral-tinted border, radius 32.
- `Eyebrow` — uppercase tracked label in `muted` (keep; restyle).
- `Pill(text, tone)` — mono uppercase tracked capsule; tones: good/mint, warn/amber, accent/coral, sleep/lavender.
- `MetricTile(label, value, unit, delta, tone)` — the Aether `.metric` tile: label (muted), big rounded value tinted by tone, unit, delta caption, and a thin tinted `MetricBar`.
- `ListRow(icon, tone, title, subtitle, meta, submeta)` — Aether `.list-row`: tinted icon chip + title/subtitle + right-aligned meta, hairline divider between rows, `card()` wrapping the list.
- `SegmentedRange` — Aether `.seg` (e.g. 7d/30d/90d) styled control (can wrap SwiftUI `Picker(.segmented)` themed, or custom).
- `FilterChips` — Aether `.chip` row.
- `HeroRing` — 210pt, 10pt stroke, track = `fg@8%`, progress tinted by decision with a soft glow (`shadow` of the decision color), rounded cap, animated draw. Center: big rounded score + "SCORE"/"READINESS" label.
- `DecisionChip` — bordered uppercase capsule (keep; recolor to Aether decision colors).
- `iconButton` — 44pt circle, `surface` bg, `borderSoft`.
- `screenBackground()` — `bg` canvas + themed nav/tab bars.

## Navigation Restructure

Five tabs (Aether order + icons), replacing the current five:

| Aether tab | Replaces | Content (real data only) |
|---|---|---|
| **Today** | Today | Hero ring + decision + meaning; a 3-up mini-stat row (HRV · RHR · Sleep hrs, from `/v1/body` + `/v1/sleep`); metric tiles: **Strain**, **Recovery**, **Sleep debt** (from pillars); the strict-advisor card; "Ask the coach". *Dropped: Day-energy tile, suggested-workout list.* |
| **Insights** | Trends | Range selector (7/30/90d → `getHistory(days:)`); readiness trend chart (styled bars/line); pillar-scores-over-time chart. *Dropped: fabricated narrative insight cards.* |
| **Activity** | Train | Filter chips (All/Run/Strength/Recovery over real sports); workout list rows (strain · duration); weekly-load card. All real. |
| **Body** | Body | Vitals tiles (Resting HR, HRV — real); the HRV / RHR / HR-range charts (restyled). *Dropped: muscle heat-map, SpO₂ & respiratory rate (not synced), mood check-in.* |
| **You** | Settings (was a sheet) | Profile header (User ID / initials avatar — no fake name); real settings sections: Connection, Sync, **Daily readiness** (notification toggle+time), Data & privacy. Ask/Settings sheets from Today's toolbar are folded here. |

**Sleep tab is removed.** Sleep content lives in Today's mini-stat (last-night hours), Insights (sleep trend), and Body (restorative). The existing `SleepView` total-sleep and stages charts are **folded into the Insights tab** as an additional section (kept, restyled to Aether) so no sleep detail is lost.

**Low-confidence banner, ErrorCard, ContentUnavailableCompat, sync status, auto-sync, background-notification** all carry over unchanged in behavior, restyled to Aether.

## Data Notes (no backend change required)

- Today mini-stats (HRV, RHR, last-night sleep hours) come from existing `/v1/body` (latest `resting_heart_rate`, `hrv_sdnn` avg) and `/v1/sleep` (last night `durationHours`) — an extra fetch on the Today screen, all real. No new endpoint.
- Strain/Recovery/Sleep-debt tiles derive from the existing `/v1/today` pillars (load, recovery, sleep) and their drivers.
- Everything else maps to endpoints already consumed by the current tabs.

## Invariant & Honesty

- Ring + decision chip render `today.decision`/`today.readiness` verbatim; low-confidence → the existing hedge/banner, restyled. Nothing here computes a decision.
- No fabricated metrics. Any module without a real source is omitted this pass (may return later behind real HealthKit/backend work — tracked separately).

## Phasing (for the implementation plan)

1. **Design system** — rewrite `Theme.swift` to the Aether palette/type/radii + the component library (`heroCard`, `Pill`, `MetricTile`, `ListRow`, `SegmentedRange`, `FilterChips`, restyled `HeroRing`/`DecisionChip`/`SectionCard`/`ErrorCard`/`ContentUnavailableCompat`). Build-green with existing screens still rendering.
2. **Today** — rebuild to the Aether layout (hero card, mini-stats, metric tiles, advisor, Ask).
3. **Nav restructure** — new 5-tab `MainTabView` (Today·Insights·Activity·Body·You), remove Sleep tab, move Settings into You, fold sleep charts into Insights.
4. **Insights** (from Trends) — range selector + trend + pillar charts, Aether-styled.
5. **Activity** (from Train) — chips + list rows + weekly load.
6. **Body** — vitals tiles + restyled charts (drop unsourced modules).
7. **You** — profile header + restyled settings.

Each phase ends with a green `xcodebuild` simulator build and renders against the local backend.

## Verification

- `xcodebuild -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build` green per phase; visual check on the booted simulator against the local backend (user_1). No iOS test target (consistent with prior iOS work). Device pass at the end.
