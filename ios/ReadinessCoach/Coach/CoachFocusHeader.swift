import SwiftUI

/// The numbers the coach is talking about: the score, then the real values
/// behind it. Everything shown comes from `CoachFocusModel`, which reads
/// `TodayDTO` only. With no baselines it shows the pillar's driver text and no
/// invented figures.
struct CoachFocusHeader: View {
    let model: CoachFocusModel
    /// Colours the readiness numeral; pillars colour by their own score band.
    let decision: Decision
    let isReadiness: Bool
    let onShowHistory: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 76
    @State private var shownScore = 0
    @State private var scoreVisible = false

    private var scoreColor: Color {
        isReadiness ? decision.band.color : ScoreBand(score: Double(model.score)).color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            topRow
            scoreRow
            if !model.pillarScores.isEmpty { pillarRow }
            if !model.factors.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(model.factors) { CoachFactorBar(factor: $0) }
                }
                if model.trend.compactMap({ $0 }).count >= 2, let first = model.factors.first {
                    CoachTrend(values: model.trend, metric: first.metric)
                }
            } else if !model.fallbackDrivers.isEmpty {
                drivers
            }
            historyButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: revealScore)
    }

    // MARK: Pieces

    private var topRow: some View {
        HStack(alignment: .center) {
            Text(model.title)
                .font(Typeface.sectionTitle)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 16)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(minWidth: Space.target, minHeight: Space.target)
                    .background(Palette.surfaceHi, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var scoreRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 14))
        return layout {
            Text("\(shownScore)")
                .font(Typeface.numeral(numeralSize))
                .foregroundStyle(scoreColor)
                .contentTransition(.numericText(value: Double(shownScore)))
                .opacity(scoreVisible ? 1 : 0)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if isReadiness {
                Text(decision.title.uppercased())
                    .font(Typeface.verdict)
                    .tracking(Typeface.verdictTracking)
                    .foregroundStyle(decision.band.color)
            } else if let weight = model.weightLabel {
                Text(weight)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scoreSpoken)
    }

    private var scoreSpoken: String {
        if isReadiness { return "Readiness \(model.score), \(decision.title)" }
        let weight = model.weightLabel.map { ", \($0)" } ?? ""
        return "\(model.title) \(model.score)\(weight)"
    }

    private var pillarRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            ForEach(model.pillarScores, id: \.0) { pillar, score in
                HStack(spacing: 8) {
                    Image(systemName: pillar.systemImage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(pillar.color)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(score)")
                            .font(Typeface.value)
                            .foregroundStyle(ScoreBand(score: Double(score)).numeralColor)
                        Text(pillar.title)
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(pillar.title) \(score)")
            }
        }
    }

    private var drivers: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.fallbackDrivers, id: \.self) { text in
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var historyButton: some View {
        Button(action: onShowHistory) {
            HStack(spacing: 4) {
                Text("See history")
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.accent)
            .frame(minHeight: Space.target)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens readiness history")
    }

    private func revealScore() {
        guard !scoreVisible else { return }
        if reduceMotion {
            shownScore = model.score
            withAnimation(.easeIn(duration: 0.25)) { scoreVisible = true }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { scoreVisible = true }
            withAnimation(.easeOut(duration: 0.8)) { shownScore = model.score }
        }
    }
}

// MARK: - Factor bar

/// One metric: today's value, its 30-day normal and the signed difference.
/// A tick on the track marks the normal; the fill is today.
struct CoachFactorBar: View {
    let factor: CoachFactor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var revealed = false

    private var comparison: MetricComparison { factor.comparison }
    private var metric: VitalMetric { factor.metric }
    private var fillColor: Color {
        comparison.tone == .neutral ? Palette.textSecondary : comparison.tone.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            labels
            track
            if let caption = comparisonLine { caption }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(comparison.accessibilityText)
        .onAppear {
            guard !revealed else { return }
            if reduceMotion { revealed = true } else {
                withAnimation(.easeOut(duration: 0.8).delay(0.15)) { revealed = true }
            }
        }
    }

    private var labels: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text(metric.title)
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
            if typeSize.isAccessibilitySize == false { Spacer(minLength: 8) }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(comparison.todayText)
                    .font(Typeface.value)
                    .foregroundStyle(Palette.textPrimary)
                if let unit = metric.unit {
                    Text(unit)
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    /// Fill scales against the larger of today and normal, with headroom, so
    /// the normal tick always lands on the track.
    private var scaleMax: Double {
        max(max(comparison.today ?? 0, comparison.normal ?? 0) * 1.25, .ulpOfOne)
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fill = min(max((comparison.today ?? 0) / scaleMax, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule()
                    .fill(fillColor)
                    .frame(width: max(width * fill * ((revealed || reduceMotion) ? 1 : 0), 0))
                if let normal = comparison.normal {
                    Capsule()
                        .fill(Palette.textPrimary.opacity(0.85))
                        .frame(width: 2, height: 14)
                        .offset(x: min(max(width * normal / scaleMax - 1, 0), width - 2))
                }
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 14)
        .opacity(reduceMotion ? (revealed ? 1 : 0) : 1)
        .animation(reduceMotion ? .easeIn(duration: 0.25) : nil, value: revealed)
        .accessibilityHidden(true)
    }

    private var comparisonLine: Text? {
        guard let normalText = comparison.normalCaption else { return nil }
        var line = Text(normalText).foregroundStyle(Palette.textSecondary)
        if let delta = comparison.deltaText {
            line = line + Text("  ·  ").foregroundStyle(Palette.textTertiary)
                + Text(delta).foregroundStyle(comparison.tone.color == Palette.textTertiary ? Palette.textSecondary : comparison.tone.color)
        }
        return line.font(.footnote.weight(.medium))
    }
}

// MARK: - Trend

/// Runs of consecutive days laid out in a rect. Missing days leave gaps.
private struct TrendLine: Shape {
    let values: [Double?]

    static func runs(_ values: [Double?], in rect: CGRect) -> [[CGPoint]] {
        guard values.count > 1, let domain = SparklineGeometry.domain(values) else { return [] }
        let inset: CGFloat = 5
        let span = domain.upperBound - domain.lowerBound
        return SparklineGeometry.runs(values).map { run in
            run.map { p in
                CGPoint(
                    x: rect.minX + inset + (rect.width - inset * 2) * CGFloat(p.index) / CGFloat(values.count - 1),
                    y: rect.minY + inset + (rect.height - inset * 2) * CGFloat(1 - (p.value - domain.lowerBound) / span)
                )
            }
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for run in Self.runs(values, in: rect) {
            guard let first = run.first else { continue }
            if run.count == 1 {
                path.addEllipse(in: CGRect(x: first.x - 2, y: first.y - 2, width: 4, height: 4))
                continue
            }
            path.move(to: first)
            run.dropFirst().forEach { path.addLine(to: $0) }
        }
        return path
    }
}

/// Seven days of the lead metric, drawn on from the left.
struct CoachTrend: View {
    let values: [Double?]
    let metric: VitalMetric

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 7 days · \(metric.title)")
                .font(.footnote)
                .foregroundStyle(Palette.textTertiary)
            TrendLine(values: values)
                .trim(from: 0, to: reduceMotion ? 1 : drawn)
                .stroke(Palette.textSecondary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .overlay { latestDot }
                .frame(height: 40)
                .opacity(reduceMotion ? Double(drawn) : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .onAppear {
            if reduceMotion {
                withAnimation(.easeIn(duration: 0.25)) { drawn = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.9).delay(0.2)) { drawn = 1 }
            }
        }
    }

    /// Marks today when it has a value.
    private var latestDot: some View {
        GeometryReader { geo in
            if values.last.flatMap({ $0 }) != nil,
               let point = TrendLine.runs(values, in: CGRect(origin: .zero, size: geo.size)).last?.last {
                Circle()
                    .fill(Palette.textPrimary)
                    .frame(width: 8, height: 8)
                    .position(point)
                    .opacity(drawn >= 1 ? 1 : 0)
            }
        }
    }

    private var spoken: String {
        let present = values.compactMap { $0 }
        guard let first = present.first, let last = present.last else { return "" }
        return "\(metric.spokenTitle) over the last 7 days, from \(metric.spoken(first)) to \(metric.spoken(last))"
    }
}
