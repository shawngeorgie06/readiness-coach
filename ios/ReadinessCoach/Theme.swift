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
    private static let fallbackMarketing = "1.1.5"
    private static let fallbackBuild = "7"

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

    // Warm decision palette (Aether): recover reads coral, not clinical red, to
    // match the prototype's warm hero. push→mint, maintain→amber, recover→coral.
    static func decisionColor(_ d: Decision) -> Color {
        switch d { case .push: return success; case .maintain: return warn; case .recover: return accent }
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
    var color: Color = Palette.textSecondary
    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.strokeSoft, lineWidth: 1))
                    .shadow(color: .black.opacity(0.34), radius: 14, y: 6)
            }
    }
}

private struct HeroCardModifier: ViewModifier {
    private let radius: CGFloat = 32

    func body(content: Content) -> some View {
        content
            .padding(EdgeInsets(top: 22, leading: 18, bottom: 20, trailing: 18))
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.surfaceHi, Palette.surface], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RadialGradient(colors: [Palette.accent.opacity(0.22), .clear],
                                       center: .top, startRadius: 0, endRadius: 240)
                            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    )
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.accent.opacity(0.22), lineWidth: 1))
            }
            // Keep ring / type from painting past the rounded hero box.
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            // Shadow outside the clip so it still softens under the card.
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.clear)
                    .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
            }
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
    var showBar = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(tone.color)
                if let unit { Text(unit).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary) }
            }
            if let delta { Text(delta).font(.system(.caption2, design: .monospaced)).foregroundStyle(Palette.textSecondary) }
            if showBar { MetricBar(value: fraction, score: 0, height: 4, tint: tone.color) }
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.strokeSoft, lineWidth: 1))
    }
}

/// Icon tint for `AetherListRow` (top-level so it isn't reparented per generic specialization).
enum AetherRowTone { case neutral, accent, mint, sleep
    var fg: Color { switch self { case .neutral: return Palette.textSecondary; case .accent: return Palette.accent; case .mint: return Palette.mint; case .sleep: return Palette.lavender } }
    var bg: Color { switch self { case .neutral: return Palette.elevated; default: return fg.opacity(0.16) } }
}

struct AetherListRow<Trailing: View>: View {
    let systemImage: String
    var tone: AetherRowTone = .neutral
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
