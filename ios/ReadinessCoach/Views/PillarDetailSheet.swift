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
    @Environment(\.dismiss) private var dismiss

    private var identity: Pillar? { Pillar.allCases.first { $0.title == info.name } }

    var body: some View {
        let score = info.pillar.score
        let band = ScoreBand(score: score)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    ScoreHead(
                        score: score,
                        verdict: info.name,
                        verdictColor: band.color,
                        meaning: info.description,
                        note: "\(info.weight) of readiness",
                        noteSystemImage: identity?.systemImage,
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

                    OpenSection("How it counts") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Pillar.allCases) { pillar in
                                if pillar != Pillar.allCases.first { Hairline() }
                                weightRow(pillar)
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .sheetSurface()
            .navigationTitle(info.name)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
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

    private func weightRow(_ pillar: Pillar) -> some View {
        let isThis = pillar == identity
        return HStack(spacing: 12) {
            Image(systemName: pillar.systemImage)
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

extension View {
    /// Sheets are the one filled surface: dark surface behind the content and
    /// the navigation bar.
    func sheetSurface() -> some View {
        self
            .foregroundStyle(Palette.textPrimary)
            .scrollContentBackground(.hidden)
            .background(Palette.surface.ignoresSafeArea())
            .toolbarBackground(Palette.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .presentationBackground(Palette.surface)
    }
}
