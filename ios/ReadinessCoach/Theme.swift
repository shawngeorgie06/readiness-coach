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

/// Device-visible build label. Prefer what Xcode actually installed
/// (`CFBundleShortVersionString` / `CFBundleVersion`) so the You/Today
/// labels cannot drift from MARKETING_VERSION.
enum AppBuild {
    /// Fallback only if Info.plist keys are missing (previews / tests).
    private static let fallbackMarketing = "1.3.8"
    private static let fallbackBuild = "28"

    static var marketing: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? fallbackMarketing
    }

    static var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? fallbackBuild
    }

    /// e.g. "1.1.2" — keep short for inline UI.
    static var stamp: String { marketing }

    /// e.g. "v1.1.2 (4)" — hard to miss on You / Settings.
    static var label: String { "v\(marketing) (\(build))" }
}

/// Formats sleep/stage durations as hours + minutes (not decimal hours).
enum DurationFormat {
    /// Compact tile text: `7h 54m`, `45m`, `8h`.
    static func short(_ hours: Double) -> String {
        let parts = components(hours)
        if parts.hours == 0 { return "\(parts.minutes)m" }
        if parts.minutes == 0 { return "\(parts.hours)h" }
        return "\(parts.hours)h \(parts.minutes)m"
    }

    /// Sentence text: `7 hr 54 min`.
    static func long(_ hours: Double) -> String {
        let parts = components(hours)
        if parts.hours == 0 { return "\(parts.minutes) min" }
        if parts.minutes == 0 {
            return parts.hours == 1 ? "1 hour" : "\(parts.hours) hours"
        }
        return "\(parts.hours) hr \(parts.minutes) min"
    }

    private static func components(_ hours: Double) -> (hours: Int, minutes: Int) {
        let total = max(0, Int((hours * 60).rounded()))
        return (total / 60, total % 60)
    }
}

/// Shared copy for the 0–21 workout strain scale.
enum StrainExplain {
    static let scaleBlurb =
        "Strain rates how hard a workout was on a 0–21 scale (same idea as common recovery wearables). It’s computed from session duration and how hard your heart worked vs your resting-to-max reserve, then capped at 21. Easy days land low; long or high-intensity sessions push toward the top. Strain feeds the Load pillar of readiness."

    static let shortBlurb =
        "0–21 effort score from duration + heart-rate intensity (capped at 21)."
}

/// Readiness is the weighted sum of three pillars. These weights mirror the
/// backend's scoring and are only ever displayed, never used to compute.
enum Pillar: CaseIterable, Identifiable {
    case recovery, sleep, load

    var id: Self { self }

    var title: String {
        switch self {
        case .recovery: return "Recovery"
        case .sleep: return "Sleep"
        case .load: return "Load"
        }
    }

    /// Share of the readiness score, as shown to the user.
    var weightPercent: Int {
        switch self {
        case .recovery: return 40
        case .sleep: return 35
        case .load: return 25
        }
    }

    var summary: String {
        switch self {
        case .recovery: return "HRV and resting heart rate vs your baseline"
        case .sleep: return "Last night's duration and quality vs your need"
        case .load: return "Recent training strain vs your norm"
        }
    }

    var systemImage: String {
        switch self {
        case .recovery: return "heart.fill"
        case .sleep: return "moon.fill"
        case .load: return "flame.fill"
        }
    }

    var color: Color {
        switch self {
        case .recovery: return Palette.recovery
        case .sleep: return Palette.sleep
        case .load: return Palette.load
        }
    }

    func score(in pillars: Pillars) -> PillarScore {
        switch self {
        case .recovery: return pillars.recovery
        case .sleep: return pillars.sleep
        case .load: return pillars.load
        }
    }
}

/// Dark, data-first. Flat near-black canvas; content sits on it, separated by
/// hairlines. One filled surface (Ask bar, segmented controls, sheets). Bright
/// colour is reserved for scores. One hue per pillar for identity; a separate
/// traffic-light set for good/bad. Dark-only for now — a light scheme is a
/// second column here, not a rewrite.
enum Palette {
    static let canvas  = Color(hex: 0x07080A)
    /// The only filled surface: Ask bar, segmented controls, sheets.
    static let surface = Color(hex: 0x15171B)
    /// Raised fill inside a surface (selected segment, inset readouts).
    static let surfaceHi = Color(hex: 0x21242B)
    /// 1px rule between open sections and rows.
    static let hairline = Color.white.opacity(0.07)
    /// Gauge tracks and skeleton blocks.
    static let track = Color.white.opacity(0.08)

    static let textPrimary   = Color(hex: 0xF2F2F0)
    static let textSecondary = Color(hex: 0xA3A6AD)
    static let textTertiary  = Color(hex: 0x8B8F98)
    static let stroke        = Color(hex: 0x2A2D34)
    static let strokeSoft    = Color(hex: 0x1F2228)

    /// Interactive tint: bone white on dark, so controls read as type, not chrome.
    static let accent = Color(hex: 0xE9E4DB)

    static let recovery = Color(hex: 0x2CA5BF)
    static let sleep    = Color(hex: 0x8474CE)
    static let load     = Color(hex: 0x9C477B)

    static let success = Color(hex: 0x3DD68C)
    static let warn    = Color(hex: 0xF0B429)
    static let danger  = Color(hex: 0xF0605B)

    // Aliases kept for the pillar tabs until they are restyled in phase 3.
    static let elevated  = surface
    static let mint      = recovery
    static let lavender  = sleep

    static func decisionColor(_ d: Decision) -> Color { d.band.color }
    static func band(for score: Double) -> Color { ScoreBand(score: score).color }
}

