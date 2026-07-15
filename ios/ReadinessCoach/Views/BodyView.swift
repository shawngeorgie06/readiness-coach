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
    @State private var explain: MetricExplain?

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

                    Text("Tap a metric title for a plain-language explainer. Drag or tap the chart to inspect each day — same smooth scrubbing as Insights.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let response, !response.daily.isEmpty {
                        lineCard(
                            title: "Heart rate variability",
                            type: "hrv_sdnn",
                            color: .teal,
                            unit: "ms",
                            goodDirection: .higher,
                            threshold: 2,
                            explain: MetricExplain(
                                title: "Heart rate variability (HRV)",
                                body: "HRV is the tiny variation between heartbeats (SDNN, in milliseconds). Higher and rising usually means your nervous system is recovered. We compare today’s average to your recent baseline — a drop often shows up before you feel wiped out."
                            ),
                            rows: response.daily,
                            selection: $hrvSelection
                        )
                        lineCard(
                            title: "Resting heart rate",
                            type: "resting_heart_rate",
                            color: .pink,
                            unit: "bpm",
                            goodDirection: .lower,
                            threshold: 1.5,
                            explain: MetricExplain(
                                title: "Resting heart rate (RHR)",
                                body: "Your pulse at rest, in beats per minute. A lower resting heart rate usually means better fitness and recovery. An unexpected rise — especially with low HRV — is a signal to take it easier."
                            ),
                            rows: response.daily,
                            selection: $rhrSelection
                        )
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
                .pageWidthLocked()
                .padding()
            }
            .verticalScrollLocked()
            .navigationTitle("Body")
            .sheet(item: $explain) { item in
                NavigationStack {
                    ScrollView {
                        Text(item.body)
                            .font(.body)
                            .padding()
                    }
                    .navigationTitle(item.title)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { explain = nil }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    @ViewBuilder
    private func lineCard(
        title: String,
        type: String,
        color: Color,
        unit: String,
        goodDirection: GoodDirection,
        threshold: Double,
        explain: MetricExplain,
        rows: [BodyDaily],
        selection: Binding<Date?>
    ) -> some View {
        let series = rows.filter { $0.type == type }.sorted { $0.date < $1.date }
        let dates = series.map { ChartDate.day($0.date) }
        if !series.isEmpty {
            SectionCard(title: title) {
                Button {
                    self.explain = explain
                } label: {
                    HStack(spacing: 6) {
                        if let trend = metricTrend(values: series.map { $0.avg }, goodDirection: goodDirection, threshold: threshold) {
                            Text("Averaging \(fmt(trend.recentAvg)) \(unit) — \(trend.phrase).")
                                .font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.leading)
                        } else if let latest = series.last {
                            Text("Latest \(fmt(latest.avg)) \(unit).")
                                .font(.subheadline.weight(.medium))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Chart(series) { day in
                    LineMark(x: .value("Date", ChartDate.day(day.date)), y: .value("Avg", day.avg))
                        .foregroundStyle(color)
                        .interpolationMethod(ChartStyle.smooth)
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
                    lines: lineLines(for: selection.wrappedValue, in: series, unit: unit),
                    note: lineNote(for: selection.wrappedValue, in: series, unit: unit, goodDirection: goodDirection)
                )
            }
            .onAppear {
                if selection.wrappedValue == nil, let last = dates.last {
                    selection.wrappedValue = last
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
                Button {
                    explain = MetricExplain(
                        title: "Daily heart rate range",
                        body: "Each day shows your lowest, average, and highest heart rate from Apple Health. The band is the min–max spread; the line is the daily average. Useful context for how hard life + training stressed your system — not a readiness score by itself."
                    )
                } label: {
                    HStack(spacing: 6) {
                        Text("Lowest · average · highest heart rate each day.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Chart(series) { day in
                    AreaMark(
                        x: .value("Date", ChartDate.day(day.date)),
                        yStart: .value("Min", day.min),
                        yEnd: .value("Max", day.max)
                    )
                    .foregroundStyle(.red.opacity(0.15))
                    LineMark(x: .value("Date", ChartDate.day(day.date)), y: .value("Avg", day.avg))
                        .foregroundStyle(.red)
                        .interpolationMethod(ChartStyle.smooth)
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
                    lines: hrLines(for: hrSelection, in: series),
                    note: "Min is the calmest reading that day; max is usually exercise or stress. Average sits between them."
                )
            }
            .onAppear {
                if hrSelection == nil, let last = dates.last {
                    hrSelection = last
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

    private func lineNote(for selection: Date?, in series: [BodyDaily], unit: String, goodDirection: GoodDirection) -> String? {
        guard let selection,
              let idx = series.firstIndex(where: { ChartDate.day($0.date) == selection }),
              idx > 0
        else {
            return goodDirection == .higher
                ? "Higher \(unit == "ms" ? "HRV" : "values") usually means better recovered."
                : "Lower resting values usually mean better recovered."
        }
        let hit = series[idx]
        let prev = series[idx - 1]
        let delta = hit.avg - prev.avg
        let absDelta = abs(delta)
        let nicer = absDelta == absDelta.rounded() ? String(Int(absDelta)) : String(format: "%.1f", absDelta)
        if absDelta < 0.05 {
            return "About the same as the previous day."
        }
        if delta > 0 {
            return goodDirection == .higher
                ? "Up \(nicer) \(unit) vs the previous day — usually a better recovery signal."
                : "Up \(nicer) \(unit) vs the previous day — often a sign you need more recovery."
        }
        return goodDirection == .higher
            ? "Down \(nicer) \(unit) vs the previous day — recovery may be lagging."
            : "Down \(nicer) \(unit) vs the previous day — usually a better recovery signal."
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

struct MetricExplain: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}
