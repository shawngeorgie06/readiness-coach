import SwiftUI

struct PillarInfo: Identifiable {
    let id = UUID()
    let name: String
    let weight: String
    let description: String
    let pillar: PillarScore
}

/// One pillar's score, what it measures, the drivers behind today's number
/// and how much it counts toward readiness. Open rows on the sheet surface.
struct PillarDetailSheet: View {
    let info: PillarInfo

    private var identity: Pillar? { Pillar.allCases.first { $0.title == info.name } }

    var body: some View {
        SheetScaffold(
            title: info.name,
            context: "Readiness pillar · \(info.weight)",
            systemImage: identity?.sheetSymbol ?? "chart.bar.xaxis",
            tone: identity?.sheetTone ?? .neutral
        ) {
            PillarDetailContent(info: info)
        }
    }
}

/// Today's complete breakdown in one native sheet, without nested sheet or
/// navigation hosts. Every pillar keeps its score, weight and original drivers.
struct ScoringDriversSheet: View {
    let pillars: Pillars

    var body: some View {
        SheetScaffold(title: "All scoring drivers", context: "Readiness breakdown", systemImage: "chart.bar.xaxis") {
            ForEach(Pillar.allCases) { pillar in
                VStack(alignment: .leading, spacing: 16) {
                    Label(pillar.title, systemImage: pillar.sheetSymbol)
                        .font(Typeface.headline)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    PillarDetailContent(
                        info: PillarInfo(name: pillar.title, weight: "\(pillar.weightPercent)%",
                                         description: pillar.summary, pillar: pillar.score(in: pillars)),
                        includesWeights: false
                    )
                }
                if pillar != Pillar.allCases.last { Hairline() }
            }
            PillarWeights(identity: nil)
        }
    }
}

private struct PillarDetailContent: View {
    let info: PillarInfo
    var includesWeights = true
    private var identity: Pillar? { Pillar.allCases.first { $0.title == info.name } }

    var body: some View {
        let score = info.pillar.score
        let band = ScoreBand(score: score)
        VStack(alignment: .leading, spacing: Space.section) {
            ScoreHead(
                score: score,
                verdict: "Pillar score",
                verdictColor: band.color,
                meaning: info.description,
                note: "\(info.weight) of readiness",
                noteSystemImage: identity?.sheetSymbol,
                accessibilityLabel: "\(info.name) \(Int(score.rounded())) of 100. \(info.description). \(info.weight) of readiness."
            )

            OpenSection("Today's drivers") {
                if info.pillar.drivers.isEmpty {
                    Text("No drivers reported for this score yet.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(info.pillar.drivers.enumerated()), id: \.offset) { index, driver in
                            if index > 0 { Hairline() }
                            driverRow(driver)
                        }
                    }
                }
            }

            if includesWeights {
                PillarWeights(identity: identity)
            }
        }
    }

    private func driverRow(_ driver: Driver) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill(identity?.color ?? Palette.textTertiary)
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(driver.text)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                if let detail = driver.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(minHeight: Space.target)
        .accessibilityElement(children: .combine)
    }
}

private struct PillarWeights: View {
    let identity: Pillar?

    var body: some View {
        OpenSection("How it counts") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Pillar.allCases) { pillar in
                    if pillar != Pillar.allCases.first { Hairline() }
                    weightRow(pillar)
                }
            }
        }
    }

    private func weightRow(_ pillar: Pillar) -> some View {
        let isThis = pillar == identity
        return HStack(spacing: 12) {
            Image(systemName: pillar.sheetSymbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(pillar.color)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(pillar.title)
                .font(isThis ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(isThis ? Palette.textPrimary : Palette.textSecondary)
            Spacer(minLength: 8)
            Text("\(pillar.weightPercent)%")
                .font(.subheadline.weight(isThis ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(isThis ? Palette.textPrimary : Palette.textSecondary)
        }
        .frame(minHeight: Space.target)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pillar.title), \(pillar.weightPercent) percent of readiness")
    }
}

private extension Pillar {
    var sheetSymbol: String {
        switch self {
        case .recovery: return "waveform.path.ecg"
        case .sleep: return "moon.zzz"
        case .load: return "flame"
        }
    }

    var sheetTone: SheetTone {
        switch self {
        case .recovery: return .recovery
        case .sleep: return .sleep
        case .load: return .load
        }
    }
}
