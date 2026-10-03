import SwiftUI

/// The reason the app exists: the locked decision, the score, one line of
/// meaning. Renders `today.decision` / `today.readiness` verbatim.
struct DecisionBlock: View {
    let today: TodayDTO
    let onScoreTap: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 22))

        layout {
            Button(action: onScoreTap) {
                ScoreRing(readiness: today.readiness, decision: today.decision)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens readiness history")

            VStack(alignment: .leading, spacing: 6) {
                Text(today.decision.title)
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text(today.decision.meaning)
                    .font(.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if today.isSleepPending {
                    Label("Showing last night — you haven't slept yet tonight", systemImage: "moon.zzz")
                        .font(.footnote)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
}

/// Thin flat ring. Track is 8% ink; the arc is the decision colour.
struct ScoreRing: View {
    let readiness: Double
    let decision: Decision
    @ScaledMetric(relativeTo: .largeTitle) var diameter: CGFloat = 116
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated = false

    var body: some View {
        let fraction = min(max(readiness / 100, 0), 1)
        let color = Palette.decisionColor(decision)
        let line: CGFloat = 6

        ZStack {
            Circle()
                .stroke(Palette.textPrimary.opacity(0.08), lineWidth: line)
            Circle()
                .trim(from: 0, to: animated ? fraction : 0)
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(readiness.rounded()))")
                .font(.system(.largeTitle, design: .default).weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(Palette.textPrimary)
                .padding(line * 2)
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion { animated = true } else {
                withAnimation(.easeOut(duration: 0.8)) { animated = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness \(Int(readiness.rounded())), decision \(decision.title)")
    }
}
