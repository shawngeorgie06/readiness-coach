import SwiftUI

/// One past day from the readiness history, exactly as the history response
/// sent it. Read-only by construction: no client, no store, no recompute, so
/// opening a past day can't overwrite its score or start a coach note.
struct DaySummary: Hashable, Identifiable {
    let date: String
    let readiness: Double
    let decision: Decision
    let recovery: Double
    let sleep: Double
    let load: Double
    let calibrating: Bool

    var id: String { date }

    init(_ point: ReadinessPoint) {
        date = point.date
        readiness = point.readiness
        decision = point.decision
        recovery = point.recoveryScore
        sleep = point.sleepScore
        load = point.loadScore
        calibrating = point.calibrating
    }

    func score(_ pillar: Pillar) -> Double {
        switch pillar {
        case .recovery: return recovery
        case .sleep: return sleep
        case .load: return load
        }
    }

    /// The verdict follows the saved decision, never the score band, so an
    /// override can't look greener than the call that day.
    var verdictBand: ScoreBand { decision.band }

    var dayText: String { StatusLineModel.formattedDay(date) }

    var accessibilityLabel: String {
        var label = "\(dayText). Readiness \(Int(readiness.rounded())) of 100. Decision: \(decision.title)."
        if calibrating { label += " Calibrating; your baseline was still forming." }
        return label
    }

    func pillarAccessibilityLabel(_ pillar: Pillar) -> String {
        "\(pillar.title) \(Int(score(pillar).rounded())) of 100, \(pillar.weightPercent) percent of readiness"
    }
}

/// A past day's saved readiness, decision and pillar scores. Pushed from
/// History; nothing here reaches the network.
struct DaySummaryView: View {
    let summary: DaySummary
    @ScaledMetric(relativeTo: .title) private var rowNumeral: CGFloat = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                ScoreHead(
                    score: summary.readiness,
                    verdict: summary.decision.title,
                    verdictColor: summary.verdictBand.color,
                    meaning: "Readiness · the call for this day",
                    note: summary.calibrating ? "Calibrating — your baseline was still forming" : nil,
                    noteSystemImage: "hourglass",
                    accessibilityLabel: summary.accessibilityLabel
                )

                OpenSection("Pillar scores") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Pillar.allCases) { pillar in
                            if pillar != Pillar.allCases.first { Hairline() }
                            pillarRow(pillar)
                        }
                    }
                }

                OpenSection("About this summary") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Decision bands: 75+ Push · 50–74 Maintain · under 50 Recover. Overrides can make a call more conservative than its score.")
                        Text("A saved snapshot of your readiness and pillar scores for this day.")
                    }
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle(summary.dayText)
    }

    private func pillarRow(_ pillar: Pillar) -> some View {
        let score = summary.score(pillar)
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: pillar.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(pillar.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(pillar.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("\(pillar.weightPercent)% of readiness")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 8)
            Text("\(Int(score.rounded()))")
                .font(Typeface.numeral(rowNumeral, width: .condensed))
                .foregroundStyle(ScoreBand(score: score).numeralColor)
        }
        .frame(minHeight: Space.target)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.pillarAccessibilityLabel(pillar))
    }
}
