import SwiftUI

/// Remembers which entrance animations already ran this launch, so a gauge
/// sweeps the first time it appears and not on every tab switch.
@MainActor
enum EntranceLedger {
    private static var played: Set<String> = []

    /// True the first time `key` is claimed in this process.
    static func claim(_ key: String) -> Bool {
        played.insert(key).inserted
    }
}

/// Geometry of the 270° gauge arc, open at the bottom.
enum GaugeArc {
    /// Share of a full circle the arc covers.
    static let sweep: Double = 0.75
    /// Rotation that puts the arc's start at the lower left (7:30).
    static let startAngle: Double = 135

    /// How far along the arc a 0–100 score reaches (0…`sweep`).
    static func trim(for score: Double) -> Double {
        min(max(score, 0), 100) / 100 * sweep
    }
}

/// A 270° pillar gauge: track at 8% white, fill in the pillar's identity
/// colour, and a condensed numeral that is white when healthy, amber at 50–74
/// and red below 50. The title sits underneath. Accessibility is provided by
/// the caller, which knows the weight and driver.
struct PillarGauge: View {
    let title: String
    let score: Double
    let tint: Color
    /// Diameter before Dynamic Type scaling.
    var diameter: CGFloat = 96
    /// Upper bound after scaling, so three gauges fit a row.
    var maxDiameter: CGFloat = 112
    /// Entrance sweep runs once per launch per key; nil never sweeps.
    var entranceKey: String?
    var showsTitle = true

    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double?

    private var size: CGFloat { min(diameter * scale, maxDiameter) }
    private var lineWidth: CGFloat { max(7, size * 0.085) }
    private var target: Double { GaugeArc.trim(for: score) }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                arc(to: GaugeArc.sweep)
                    .stroke(Palette.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                arc(to: progress ?? target)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .shadow(color: tint.opacity(0.45), radius: 6)
                Text("\(Int(score.rounded()))")
                    .font(Typeface.numeral(size * 0.34))
                    .foregroundStyle(ScoreBand(score: score).numeralColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(reduceMotion ? .identity : .numericText(value: score))
                    .padding(lineWidth * 1.5)
            }
            .frame(width: size, height: size)

            if showsTitle {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .onAppear(perform: enter)
        .onChange(of: target) { _, new in
            guard progress != nil else { return }
            if reduceMotion { progress = new } else {
                withAnimation(.easeInOut(duration: 0.5)) { progress = new }
            }
        }
    }

    private func arc(to end: Double) -> some Shape {
        Circle()
            .trim(from: 0, to: end)
            .rotation(.degrees(GaugeArc.startAngle))
    }

    private func enter() {
        guard progress == nil else { return }
        guard !reduceMotion, let entranceKey, EntranceLedger.claim(entranceKey) else {
            progress = target
            return
        }
        progress = 0
        withAnimation(.easeOut(duration: 0.9)) { progress = target }
    }
}