/// Where a 0–100 score sits, at the backend's push/maintain cutoffs (75 / 50).
/// Scores only: comparison deltas use each metric's server band instead.
enum ScoreBand: Equatable {
    case high, mid, low

    /// Banded on the displayed (rounded) value, so a numeral that reads "75"
    /// is never coloured as below 75.
    init(score: Double) {
        let shown = score.rounded()
        if shown >= 75 { self = .high } else if shown >= 50 { self = .mid } else { self = .low }
    }

    var color: Color {
        switch self {
        case .high: return Palette.success
        case .mid: return Palette.warn
        case .low: return Palette.danger
        }
    }

    /// Numerals inside pillar gauges: white when healthy (never green), so
    /// colour only appears where a pillar is weak.
    var numeralColor: Color {
        switch self {
        case .high: return Palette.textPrimary
        case .mid: return Palette.warn
        case .low: return Palette.danger
        }
    }
}

extension Decision {
    /// The locked decision's colour family. Today's verdict uses this, never the
    /// score band, so an override can't look greener than the call.
    var band: ScoreBand {
        switch self {
        case .push: return .high
        case .maintain: return .mid
        case .recover: return .low
        }
    }
}

/// Type roles. Numerals are SF Pro Compressed/Condensed heavy with tabular
/// digits; everything else is SF Pro at Dynamic Type text styles.
enum Typeface {
    /// Big score numerals. Size comes from a `@ScaledMetric` at the call site.
    static func numeral(_ size: CGFloat, width: Font.Width = .compressed) -> Font {
        .system(size: size, weight: .heavy).width(width).monospacedDigit()
    }
    /// Row values and vitals (~20pt at default size).
    static let value = Font.title3.weight(.heavy).width(.condensed).monospacedDigit()
    /// Section titles: sentence case, 15pt semibold, white.
    static let sectionTitle = Font.subheadline.weight(.semibold)
    /// The one uppercase, letter-spaced voice: the verdict beside a head numeral.
    static let verdict = Font.title3.weight(.heavy).width(.condensed)
    static let verdictTracking: CGFloat = 1.6
    /// Plan headline: 20pt bold.
    static let headline = Font.title3.weight(.bold)
}

/// Spacing scale for the open layout.
enum Space {
    static let margin: CGFloat = 20
    static let section: CGFloat = 28
    static let row: CGFloat = 14
    static let tight: CGFloat = 6
    /// Minimum touch target.
    static let target: CGFloat = 44
}

/// Sentence-case section label. Replaces the mono uppercase eyebrow.
struct Eyebrow: View {
    let text: String
    var color: Color = Palette.textSecondary
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    /// High-contrast filled action, including on iOS 17's prominent-button chrome.
    func primaryAction() -> some View {
        self.buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .foregroundStyle(Palette.canvas)
    }

    /// Flat surface, no shadow or stroke.
    func card() -> some View { modifier(CardModifier()) }
    func screenBackground() -> some View {
        self
            .foregroundStyle(Palette.textPrimary)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas.ignoresSafeArea())
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct MetricBar: View {
    let value: Double
    let score: Double
    var height: CGFloat = 4
    var tint: Color? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .onAppear {
            if reduceMotion { animated = true } else {
                withAnimation(.easeOut(duration: 0.7)) { animated = true }
            }
        }
    }
}

struct Pill: View {
    enum Tone { case good, warn, accent, sleep, neutral }
    let text: String
    var tone: Tone = .neutral
    init(_ text: String, tone: Tone = .neutral) { self.text = text; self.tone = tone }
    var textColor: Color { Palette.textPrimary }
    private var color: Color {
        switch tone { case .good: return Palette.success; case .warn: return Palette.warn
        case .accent: return Palette.accent; case .sleep: return Palette.sleep; case .neutral: return Palette.textSecondary }
    }
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(textColor)
    }
}

/// Icon tint for `AetherListRow` (top-level so it isn't reparented per generic specialization).
enum AetherRowTone { case neutral, accent, mint, sleep
    var fg: Color { switch self { case .neutral: return Palette.textSecondary; case .accent: return Palette.load; case .mint: return Palette.recovery; case .sleep: return Palette.sleep } }
    var bg: Color { switch self { case .neutral: return Palette.surfaceHi; default: return fg.opacity(0.14) } }
}

struct AetherListRow<Trailing: View>: View {
    let systemImage: String
    var tone: AetherRowTone = .neutral
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).font(.callout.weight(.semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(tone.fg)
                .background(tone.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(Palette.textSecondary) }
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
                    Text(options[i]).font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(selection == i ? Palette.textPrimary : Palette.textSecondary)
                        .background(selection == i ? Palette.surfaceHi : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == i ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Small stat tile used on the pillar tabs: label, big value, optional unit and
/// delta, with a thin bar in the metric's colour.
struct MetricTile: View {
    enum Tone { case strain, recovery, sleep
        var color: Color { switch self { case .strain: return Palette.load; case .recovery: return Palette.recovery; case .sleep: return Palette.sleep } } }
    let label: String
    let value: String
    var unit: String? = nil
    var delta: String? = nil
    let fraction: Double
    let tone: Tone
    var showBar = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.footnote.weight(.medium)).foregroundStyle(Palette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.textPrimary)
                if let unit { Text(unit).font(.footnote.weight(.medium)).foregroundStyle(Palette.textSecondary) }
            }
            if let delta { Text(delta).font(.caption).foregroundStyle(Palette.textSecondary) }
            if showBar { MetricBar(value: fraction, score: 0, height: 4, tint: tone.color) }
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
