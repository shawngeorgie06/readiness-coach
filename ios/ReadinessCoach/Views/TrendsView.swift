import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var response: ReadinessHistoryResponse?
    @State private var error: String?
    @State private var isLoading = false
    @State private var readinessSelection: Date?
    @State private var pillarSelection: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let points, !points.isEmpty {
                        readinessCard(points)
                        pillarsCard(points)
                        SleepChartsSection()
                    } else if isLoading {
                        ProgressView().padding(.top, 60)
                    } else {
                        ContentUnavailableCompat(
                            title: "No trend yet",
                            message: "Sync a few days of data to see your readiness trend.",
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                    }
                    if let error {
                        ErrorCard(message: error) { Task { await load() } }
                    }
                }
                .padding()
            }
            .navigationTitle("Trends")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var points: [ReadinessPoint]? { response?.data }

    /// Plain-language readiness trend for the summary line.
    private func readinessSummary(_ points: [ReadinessPoint]) -> String {
        guard let trend = metricTrend(values: points.map { $0.readiness }, goodDirection: .higher, threshold: 2) else {
            return "Not enough history yet to call a trend."
        }
        switch trend.direction {
        case .up:   return "Your readiness is improving lately."
        case .flat: return "Your readiness is holding steady lately."
        case .down: return "Your readiness is sliding lately."
        }
    }

    private func readinessCard(_ points: [ReadinessPoint]) -> some View {
        SectionCard(title: "Readiness — last \(response?.days ?? 0) days") {
            HStack(spacing: 6) {
                Text(readinessSummary(points))
                    .font(.subheadline.weight(.medium))
                InfoBadge(title: "Readiness score",
                          message: "A 0–100 daily score. 75+ means Push, 50–74 Maintain, under 50 Recover. The score decides; the coach only ever plays it safer.")
            }
            Chart(points) { point in
                LineMark(x: .value("Date", ChartDate.day(point.date)), y: .value("Readiness", point.readiness))
                    .foregroundStyle(.secondary)
                PointMark(x: .value("Date", ChartDate.day(point.date)), y: .value("Readiness", point.readiness))
                    .foregroundStyle(point.decision.tint)
                    .symbolSize(40)
                if let sel = readinessSelection {
                    RuleMark(x: .value("Date", sel))
                        .foregroundStyle(.gray.opacity(0.4))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            if let snapped = nearestDate(sel, in: points.map { ChartDate.day($0.date) }),
                               let hit = points.first(where: { ChartDate.day($0.date) == snapped }) {
                                ScrubReadout(date: snapped, lines: ["\(Int(hit.readiness.rounded())) · \(hit.decision.title)"])
                            }
                        }
                }
            }
            .chartYScale(domain: 0 ... 100)
            .frame(height: 200)
            .chartXSelection(value: $readinessSelection)
            HStack(spacing: 14) {
                ForEach(Decision.allCases, id: \.self) { decision in
                    Label(decision.title, systemImage: "circle.fill")
                        .font(.caption2).foregroundStyle(decision.tint)
                        .labelStyle(.titleAndIcon)
                }
            }
            if let latest = points.last {
                Text("Latest \(Int(latest.readiness.rounded())) · \(latest.decision.title)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func pillarsCard(_ points: [ReadinessPoint]) -> some View {
        SectionCard(title: "Pillar scores over time") {
            HStack(spacing: 6) {
                Text("Sleep, Recovery, and Load are the three inputs to your readiness — watch which one is dragging the others down.")
                    .font(.caption).foregroundStyle(.secondary)
                InfoBadge(title: "Pillars",
                          message: "Each pillar is scored 0–100. Your readiness is built from all three, so a low pillar here explains a low score on Today.")
            }
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Date", ChartDate.day(point.date)),
                             y: .value("Score", point.sleepScore),
                             series: .value("Pillar", "Sleep"))
                        .foregroundStyle(by: .value("Pillar", "Sleep"))
                    LineMark(x: .value("Date", ChartDate.day(point.date)),
                             y: .value("Score", point.recoveryScore),
                             series: .value("Pillar", "Recovery"))
                        .foregroundStyle(by: .value("Pillar", "Recovery"))
                    LineMark(x: .value("Date", ChartDate.day(point.date)),
                             y: .value("Score", point.loadScore),
                             series: .value("Pillar", "Load"))
                        .foregroundStyle(by: .value("Pillar", "Load"))
                }
                if let sel = pillarSelection {
                    RuleMark(x: .value("Date", sel))
                        .foregroundStyle(.gray.opacity(0.4))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            if let snapped = nearestDate(sel, in: points.map { ChartDate.day($0.date) }),
                               let hit = points.first(where: { ChartDate.day($0.date) == snapped }) {
                                ScrubReadout(date: snapped, lines: [
                                    "Sleep \(Int(hit.sleepScore.rounded()))",
                                    "Recovery \(Int(hit.recoveryScore.rounded()))",
                                    "Load \(Int(hit.loadScore.rounded()))",
                                ])
                            }
                        }
                }
            }
            .chartForegroundStyleScale(domain: ["Sleep", "Recovery", "Load"], range: [.blue, .teal, .orange])
            .chartYScale(domain: 0 ... 100)
            .frame(height: 200)
            .chartXSelection(value: $pillarSelection)
        }
    }

    private func load() async {
        guard let client = settings.makeClient() else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            response = try await client.getHistory(days: 30)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

}
