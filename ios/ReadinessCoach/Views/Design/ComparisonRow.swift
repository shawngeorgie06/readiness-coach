import SwiftUI

/// A 14-day line without axes. Missing days are gaps; a lone day between gaps
/// is a dot. Decorative to VoiceOver: the owning row speaks the numbers.
struct Sparkline: View {
    let values: [Double?]
    var color: Color = Palette.textTertiary
    var lineWidth: CGFloat = 1.5

    var body: some View {
        Canvas { context, size in
            guard let domain = SparklineGeometry.domain(values), values.count > 1 else { return }
            let inset = lineWidth + 1
            let height = max(size.height - inset * 2, 1)
            let stepX = size.width / CGFloat(values.count - 1)
            func point(_ p: SparklineGeometry.Point) -> CGPoint {
                let fraction = (p.value - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
                return CGPoint(x: CGFloat(p.index) * stepX, y: inset + height * (1 - fraction))
            }
            for run in SparklineGeometry.runs(values) {
                if run.count == 1 {
                    let c = point(run[0])
                    let r = lineWidth * 1.4
                    context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
                } else {
                    var path = Path()
                    path.addLines(run.map(point))
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The comparison in the metric's tone, never colour alone. Compact: one line
/// for a narrow column. Full: the arrowed status ("Below target") over the
/// change and what it's measured against ("+1h vs avg"), so a night that beat
/// the average but missed the target can't read as a contradiction.
struct ComparisonBadge: View {
    let comparison: MetricComparison
    var compact = false
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            HStack(spacing: 4) {
                if let arrow = comparison.arrowSymbol {
                    Image(systemName: arrow)
                        .font(.caption2.weight(.bold))
                }
                Text(compact ? comparison.compactText : comparison.summary)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(comparison.position == nil ? Palette.textTertiary : comparison.tone.color)
            if !compact, let change = comparison.changeText {
                Text(change)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([comparison.summary, comparison.spokenChange].compactMap { $0 }.joined(separator: ". "))
    }
}

/// "Compared with normal" row: metric · today · reference · status and change.
/// A hairline sits above. Stacks at accessibility sizes. Callers that follow
/// the spec's hide rule skip rows whose `today` is nil.
struct ComparisonRow: View {
    let comparison: MetricComparison
    var showsSparkline = false
    var showsRule = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsRule { Hairline() }
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        title
                        value
                        normal
                        ComparisonBadge(comparison: comparison)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        title.frame(maxWidth: .infinity, alignment: .leading)
                        value
                        normal.frame(minWidth: 64, alignment: .trailing)
                        ComparisonBadge(comparison: comparison, alignment: .trailing)
                            .frame(minWidth: 72, alignment: .trailing)
                    }
                }
            }
            if showsSparkline {
                Sparkline(values: comparison.recent, color: comparison.tone.color.opacity(0.9))
                    .frame(height: 28)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(comparison.accessibilityText)
    }

    private var title: some View {
        Text(comparison.metric.title)
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
    }

    private var value: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(comparison.todayText)
                .font(Typeface.value)
                .foregroundStyle(Palette.textPrimary)
            if comparison.today != nil, let unit = comparison.metric.unit {
                Text(unit).font(.caption).foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private var normal: some View {
        Text(comparison.normalCaption ?? "")
            .font(.footnote)
            .foregroundStyle(Palette.textTertiary)
            .monospacedDigit()
    }
}
