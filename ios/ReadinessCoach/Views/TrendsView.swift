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
                .pageWidthLocked()
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
            Text("Tap any day on the chart to see the date, score, decision, and what changed vs the day before.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(points) { point in
                LineMark(x: .value("Date", ChartDate.day(point.date)), y: .value("Readiness", point.readiness))
                    .foregroundStyle(.secondary)
                    .interpolationMethod(ChartStyle.smooth)
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
                ChartDayScrubOverlay(proxy: proxy, dates: dates, selection: $readinessSelection)
            }
            .clipped()

            ScrubDetailBanner(
                date: readinessSelection,
                placeholder: "Tap a point to inspect that day",
                lines: readinessLines(for: readinessSelection, in: points),
                note: readinessNote(for: readinessSelection, in: points)
            )

            HStack(spacing: 14) {
                ForEach(Decision.allCases, id: \.self) { decision in
                    Label(decision.title, systemImage: "circle.fill")
                        .font(.caption2).foregroundStyle(decision.tint)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .onAppear {
            if readinessSelection == nil, let last = dates.last {
                readinessSelection = last
            }
        }
    }

    private func pillarsCard(_ points: [ReadinessPoint]) -> some View {
        let dates = points.map { ChartDate.day($0.date) }
        return SectionCard(title: "Pillar scores over time") {
            HStack(spacing: 6) {
                Text("Sleep, Recovery, and Load feed readiness. Tap a day to see each pillar’s score.")
                    .font(.caption).foregroundStyle(.secondary)
                InfoBadge(title: "Pillars",
                          message: "Sleep (35%): rest quality. Recovery (40%): HRV + resting heart rate vs your baseline. Load (25%): recent training strain. A weak pillar usually explains a weak readiness day.")
            }
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Date", ChartDate.day(point.date)),
                             y: .value("Score", point.sleepScore),
                             series: .value("Pillar", "Sleep"))
                        .foregroundStyle(by: .value("Pillar", "Sleep"))
                        .interpolationMethod(ChartStyle.smooth)
                    LineMark(x: .value("Date", ChartDate.day(point.date)),
                             y: .value("Score", point.recoveryScore),
                             series: .value("Pillar", "Recovery"))
                        .foregroundStyle(by: .value("Pillar", "Recovery"))
                        .interpolationMethod(ChartStyle.smooth)
                    LineMark(x: .value("Date", ChartDate.day(point.date)),
                             y: .value("Score", point.loadScore),
                             series: .value("Pillar", "Load"))
                        .foregroundStyle(by: .value("Pillar", "Load"))
                        .interpolationMethod(ChartStyle.smooth)
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
                placeholder: "Tap to compare Sleep · Recovery · Load for a day",
                lines: pillarLines(for: pillarSelection, in: points),
                note: pillarNote(for: pillarSelection, in: points)
            )
        }
        .onAppear {
            if pillarSelection == nil, let last = dates.last {
                pillarSelection = last
            }
        }
    }

    private func readinessLines(for selection: Date?, in points: [ReadinessPoint]) -> [String] {
        guard let hit = point(on: selection, in: points) else { return [] }
        var lines = [
            "Readiness \(Int(hit.readiness.rounded())) · \(hit.decision.title)",
            "Sleep \(Int(hit.sleepScore.rounded())) · Recovery \(Int(hit.recoveryScore.rounded())) · Load \(Int(hit.loadScore.rounded()))",
        ]
        if let delta = delta(for: hit, in: points) {
            lines.insert(deltaLabel(delta), at: 1)
        }
        return lines
    }

    private func readinessNote(for selection: Date?, in points: [ReadinessPoint]) -> String? {
        guard let hit = point(on: selection, in: points) else { return nil }
        if let delta = delta(for: hit, in: points) {
            let absDelta = Int(abs(delta).rounded())
            if absDelta == 0 {
                return "Unchanged vs the previous scored day. Decision bands: 75+ Push, 50–74 Maintain, under 50 Recover."
            }
            if delta < 0 {
                return "Down \(absDelta) point\(absDelta == 1 ? "" : "s") vs the previous day — your body was less ready. Check which pillar dropped below."
            }
            return "Up \(absDelta) point\(absDelta == 1 ? "" : "s") vs the previous day — recovery/load conditions improved."
        }
        return "Decision bands: 75+ Push, 50–74 Maintain, under 50 Recover."
    }

    private func pillarLines(for selection: Date?, in points: [ReadinessPoint]) -> [String] {
        guard let hit = point(on: selection, in: points) else { return [] }
        return [
            "Sleep \(Int(hit.sleepScore.rounded())) — rest quality vs your need",
            "Recovery \(Int(hit.recoveryScore.rounded())) — HRV & resting heart rate",
            "Load \(Int(hit.loadScore.rounded())) — recent training strain",
        ]
    }

    private func pillarNote(for selection: Date?, in points: [ReadinessPoint]) -> String? {
        guard let hit = point(on: selection, in: points) else { return nil }
        let ranked = [
            ("Sleep", hit.sleepScore),
            ("Recovery", hit.recoveryScore),
            ("Load", hit.loadScore),
        ].sorted { $0.1 < $1.1 }
        if let weakest = ranked.first {
            return "\(weakest.0) was the weakest input this day (\(Int(weakest.1.rounded()))/100), so it pulled readiness down the most."
        }
        return nil
    }

    private func point(on selection: Date?, in points: [ReadinessPoint]) -> ReadinessPoint? {
        guard let selection else { return nil }
        return points.first(where: { ChartDate.day($0.date) == selection })
    }

    private func delta(for hit: ReadinessPoint, in points: [ReadinessPoint]) -> Double? {
        guard let idx = points.firstIndex(where: { $0.id == hit.id }), idx > 0 else { return nil }
        return hit.readiness - points[idx - 1].readiness
    }

    private func deltaLabel(_ delta: Double) -> String {
        let n = Int(delta.rounded())
        if n == 0 { return "Change vs prior day · 0 points" }
        if n > 0 { return "Change vs prior day · +\(n) points" }
        return "Change vs prior day · \(n) points"
    }

    private func load() async {
        guard let client = settings.makeClient() else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            response = try await client.getHistory(days: rangeDays)
            if readinessSelection == nil, let last = response?.data.last {
                readinessSelection = ChartDate.day(last.date)
            }
            if pillarSelection == nil, let last = response?.data.last {
                pillarSelection = ChartDate.day(last.date)
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
