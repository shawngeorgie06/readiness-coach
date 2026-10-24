import SwiftUI

extension Pillar {
    /// VoiceOver for a pillar gauge: score, the real weight, and today's top
    /// driver. The weight is spoken here rather than drawn on the gauge.
    func gaugeAccessibilityLabel(_ score: PillarScore) -> String {
        var label = "\(title) \(Int(score.score.rounded())) of 100, \(weightPercent) percent of readiness"
        if let driver = score.drivers.first?.text, !driver.isEmpty { label += ". \(driver)" }
        return label
    }
}

/// The three pillars as equal 270° gauges. Tapping one opens its tab. At
/// accessibility sizes the gauges stack, each beside its name and driver.
struct PillarGaugeRow: View {
    let pillars: Pillars
    let open: (Pillar) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Pillar.allCases) { pillar in
                    if pillar != Pillar.allCases.first { Hairline() }
                    stackedRow(pillar)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Pillar.allCases) { pillar in
                    button(pillar) {
                        PillarGauge(
                            title: pillar.title,
                            score: pillar.score(in: pillars).score,
                            tint: pillar.color,
                            entranceKey: "today.\(pillar.title)"
                        )
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                }
            }
        }
    }

    private func stackedRow(_ pillar: Pillar) -> some View {
        let score = pillar.score(in: pillars)
        return button(pillar) {
            VStack(alignment: .leading, spacing: 12) {
                PillarGauge(
                    title: pillar.title,
                    score: score.score,
                    tint: pillar.color,
                    maxDiameter: 150,
                    entranceKey: "today.\(pillar.title)",
                    showsTitle: false
                )
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pillar.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                        if let driver = score.drivers.first?.text {
                            Text(driver)
                                .font(.body)
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.vertical, Space.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    private func button(_ pillar: Pillar, @ViewBuilder label: () -> some View) -> some View {
        Button { open(pillar) } label: { label() }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pillar.gaugeAccessibilityLabel(pillar.score(in: pillars)))
            .accessibilityHint("Opens the \(AppTab(pillar).title) tab")
            .accessibilityAddTraits(.isButton)
    }
}

/// The advisor's prescription as a headline, then one "why" line that expands
/// to every reason and what happens if it's ignored. Every line stays
/// reachable; nothing from the note is dropped.
struct TodayPlanSection: View {
    let note: AdvisorNote
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    private var lead: String { note.why.first ?? "If ignored" }
    private var moreReasons: [String] { Array(note.why.dropFirst()) }

    var body: some View {
        OpenSection("Today's plan") {
            VStack(alignment: .leading, spacing: 10) {
                Text(note.prescription)
                    .font(Typeface.headline)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(lead)
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(expanded ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.textTertiary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .frame(minHeight: Space.target)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(lead)
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                .accessibilityHint(expanded ? "Hides the reasons" : "Shows every reason and what happens if ignored")
                .accessibilityAddTraits(.isButton)

                if expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(moreReasons.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !note.why.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("If ignored")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.textPrimary)
                                Text(note.ifIgnored)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                            .padding(.top, 4)
                        } else {
                            Text(note.ifIgnored)
                                .font(.subheadline)
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}

/// HRV, resting HR, sleep and 7-day load from the server's `baselines`: value,
/// a 14-day sparkline and the change from normal. Four columns by default, two
/// at large text, a list of comparison rows at accessibility sizes.
struct VitalsSection: View {
    let comparisons: [MetricComparison]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        OpenSection("Vitals") {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(comparisons.enumerated()), id: \.element.id) { index, comparison in
                        ComparisonRow(comparison: comparison, showsSparkline: true, showsRule: index > 0)
                    }
                }
            } else {
                let columns = Array(
                    repeating: GridItem(.flexible(), spacing: 14, alignment: .topLeading),
                    count: typeSize >= .xxLarge ? 2 : 4
                )
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(comparisons) { VitalColumn(comparison: $0) }
                }
            }
        }
    }
}

private struct VitalColumn: View {
    let comparison: MetricComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(comparison.metric.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(comparison.todayText)
                    .font(Typeface.value)
                    .foregroundStyle(Palette.textPrimary)
                if comparison.today != nil, let unit = comparison.metric.unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Sparkline(values: comparison.recent, color: comparison.tone.color)
                .frame(height: 24)
            ComparisonBadge(comparison: comparison, compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(comparison.accessibilityText)
    }
}

/// Today's loading placeholder, shaped like the screen it becomes.
struct TodaySkeleton: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            SkeletonHead()
            if typeSize.isAccessibilitySize {
                SkeletonGauge(maxDiameter: 150)
            } else {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in SkeletonGauge().frame(maxWidth: .infinity) }
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Hairline()
                SkeletonBlock(width: 96, height: 14)
                SkeletonBlock(height: 22)
                SkeletonLines(count: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading today")
    }
}
