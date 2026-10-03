import SwiftUI

/// One pillar of the score: name and weight, today's top driver, the score,
/// and a bar in the pillar colour. Tapping opens that pillar's tab.
struct PillarRow: View {
    let pillar: Pillar
    let score: PillarScore
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var driver: String { score.drivers.first?.text ?? pillar.summary }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
                layout {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(pillar.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Palette.textPrimary)
                            Text("\(pillar.weightPercent)%")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        Text(driver)
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 12) {
                        Text("\(Int(score.score.rounded()))")
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textPrimary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                MetricBar(value: score.score / 100, score: score.score, tint: pillar.color)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pillar.title), \(pillar.weightPercent) percent of readiness, score \(Int(score.score.rounded())). \(driver)")
        .accessibilityHint("Opens the \(AppTab(pillar).title) tab")
    }
}

/// The three pillars stacked with hairline dividers, on one flat surface.
struct PillarBreakdown: View {
    let pillars: Pillars
    let open: (Pillar) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Pillar.allCases) { pillar in
                PillarRow(pillar: pillar, score: pillar.score(in: pillars)) { open(pillar) }
                if pillar != Pillar.allCases.last {
                    Divider().overlay(Palette.strokeSoft)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
