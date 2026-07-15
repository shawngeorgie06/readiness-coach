import SwiftUI
import Charts

struct BodyView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var response: BodyResponse?
    @State private var error: String?
    @State private var isLoading = false
    @State private var rangeDays = 30
    @State private var hrvSelection: Date?
    @State private var rhrSelection: Date?
    @State private var hrSelection: Date?

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
                        hrvSelection = nil; rhrSelection = nil; hrSelection = nil
                        Task { await load() }
                    }

                    if let response, !response.daily.isEmpty {
                        lineCard("Heart rate variability", type: "hrv_sdnn", color: .teal, unit: "ms",
                                 goodDirection: .higher, threshold: 2,
                                 badge: (title: "Heart rate variability",
                                         message: "The beat-to-beat variation in your heart rate, a read on nervous-system recovery. Higher — and rising — generally means better recovered. Shown as SDNN in milliseconds."),
                                 rows: response.daily, selection: $hrvSelection)
                        lineCard("Resting heart rate", type: "resting_heart_rate", color: .pink, unit: "bpm",
                                 goodDirection: .lower, threshold: 1.5,
                                 badge: (title: "Resting heart rate",
                                         message: "Your heart rate at rest. A lower resting heart rate usually signals better fitness and recovery."),
                                 rows: response.daily, selection: $rhrSelection)
                        heartRateCard(response.daily)
                    } else if isLoading {
                        ProgressView().padding(.top, 60)
                    } else {
                        ContentUnavailableCompat(
                            title: "No body metrics",
                            message: "Sync from the Today tab to load HRV and heart rate.",
                            systemImage: "heart"
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
            .navigationTitle("Body")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    @ViewBuilder
    private func lineCard(_ title: String, type: String, color: Color, unit: String,
                          goodDirection: GoodDirection, threshold: Double,
                          badge: (title: String, message: String),
                          rows: [BodyDaily], selection: Binding<Date?>) -> some View {
        let series = rows.filter { $0.type == type }.sorted { $0.date < $1.date }
        let dates = series.map { ChartDate.day($0.date) }
        if !series.isEmpty {
            SectionCard(title: title) {
                if let trend = metricTrend(values: series.map { $0.avg }, goodDirection: goodDirection, threshold: threshold) {
                    HStack(spacing: 6) {
                        Text("Averaging \(fmt(trend.recentAvg)) \(unit) — \(trend.phrase).")
                            .font(.subheadline.weight(.medium))
                        InfoBadge(title: badge.title, message: badge.message)
                    }
                } else if let latest = series.last {
                    HStack(spacing: 6) {
                        Text("Latest \(fmt(latest.avg)) \(unit).")
                            .font(.subheadline.weight(.medium))
                        InfoBadge(title: badge.title, message: badge.message)
                    }
                }
                Chart(series) { day in
                    LineMark(x: .value("Date", ChartDate.day(day.date)), y: .value("Avg", day.avg))
                        .foregroundStyle(color)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", ChartDate.day(day.date)), y: .value("Avg", day.avg))
                        .foregroundStyle(color).symbolSize(18)
                    if let sel = selection.wrappedValue {
                        RuleMark(x: .value("Date", sel))
                            .foregroundStyle(.secondary.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(6, series.count))) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxisLabel(unit, position: .leading, alignment: .center)
                .frame(height: 200)
                .chartOverlay { proxy in
                    ChartDayScrubOverlay(proxy: proxy, dates: dates, selection: selection)
                }
                .clipped()

                ScrubDetailBanner(
                    date: selection.wrappedValue,
                    placeholder: "Tap or drag to inspect a day (\(unit))",
                    lines: lineLines(for: selection.wrappedValue, in: series, unit: unit)
                )

                if selection.wrappedValue == nil, let latest = series.last {
                    Text("Latest avg \(fmt(latest.avg)) \(unit)  (range \(fmt(latest.min))–\(fmt(latest.max)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func heartRateCard(_ rows: [BodyDaily]) -> some View {
        let series = rows.filter { $0.type == "heart_rate" }.sorted { $0.date < $1.date }
        let dates = series.map { ChartDate.day($0.date) }
        if !series.isEmpty {
            SectionCard(title: "Heart rate — daily range") {
                HStack(spacing: 6) {
                    Text("The lowest, average, and highest heart rate each day.")
                        .font(.caption).foregroundStyle(.secondary)
                    InfoBadge(title: "Daily heart rate",
                              message: "The lowest, average, and highest heart rate recorded each day. Useful context, not a readiness score on its own.")
                }
                Chart(series) { day in
                    AreaMark(
                        x: .value("Date", ChartDate.day(day.date)),
                        yStart: .value("Min", day.min),
                        yEnd: .value("Max", day.max)
                    )
                    .foregroundStyle(.red.opacity(0.15))
                    LineMark(x: .value("Date", ChartDate.day(day.date)), y: .value("Avg", day.avg))
                        .foregroundStyle(.red)
                        .interpolationMethod(.catmullRom)
                    if let sel = hrSelection {
                        RuleMark(x: .value("Date", sel))
                            .foregroundStyle(.secondary.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(6, series.count))) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxisLabel("bpm", position: .leading, alignment: .center)
                .frame(height: 210)
                .chartOverlay { proxy in
                    ChartDayScrubOverlay(proxy: proxy, dates: dates, selection: $hrSelection)
                }
                .clipped()

                ScrubDetailBanner(
                    date: hrSelection,
                    placeholder: "Tap or drag to see min · avg · max for a day",
                    lines: hrLines(for: hrSelection, in: series)
                )

                if hrSelection == nil, let latest = series.last {
                    Text("Latest — min \(fmt(latest.min)) · avg \(fmt(latest.avg)) · max \(fmt(latest.max)) bpm")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func lineLines(for selection: Date?, in series: [BodyDaily], unit: String) -> [String] {
        guard let selection,
              let hit = series.first(where: { ChartDate.day($0.date) == selection })
        else { return [] }
        return [
            "Average \(fmt(hit.avg)) \(unit)",
            "Range \(fmt(hit.min))–\(fmt(hit.max)) \(unit) · \(hit.count) samples",
        ]
    }

    private func hrLines(for selection: Date?, in series: [BodyDaily]) -> [String] {
        guard let selection,
              let hit = series.first(where: { ChartDate.day($0.date) == selection })
        else { return [] }
        return [
            "Min \(fmt(hit.min)) bpm",
            "Avg \(fmt(hit.avg)) bpm",
            "Max \(fmt(hit.max)) bpm",
        ]
    }

    private func load() async {
        guard let client = settings.makeClient() else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            response = try await client.getBody(days: rangeDays)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
