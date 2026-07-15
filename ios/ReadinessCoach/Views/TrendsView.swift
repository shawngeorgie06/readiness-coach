import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var response: ReadinessHistoryResponse?
    @State private var error: String?
    @State private var isLoading = false
    @State private var rangeDays = 30
    @State private var readinessSelection: Date?
    @State private var pillarSelection: Date?

    private let ranges = [7, 30, 90]

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    Picker("Range", selection: $rangeDays) {
                        ForEach(ranges, id: \.self) { days in
                            Text("\(days)D").tag(days)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: rangeDays) { _, _ in
                        readinessSelection = nil
                        pillarSelection = nil
                        Task { await load() }
                    }

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
                        ErrorCard(message: error) { Task { await load() } }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .verticalScrollLocked()
            .navigationTitle("Insights")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var points: [ReadinessPoint]? { response?.data }

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
        let dates = points.map { ChartDate.day($0.date) }
        return SectionCard(title: "Readiness — last \(response?.days ?? rangeDays) days") {
            HStack(spacing: 6) {
                Text(readinessSummary(points))
                    .font(.subheadline.weight(.medium))
                InfoBadge(title: "Readiness score",
                          message: "A 0–100 daily score. 75+ means Push, 50–74 Maintain, under 50 Recover. The score decides; the coach only ever plays it safer.")
            }
            Chart(points) { point in
                LineMark(x: .value("Date", ChartDate.day(point.date)), y: .value("Readiness", point.readiness))
                    .foregroundStyle(.secondary)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Date", ChartDate.day(point.date)), y: .value("Readiness", point.readiness))
                    .foregroundStyle(point.decision.tint)
                    .symbolSize(40)
                if let sel = readinessSelection {
                    RuleMark(x: .value("Date", sel))
                        .foregroundStyle(.secondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartYScale(domain: 0 ... 100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let n = value.as(Double.self) {
                            Text("\(Int(n))")
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(6, points.count))) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 220)
            .chartOverlay { proxy in
                ChartDayScrubOverlay(proxy: proxy, dates: dates, selection: $readinessSelection)
            }
            .clipped()

            ScrubDetailBanner(
                date: readinessSelection,
                placeholder: "Tap or drag the chart to inspect a day",
                lines: readinessLines(for: readinessSelection, in: points)
            )

            HStack(spacing: 14) {
                ForEach(Decision.allCases, id: \.self) { decision in
                    Label(decision.title, systemImage: "circle.fill")
                        .font(.caption2).foregroundStyle(decision.tint)
                        .labelStyle(.titleAndIcon)
                }
            }
            if readinessSelection == nil, let latest = points.last {
                Text("Latest \(Int(latest.readiness.rounded())) · \(latest.decision.title)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func pillarsCard(_ points: [ReadinessPoint]) -> some View {
        let dates = points.map { ChartDate.day($0.date) }
        return SectionCard(title: "Pillar scores over time") {
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
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Date", ChartDate.day(point.date)),
                             y: .value("Score", point.recoveryScore),
                             series: .value("Pillar", "Recovery"))
                        .foregroundStyle(by: .value("Pillar", "Recovery"))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Date", ChartDate.day(point.date)),
                             y: .value("Score", point.loadScore),
                             series: .value("Pillar", "Load"))
                        .foregroundStyle(by: .value("Pillar", "Load"))
                        .interpolationMethod(.catmullRom)
                }
                if let sel = pillarSelection {
                    RuleMark(x: .value("Date", sel))
                        .foregroundStyle(.secondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartForegroundStyleScale(domain: ["Sleep", "Recovery", "Load"], range: [.blue, .teal, .orange])
            .chartYScale(domain: 0 ... 100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let n = value.as(Double.self) { Text("\(Int(n))") }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(6, points.count))) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 220)
            .chartOverlay { proxy in
                ChartDayScrubOverlay(proxy: proxy, dates: dates, selection: $pillarSelection)
            }
            .clipped()

            ScrubDetailBanner(
                date: pillarSelection,
                placeholder: "Tap or drag to compare Sleep · Recovery · Load for a day",
                lines: pillarLines(for: pillarSelection, in: points)
            )
        }
    }

    private func readinessLines(for selection: Date?, in points: [ReadinessPoint]) -> [String] {
        guard let selection,
              let hit = points.first(where: { ChartDate.day($0.date) == selection })
        else { return [] }
        return [
            "Readiness \(Int(hit.readiness.rounded())) · \(hit.decision.title)",
            "Sleep \(Int(hit.sleepScore.rounded())) · Recovery \(Int(hit.recoveryScore.rounded())) · Load \(Int(hit.loadScore.rounded()))",
        ]
    }

    private func pillarLines(for selection: Date?, in points: [ReadinessPoint]) -> [String] {
        guard let selection,
              let hit = points.first(where: { ChartDate.day($0.date) == selection })
        else { return [] }
        return [
            "Sleep \(Int(hit.sleepScore.rounded()))",
            "Recovery \(Int(hit.recoveryScore.rounded()))",
            "Load \(Int(hit.loadScore.rounded()))",
        ]
    }

    private func load() async {
        guard let client = settings.makeClient() else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            response = try await client.getHistory(days: rangeDays)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
