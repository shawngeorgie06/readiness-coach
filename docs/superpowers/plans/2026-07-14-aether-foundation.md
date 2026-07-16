# Aether Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin the app to the Aether design system and restructure navigation to Aether's five tabs (Today · Insights · Activity · Body · You), with Today rebuilt to the Aether layout — all on real data.

**Architecture:** Rewrite `Theme.swift` from the "Deep Ink" palette to the Aether design system (warm charcoal, coral/mint/lavender, SF Pro Rounded, rounded soft-elevated cards) plus a reusable component library. Because the shared components keep their existing names/signatures, every current tab picks up the new look on rebuild. Then rebuild `TodayView` to the Aether hero layout and restructure `MainTabView` into the five Aether tabs (Settings becomes a "You" tab; Sleep folds into Insights).

**Tech Stack:** SwiftUI (iOS 17), Swift Charts. No backend change (Today's mini-stats reuse existing `/v1/body` and `/v1/sleep`).

## Global Constraints

- **iOS presentation only. No backend/DTO change.** Today mini-stats reuse existing endpoints via the existing `APIClient` methods (`getBody`, `getSleep`).
- **The deterministic score owns the decision.** The hero ring + decision chip render `today.decision`/`today.readiness` verbatim; low-confidence still surfaces via the existing banner (restyled). Nothing computes a decision.
- **Real data only.** Do not introduce fabricated metrics. Dropped Aether modules (day-energy, suggested workouts) are omitted.
- **Aether palette (verbatim sRGB hex), from `docs/superpowers/specs/2026-07-14-aether-redesign-design.md`:** bg `#150E0A`, bgElevated `#1F1612`, surface `#271D18`, surface2 `#322621`, fg `#F6F1EC`, muted `#B2A9A2`, muted2 `#877E78`, border `#3D332F`, borderSoft `#322926`, accent/coral `#F9875E`, secondary/mint `#5ED8A9`, sleep/lavender `#B2A6EC`, success `#5BD295`, warn `#F2B95A`, danger `#F05F5A`.
- **Decision→color:** push→success `#5BD295`, maintain→warn `#F2B95A`, recover→danger `#F05F5A`. Coral stays the chrome/strain accent, never a decision color.
- **Type:** display = `.system(design: .rounded)`; body = default; numbers/pills = `.monospaced` with `monospacedDigit()`/`tabular-nums`.
- **File-system-synchronized project (objectVersion 77):** new `.swift` files auto-include; do NOT edit `project.pbxproj`. The working tree has a pre-existing uncommitted `project.pbxproj` (personal DEVELOPMENT_TEAM) — never stage/commit/revert it.
- **No iOS test target.** Verify each task with the simulator build below + a visual check; do not create a test target.
- **Build (verbatim), from repo root `/Users/shawngeorgie/readiness-coach`:**
  `xcodebuild -project ios/ReadinessCoach.xcodeproj -scheme ReadinessCoach -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`
- **Headless SourceKit false positives** ("cannot find type X in scope" on module types) are expected; the whole-module build is authoritative.

---

### Task 1: Aether design system (`Theme.swift` + `Components.swift`)

Rewrite the design tokens and shared component library to Aether. Keep the existing public names/signatures so all current screens still compile: `Palette`, `Eyebrow`, `SectionCard`, `MetricBar`, `card()`, `screenBackground()`, `ReadinessRing`, `DecisionChip`, `ErrorCard`, `ContentUnavailableCompat`, `Decision.tint`. Add new components: `HeroCard`, `Pill`, `MetricTile`, `AetherListRow`, `SegmentedRange`, `FilterChips`.

**Files:**
- Modify: `ios/ReadinessCoach/Theme.swift`
- Modify: `ios/ReadinessCoach/Views/RootView.swift` (the `ReadinessRing`, `DecisionChip`, `SectionCard`, `Decision.tint` live here — recolor to Aether)
- Modify: `ios/ReadinessCoach/Views/Components.swift` (`ErrorCard`, `InfoBadge`; add nothing structural — recolor)

**Interfaces produced (used by Tasks 2–3 and later plans):**
- `Palette` with the tokens above + `gradient(for:)` / `band(for:)` on Aether decision colors.
- `func card() -> some View`, `func heroCard() -> some View`, `func screenBackground() -> some View`
- `struct Pill: View { init(_ text: String, tone: Pill.Tone) }` — Tone `.good/.warn/.accent/.sleep/.neutral`
- `struct MetricTile: View { init(label: String, value: String, unit: String? = nil, delta: String? = nil, fraction: Double, tone: MetricTile.Tone) }` — Tone `.strain/.recovery/.sleep`
- `struct AetherListRow<Trailing: View>: View { init(systemImage: String, tone: ListTone, title: String, subtitle: String?, @ViewBuilder trailing: () -> Trailing) }`
- `struct SegmentedRange: View { init(_ options: [String], selection: Binding<Int>) }`

- [ ] **Step 1: Rewrite `Theme.swift` to the Aether tokens + core modifiers/components**

Replace the `Palette` enum and card modifiers in `ios/ReadinessCoach/Theme.swift` with:

```swift
import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Aether — warm, human, approachable dark. Every token explicit.
enum Palette {
    static let canvas     = Color(hex: 0x150E0A)
    static let elevated   = Color(hex: 0x1F1612)
    static let surface    = Color(hex: 0x271D18)
    static let surfaceHi  = Color(hex: 0x322621)
    static let textPrimary   = Color(hex: 0xF6F1EC)
    static let textSecondary = Color(hex: 0xB2A9A2)
    static let textTertiary  = Color(hex: 0x877E78)
    static let stroke        = Color(hex: 0x3D332F)
    static let strokeSoft    = Color(hex: 0x322926)

    static let accent    = Color(hex: 0xF9875E)   // coral — chrome / strain
    static let mint       = Color(hex: 0x5ED8A9)  // recovery
    static let lavender   = Color(hex: 0xB2A6EC)  // sleep
    static let success    = Color(hex: 0x5BD295)
    static let warn       = Color(hex: 0xF2B95A)
    static let danger     = Color(hex: 0xF05F5A)

    // Data-viz aliases (kept for chart tabs; map old names to Aether)
    static let sleepBlue = lavender
    static let teal      = mint
    static let indigo    = lavender
    static let violet    = lavender
    static let warm      = accent
    static let coral     = accent

    static func decisionColor(_ d: Decision) -> Color {
        switch d { case .push: return success; case .maintain: return warn; case .recover: return danger }
    }
    static func gradient(for d: Decision) -> [Color] {
        let c = decisionColor(d)
        return [c.opacity(0.85), c]
    }
    static func band(for score: Double) -> Color {
        if score >= 75 { return success }
        if score >= 50 { return warn }
        return danger
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(Palette.textSecondary)
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.strokeSoft, lineWidth: 1))
            .shadow(color: .black.opacity(0.34), radius: 14, y: 6)
    }
}

private struct HeroCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(EdgeInsets(top: 22, leading: 18, bottom: 20, trailing: 18))
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.surfaceHi, Palette.surface], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RadialGradient(colors: [Palette.accent.opacity(0.22), .clear],
                                       center: .top, startRadius: 0, endRadius: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    )
            )
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Palette.accent.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
    func heroCard() -> some View { modifier(HeroCardModifier()) }
    func screenBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Palette.canvas.ignoresSafeArea())
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

struct MetricBar: View {
    let value: Double
    let score: Double
    var height: CGFloat = 4
    var tint: Color? = nil
    @State private var animated = false
    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.textPrimary.opacity(0.08))
                Capsule().fill(tint ?? Palette.band(for: score))
                    .frame(width: geo.size.width * (animated ? clamped : 0))
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { animated = true } }
    }
}
```

- [ ] **Step 2: Add the new Aether components to `Theme.swift`**

Append `Pill`, `MetricTile`, `AetherListRow`, `SegmentedRange`, and a mono-number helper:

```swift
struct Pill: View {
    enum Tone { case good, warn, accent, sleep, neutral }
    let text: String
    var tone: Tone = .neutral
    init(_ text: String, tone: Tone = .neutral) { self.text = text; self.tone = tone }
    private var color: Color {
        switch tone { case .good: return Palette.mint; case .warn: return Palette.warn
        case .accent: return Palette.accent; case .sleep: return Palette.lavender; case .neutral: return Palette.textSecondary }
    }
    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .tracking(0.6)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

struct MetricTile: View {
    enum Tone { case strain, recovery, sleep
        var color: Color { switch self { case .strain: return Palette.accent; case .recovery: return Palette.mint; case .sleep: return Palette.lavender } } }
    let label: String
    let value: String
    var unit: String? = nil
    var delta: String? = nil
    let fraction: Double
    let tone: Tone
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(tone.color)
                if let unit { Text(unit).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary) }
            }
            if let delta { Text(delta).font(.system(.caption2, design: .monospaced)).foregroundStyle(Palette.textSecondary) }
            MetricBar(value: fraction, score: 0, height: 4, tint: tone.color)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.strokeSoft, lineWidth: 1))
    }
}

struct AetherListRow<Trailing: View>: View {
    enum ListTone { case neutral, accent, mint, sleep
        var fg: Color { switch self { case .neutral: return Palette.textSecondary; case .accent: return Palette.accent; case .mint: return Palette.mint; case .sleep: return Palette.lavender } }
        var bg: Color { switch self { case .neutral: return Palette.elevated; default: return fg.opacity(0.16) } } }
    let systemImage: String
    var tone: ListTone = .neutral
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(tone.fg)
                .background(tone.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.textSecondary) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(14)
    }
}

struct SegmentedRange: View {
    let options: [String]
    @Binding var selection: Int
    init(_ options: [String], selection: Binding<Int>) { self.options = options; self._selection = selection }
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                Button { selection = i } label: {
                    Text(options[i]).font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(selection == i ? Palette.textPrimary : Palette.textSecondary)
                        .background(selection == i ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Palette.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.strokeSoft, lineWidth: 1))
    }
}
```

- [ ] **Step 3: Recolor the shared components in `RootView.swift` to Aether**

In `ios/ReadinessCoach/Views/RootView.swift`: set `Decision.tint` to `Palette.decisionColor(self)`; keep `ReadinessRing` but change it to a 210×210 ring, 10pt stroke, track `Palette.textPrimary.opacity(0.08)`, progress = `Palette.decisionColor(decision)` with a `.shadow(color: decisionColor.opacity(0.5), radius: 12)` glow, rounded cap, animated draw, center score `.system(size: 64, weight: .semibold, design: .rounded)` + `Eyebrow("Score")`; recolor `DecisionChip` to Aether decision colors; change `SectionCard` to use `Eyebrow(text:)` + `.card()` (already does — verify colors). Keep `.preferredColorScheme(.dark)` and `.tint(Palette.accent)`.

```swift
extension Decision {
    var tint: Color { Palette.decisionColor(self) }
    // systemImage, meaning: unchanged
}
```

For `ReadinessRing`, replace the ring body:

```swift
    var body: some View {
        let fraction = min(max(readiness / 100, 0), 1)
        let color = Palette.decisionColor(decision)
        ZStack {
            Circle().stroke(Palette.textPrimary.opacity(0.08), lineWidth: 10)
            Circle().trim(from: 0, to: animated ? fraction : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.5), radius: 12)
            VStack(spacing: 2) {
                Text("\(Int(readiness.rounded()))")
                    .font(.system(size: 64, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                Eyebrow(text: "Score")
            }
        }
        .frame(width: 210, height: 210)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { animated = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness \(Int(readiness.rounded())), decision \(decision.title)")
    }
```

- [ ] **Step 4: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **` (all existing screens compile against the renamed/retinted components).

- [ ] **Step 5: Commit**

```bash
git add ios/ReadinessCoach/Theme.swift ios/ReadinessCoach/Views/RootView.swift ios/ReadinessCoach/Views/Components.swift
git commit -m "feat(ios): Aether design system — warm palette, rounded cards, component library"
```

---

### Task 2: Rebuild Today to the Aether layout

**Files:**
- Modify: `ios/ReadinessCoach/Views/TodayView.swift`

**Interfaces consumed:** `heroCard()`, `Pill`, `MetricTile`, `ReadinessRing`, `DecisionChip`, `Palette`, `SectionCard`; `APIClient.getBody`, `APIClient.getSleep` for mini-stats.

- [ ] **Step 1: Add a mini-stats fetch (real HRV / RHR / last-night sleep)**

In `TodayView`, add state and a loader that pulls the latest values from the existing detail endpoints:

```swift
    @State private var hrv: Double?
    @State private var rhr: Double?
    @State private var sleepHours: Double?

    private func loadMiniStats() async {
        guard let client = settings.makeClient() else { return }
        async let body = try? client.getBody(days: 7)
        async let sleep = try? client.getSleep(days: 2)
        if let b = await body {
            hrv = b.daily.filter { $0.type == "hrv_sdnn" }.sorted { $0.date < $1.date }.last?.avg
            rhr = b.daily.filter { $0.type == "resting_heart_rate" }.sorted { $0.date < $1.date }.last?.avg
        }
        if let s = await sleep { sleepHours = s.data.filter { $0.durationHours > 0 }.last?.durationHours }
    }
```

Call `await loadMiniStats()` from the existing `.task`/refresh path alongside the Today load.

- [ ] **Step 2: Rebuild the hero + mini-stats + metric tiles**

Replace the header `VStack` (ring + chip + meaning) and pillars section with the Aether hero card and metric tiles. The hero card holds the ring, decision chip, meaning, and a 3-up mini-stat row; below it a 2-column grid of `MetricTile`s for Strain / Recovery / Sleep debt (values from `today.pillars`). Use `fmt`/`Int` as today. Example hero block:

```swift
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Readiness")
                    Text("Calibrated from sleep, HRV & load").font(.caption).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Pill(today.decision.title, tone: today.decision == .push ? .good : today.decision == .maintain ? .warn : .accent)
            }
            ReadinessRing(readiness: today.readiness, decision: today.decision)
            DecisionChip(decision: today.decision)
            Text(today.decision.meaning).font(.system(.body, design: .rounded))
                .foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
            HStack(spacing: 8) {
                miniStat("HRV", hrv.map { "\(Int($0.rounded()))" } ?? "—", "ms")
                miniStat("RHR", rhr.map { "\(Int($0.rounded()))" } ?? "—", "bpm")
                miniStat("Sleep", sleepHours.map { String(format: "%.1f", $0) } ?? "—", "h")
            }
        }
        .frame(maxWidth: .infinity)
        .heroCard()
