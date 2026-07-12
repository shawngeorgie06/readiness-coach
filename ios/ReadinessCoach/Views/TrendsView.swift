import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var response: ReadinessHistoryResponse?
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let points, !points.isEmpty {
                        readinessCard(points)
                        pillarsCard(points)
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
                        Text(error).font(.footnote).foregroundStyle(.red)
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

    private func readinessCard(_ points: [ReadinessPoint]) -> some View {
        SectionCard(title: "Readiness — last \(response?.days ?? 0) days") {
            Chart(points) { point in
                LineMark(x: .value("Date", ChartDate.day(point.date)), y: .value("Readiness", point.readiness))
                    .foregroundStyle(.secondary)
                PointMark(x: .value("Date", ChartDate.day(point.date)), y: .value("Readiness", point.readiness))
                    .foregroundStyle(point.decision.tint)
                    .symbolSize(40)
            }
            .chartYScale(domain: 0 ... 100)
            .frame(height: 200)
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
            }
            .chartForegroundStyleScale(domain: ["Sleep", "Recovery", "Load"], range: [.blue, .teal, .orange])
            .chartYScale(domain: 0 ... 100)
            .frame(height: 200)
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
