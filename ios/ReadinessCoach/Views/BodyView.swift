import SwiftUI
import Charts

struct BodyView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var response: BodyResponse?
    @State private var error: String?
    @State private var isLoading = false
    @State private var hrvSelection: Date?
    @State private var rhrSelection: Date?
    @State private var hrSelection: Date?
    @State private var pillars: Pillars?
    @State private var explain: MetricExplain?

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    header
                    if let pillars { readoutCard(pillars) }
                    if let response, !response.daily.isEmpty {
                        vitals(response.daily)
                        lineCard("Heart rate variability", type: "hrv_sdnn", color: Palette.mint, unit: "ms",
                                 goodDirection: .higher, threshold: 2,
                                 explain: MetricExplain(
                                    title: "Heart rate variability (HRV)",
                                    body: "HRV is the tiny variation between heartbeats (SDNN, ms). Higher and rising usually means your nervous system is recovered. We compare today’s average to your recent baseline."
                                 ),
                                 rows: response.daily, selection: $hrvSelection)
                        lineCard("Resting heart rate", type: "resting_heart_rate", color: Palette.accent, unit: "bpm",
                                 goodDirection: .lower, threshold: 1.5,
                                 explain: MetricExplain(
                                    title: "Resting heart rate (RHR)",
                                    body: "Your pulse at rest. Lower usually means better fitness and recovery. An unexpected rise — especially with low HRV — is a cue to ease off."
                                 ),
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
                .pageWidthLocked()
                .padding()
            }
            .verticalScrollLocked()
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $explain) { item in
                NavigationStack {
                    ScrollView {
                        Text(item.body).font(.body).padding()
                    }
                    .navigationTitle(item.title)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { explain = nil } } }
                }
                .presentationDetents([.medium, .large])
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Signals")
                Text("Body").font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func readoutCard(_ pillars: Pillars) -> some View {
        let driver = pillars.recovery.drivers.first
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Readout")
            Text(driver?.text ?? "Recovery signals")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
            if let detail = driver?.detail {
                Text(detail).font(.callout).foregroundStyle(Palette.textSecondary)
            }
            Text("This is today’s top recovery takeaway from HRV and resting heart rate.")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func latest(_ rows: [BodyDaily], _ type: String) -> BodyDaily? {
        rows.filter { $0.type == type }.sorted { $0.date < $1.date }.last
    }

    @ViewBuilder
    private func vitals(_ rows: [BodyDaily]) -> some View {
        let rhr = latest(rows, "resting_heart_rate")
        let hrv = latest(rows, "hrv_sdnn")
        let hr = latest(rows, "heart_rate")
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            if let rhr {
                Button {
                    explain = MetricExplain(title: "Resting heart rate",
                                            body: "Latest resting pulse: \(fmt(rhr.avg)) bpm (range \(fmt(rhr.min))–\(fmt(rhr.max))). Lower resting heart rate usually signals better fitness and recovery.")
                } label: {
                    MetricTile(label: "Resting HR", value: fmt(rhr.avg), unit: "bpm", fraction: 0, tone: .strain, showBar: false)
                }.buttonStyle(.plain)
            }
            if let hrv {
                Button {
                    explain = MetricExplain(title: "Heart rate variability",
                                            body: "Latest HRV: \(fmt(hrv.avg)) ms (range \(fmt(hrv.min))–\(fmt(hrv.max))). Higher HRV generally means better nervous-system recovery.")
                } label: {
                    MetricTile(label: "HRV", value: fmt(hrv.avg), unit: "ms", fraction: 0, tone: .recovery, showBar: false)
                }.buttonStyle(.plain)
            }
            if let hr {
                Button {
                    explain = MetricExplain(title: "Average heart rate",
                                            body: "Today’s average heart rate across the day: \(fmt(hr.avg)) bpm. Useful context for overall demand, not a readiness score by itself.")
                } label: {
                    MetricTile(label: "Avg HR", value: fmt(hr.avg), unit: "bpm", fraction: 0, tone: .sleep, showBar: false)
                }.buttonStyle(.plain)
                Button {
                    explain = MetricExplain(title: "Peak heart rate",
                                            body: "Highest heart rate recorded today: \(fmt(hr.max)) bpm — usually from a hard effort or stress spike.")
                } label: {
                    MetricTile(label: "Peak HR", value: fmt(hr.max), unit: "bpm", fraction: 0, tone: .strain, showBar: false)
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func lineCard(_ title: String, type: String, color: Color, unit: String,
                          goodDirection: GoodDirection, threshold: Double,
                          explain: MetricExplain,
                          rows: [BodyDaily], selection: Binding<Date?>) -> some View {
        let series = rows.filter { $0.type == type }.sorted { $0.date < $1.date }
        let dates = series.map { ChartDate.day($0.date) }
        if !series.isEmpty {
            SectionCard(title: title) {
                Button { self.explain = explain } label: {
                    HStack(spacing: 6) {
                        if let trend = metricTrend(values: series.map { $0.avg }, goodDirection: goodDirection, threshold: threshold) {
                            Text("Averaging \(fmt(trend.recentAvg)) \(unit) — \(trend.phrase).")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.textPrimary)
                                .multilineTextAlignment(.leading)
                        } else if let latest = series.last {
                            Text("Latest \(fmt(latest.avg)) \(unit).")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.textPrimary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "info.circle").foregroundStyle(Palette.textSecondary)
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
                            .foregroundStyle(Palette.textTertiary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .frame(height: 190)
                .chartOverlay { proxy in
                    ChartDayScrubOverlay(proxy: proxy, dates: dates, selection: selection)
                }
                .clipped()

                ScrubDetailBanner(
                    date: selection.wrappedValue,
                    placeholder: "Tap or drag to inspect a day",
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
                        body: "Each day shows your lowest, average, and highest heart rate from Apple Health. The band is min–max; the line is the daily average."
                    )
                } label: {
                    HStack {
                        Text("Lowest · average · highest each day.")
                            .font(.caption).foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Image(systemName: "info.circle").foregroundStyle(Palette.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                Chart(series) { day in
                    AreaMark(
                        x: .value("Date", ChartDate.day(day.date)),
                        yStart: .value("Min", day.min),
                        yEnd: .value("Max", day.max)
                    )
                    .foregroundStyle(Palette.lavender.opacity(0.15))
                    LineMark(x: .value("Date", ChartDate.day(day.date)), y: .value("Avg", day.avg))
                        .foregroundStyle(Palette.lavender)
                        .interpolationMethod(ChartStyle.smooth)
                    if let sel = hrSelection {
                        RuleMark(x: .value("Date", sel))
                            .foregroundStyle(Palette.textTertiary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .frame(height: 200)
                .chartOverlay { proxy in
                    ChartDayScrubOverlay(proxy: proxy, dates: dates, selection: $hrSelection)
                }
                .clipped()

                ScrubDetailBanner(
                    date: hrSelection,
                    placeholder: "Tap or drag to see min · avg · max",
                    lines: hrLines(for: hrSelection, in: series),
                    note: "Min is the calmest reading; max is usually exercise or stress."
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
            "Range \(fmt(hit.min))–\(fmt(hit.max)) \(unit)",
        ]
    }

    private func lineNote(for selection: Date?, in series: [BodyDaily], unit: String, goodDirection: GoodDirection) -> String? {
        guard let selection,
              let idx = series.firstIndex(where: { ChartDate.day($0.date) == selection }),
              idx > 0
        else { return nil }
        let hit = series[idx]
        let prev = series[idx - 1]
        let delta = hit.avg - prev.avg
        let absDelta = abs(delta)
        let nicer = absDelta == absDelta.rounded() ? String(Int(absDelta)) : String(format: "%.1f", absDelta)
        if absDelta < 0.05 { return "About the same as the previous day." }
        if delta > 0 {
            return goodDirection == .higher
                ? "Up \(nicer) \(unit) vs previous day — usually better recovery."
                : "Up \(nicer) \(unit) vs previous day — often a cue to recover more."
        }
        return goodDirection == .higher
            ? "Down \(nicer) \(unit) vs previous day — recovery may be lagging."
            : "Down \(nicer) \(unit) vs previous day — usually better recovery."
    }

    private func hrLines(for selection: Date?, in series: [BodyDaily]) -> [String] {
        guard let selection,
              let hit = series.first(where: { ChartDate.day($0.date) == selection })
        else { return [] }
        return ["Min \(fmt(hit.min)) bpm", "Avg \(fmt(hit.avg)) bpm", "Max \(fmt(hit.max)) bpm"]
    }

    private func load() async {
        guard let client = settings.makeClient() else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            response = try await client.getBody(days: 30)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        pillars = try? await client.getToday().pillars
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