```

with a `miniStat(_:_:_:)` helper (label tiny, value rounded-18, unit) inside a `.surfaceHi` quiet tile, and a `metricTiles(today.pillars)` grid using `MetricTile(label:"Strain"/"Recovery"/"Sleep debt", value:…, fraction:…, tone:.strain/.recovery/.sleep)` derived from the load/recovery/sleep pillar scores. Keep the advisor card and the "Ask the coach" button (already Aether via `.borderedProminent`/`Palette.accent`). Keep the low-confidence banner and `.screenBackground()`.

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Visual check + Commit**

Confirm Today renders the hero card with the ring, mini-stats, and metric tiles against the local backend (sim), then:

```bash
git add ios/ReadinessCoach/Views/TodayView.swift
git commit -m "feat(ios): rebuild Today to the Aether hero layout"
```

---

### Task 3: Navigation restructure — five Aether tabs + You

**Files:**
- Modify: `ios/ReadinessCoach/Views/RootView.swift` (`MainTabView`)
- Create: `ios/ReadinessCoach/Views/YouView.swift`

**Interfaces consumed:** existing `TrendsView`, `TrainView`, `BodyView`, `SleepView`, `SettingsView`, `AskCoachView`.

- [ ] **Step 1: Create `YouView` wrapping the existing Settings content**

Create `ios/ReadinessCoach/Views/YouView.swift` — a `NavigationStack` with a profile header card (initials avatar from `settings.userId`, no fabricated name) above the existing `SettingsView` body content. Simplest faithful version: embed `SettingsView()` and add a header. Since `SettingsView` is already a full `NavigationStack`, `YouView` = a thin wrapper that shows a profile header then the settings form. Implementation:

```swift
import SwiftUI

struct YouView: View {
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        SettingsView()   // already a NavigationStack with Connection/Sync/Daily readiness/Data & privacy
    }
}
```

(The profile-header polish lands in the dedicated "You" plan; for the foundation, `YouView` surfaces the real settings under the new tab.)

- [ ] **Step 2: Restructure `MainTabView` to the five Aether tabs**

Replace `MainTabView`'s `TabView` with Today · Insights · Activity · Body · You. Insights = `TrendsView` (sleep charts fold in during the Insights plan), Activity = `TrainView`, Body = `BodyView`, You = `YouView`. Remove the standalone Sleep tab. Recolor the tab bar to the Aether canvas with the coral active tint.

```swift
struct MainTabView: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "circle.circle.fill") }
            TrendsView().tabItem { Label("Insights", systemImage: "chart.bar.fill") }
            TrainView().tabItem { Label("Activity", systemImage: "bolt.fill") }
            BodyView().tabItem { Label("Body", systemImage: "figure.stand") }
            YouView().tabItem { Label("You", systemImage: "person.fill") }
        }
        .toolbarBackground(Palette.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .tint(Palette.accent)
    }
}
```

- [ ] **Step 3: Fold Sleep into Insights (preserve sleep access)**

So no sleep data is lost when the Sleep tab is removed, add the existing sleep charts to the Insights (`TrendsView`) screen as a trailing section. In `TrendsView`'s `ScrollView` `VStack`, after the pillar card, embed the existing sleep total + stages sections by instantiating the relevant `SleepView` chart builders. Minimal approach: add `SleepView()`'s content below Trends by rendering a `SleepChartsSection` view extracted from `SleepView` (extract its `totalCard`/`stageCard` into a small reusable `SleepChartsSection` view used by both). If extraction is out of scope for this task, embed `SleepView()` inside a `Section`-less container below the Trends charts. Chosen approach: extract `SleepChartsSection` (total + stages charts) from `SleepView` and render it in `TrendsView` under the pillar chart, so both compile against real `getSleep` data.

- [ ] **Step 4: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Visual check + Commit**

Confirm the five tabs appear (Today · Insights · Activity · Body · You), the Sleep tab is gone, sleep charts show under Insights, and You shows settings. Then:

```bash
git add ios/ReadinessCoach/Views/RootView.swift ios/ReadinessCoach/Views/YouView.swift ios/ReadinessCoach/Views/TrendsView.swift ios/ReadinessCoach/Views/SleepView.swift
git commit -m "feat(ios): restructure to Aether five-tab nav (Today·Insights·Activity·Body·You)"
```

---

## Self-Review Notes

- **Spec coverage (this plan = phases 1–3):** design system → Task 1; Today rebuild → Task 2; nav restructure + Sleep fold + Settings→You → Task 3. Remaining phases (Insights/Activity/Body/You detail) are follow-on plans, as the spec's phasing states.
- **API consistency:** `MetricTile(label:value:unit:delta:fraction:tone:)`, `Pill(_:tone:)`, `AetherListRow(systemImage:tone:title:subtitle:trailing:)`, `SegmentedRange(_:selection:)`, `Palette.decisionColor(_:)`/`band(for:)`/`gradient(for:)` are defined in Task 1 and consumed unchanged in Tasks 2–3 and later plans.
- **Real-data only:** Today mini-stats/tiles come from `getBody`/`getSleep`/`today.pillars`; no fabricated modules.
- **Invariant:** ring/chip render server decision; low-confidence banner retained.
