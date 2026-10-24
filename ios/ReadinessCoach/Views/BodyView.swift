import SwiftUI
import Charts

/// Recovery tab: the Recovery pillar score and its drivers, a 7/30-day HRV or
/// resting-HR trend against the server's 30-day normal, today against normal,
/// the last seven days, and the daily heart-rate range.
struct BodyView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var metric = RecoveryMetric.hrv
    @State private var rangeIndex = 1
    @State private var hrvSelection = ChartDaySelection()
    @State private var rhrSelection = ChartDaySelection()
    @State private var hrSelection = ChartDaySelection()
    @State private var showsHeartRange = false
    @State private var refreshCount = 0
    @State private var derived = Derived<SeriesStamp, BodySeries>()

    private let ranges = [SegmentOption("7D", spoken: "7 days"), SegmentOption("30D", spoken: "30 days")]
    private let rangeDays = [7, 30]

    private var resource: Resource<BodyResponse> { store.body }
    private var days: Int { rangeDays[min(max(rangeIndex, 0), rangeDays.count - 1)] }
    private var today: Date { ChartDate.day(store.currentDay.date) }

    /// True once real content (or an empty/error state) replaces the skeleton.
    private var perfContentReady: Bool { resource.value != nil || resource.error != nil }

    /// Per-metric chart series, rebuilt only when the resource changes.
    private func series(_ response: BodyResponse) -> BodySeries {
        derived.series(fetchedAt: resource.fetchedAt) { BodySeries(response.daily, timeZone: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    PillarHead(
                        model: PillarHeadModel(pillar: .recovery, today: store.today.value, currentDay: store.currentDay.date),
                        isLoading: store.today.value == nil && store.today.error == nil
                    )
                    ResourceNotice(resource: store.today, noun: "your score", currentDay: store.currentDay.date, errorsOnly: true) {
                        Task { await store.refresh(.today, force: true) }
                    }
                    ResourceNotice(resource: resource, noun: "recovery data", currentDay: store.currentDay.date) {
                        Task { await refresh() }
                    }
                    if let response = resource.value, !response.daily.isEmpty {
                        let metrics = series(response)
                        hero(metrics)
                        compared
                        lastWeek(metrics)
                        heartRange(metrics.hr)
                    } else if resource.value == nil, resource.error == nil {
                        PillarSkeleton(name: "recovery trends")
                    } else {
                        compared
                        if resource.value != nil {
                            PillarEmptyState(
                                title: "No recovery readings yet",
                                message: "HRV and resting heart rate appear after your Watch records them and Today syncs Health.",
                                systemImage: "heart"
                            )
                        }
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .pillarScreen(title: "Recovery", day: store.currentDay.date)
            .sensoryFeedback(.success, trigger: refreshCount)
            .task(id: store.taskID(.body)) { await store.refresh(.body) }
            .onAppear { if perfContentReady { PerfSignpost.endTabSwitchIfNeeded(tab: "recovery") } }
            .onChange(of: perfContentReady) { _, ready in
                if ready { PerfSignpost.endTabSwitchIfNeeded(tab: "recovery") }
            }
            .refreshable { await refresh() }
        }
    }

    private func refresh() async {
        if await store.refresh(.body, force: true) { refreshCount += 1 }
    }

    // MARK: Hero

    private func selection(for metric: RecoveryMetric) -> Binding<Date?> {
        metric == .hrv ? $hrvSelection.date : $rhrSelection.date
    }

    @ViewBuilder
    private func hero(_ metrics: BodySeries) -> some View {
        let series = metric.series(in: metrics)
        let points = RecoveryWindow.points(series, days: days, endingOn: today)
        let normal = store.today.value?.baselines.flatMap { metric.vital.baseline(in: $0).baseline30d }
        let binding = selection(for: metric)
        let dates = points.map(\.date)
        let shown = binding.wrappedValue.flatMap { dates.contains($0) ? $0 : nil } ?? dates.last

        OpenSection("Trend") {
            heroControls
            if points.isEmpty {
                Text("No \(metric.title) readings in the last \(days) days.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            } else {
                readout(series, day: shown)
                trendChart(points, normal: normal, shown: shown, selection: binding)
                trendLine(series)
            }
            AboutDisclosure(explain: metric.explain)
        }
    }

    private var heroControls: some View {
        let metricPicker = PillarPicker(
            name: "Metric",
            options: RecoveryMetric.allCases.map { SegmentOption($0.shortTitle, spoken: $0.title) },
            selection: Binding(
                get: { RecoveryMetric.allCases.firstIndex(of: metric) ?? 0 },
                set: { metric = RecoveryMetric.allCases[$0] }
            )
        )
        let rangePicker = PillarPicker(name: "Range", options: ranges, selection: $rangeIndex)
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { metricPicker; rangePicker }
            } else {
                HStack { metricPicker; Spacer(minLength: 8); rangePicker }
            }
        }
    }

    /// The scrubbed (or latest) day, read out above the chart.
    @ViewBuilder
    private func readout(_ series: BodySeries.Metric, day: Date?) -> some View {
        if let day, let row = series.row(on: day) {
            VStack(alignment: .leading, spacing: 4) {
                Text(day, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(pillarNumber(row.avg))
                        .font(Typeface.numeral(44))
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(metric.unit) daily avg")
                        .font(.footnote)
                        .foregroundStyle(Palette.textTertiary)
                }
                Text("Range \(pillarNumber(row.min))–\(pillarNumber(row.max)) \(metric.unit)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
                if let change = dayChange(series, on: day) {
                    Text(change)
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func trendChart(_ points: [BodySeries.Point], normal: Double?, shown: Date?, selection: Binding<Date?>) -> some View {
        let dates = points.map(\.date)
        let domain = RecoveryWindow.domain(points.map(\.avg), normal: normal) ?? 0...1
        let color = Palette.recovery
        return Chart {
            ForEach(points) { day in
                AreaMark(
                    x: .value("Date", day.date),
                    yStart: .value("Floor", domain.lowerBound),
                    yEnd: .value(metric.title, day.avg)
                )
                .interpolationMethod(ChartStyle.smooth)
                .foregroundStyle(LinearGradient(
                    colors: [color.opacity(0.28), color.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                ))
                LineMark(x: .value("Date", day.date), y: .value(metric.title, day.avg))
                    .interpolationMethod(ChartStyle.smooth)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            if let normal {
                RuleMark(y: .value("Normal", normal))
                    .foregroundStyle(Palette.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("normal \(pillarNumber(normal))")
                            .font(.caption2)
                            .foregroundStyle(Palette.textSecondary)
                    }
            }
            if let shown, let point = points.first(where: { $0.date == shown }) {
                RuleMark(x: .value("Selected", shown))
                    .foregroundStyle(Palette.textTertiary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Selected", shown), y: .value(metric.title, point.avg))
                    .foregroundStyle(Palette.textPrimary)
                    .symbolSize(40)
            }
        }
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel().font(.caption2).foregroundStyle(Palette.textTertiary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.caption2).foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(height: 200)
        .chartOverlay { proxy in
            ChartDayScrubOverlay(proxy: proxy, dates: dates, selection: selection)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title), last \(days) days")
        .accessibilityValue(chartValue(points, shown: shown, normal: normal))
        .accessibilityHint("Swipe up or down to move between days")
        .accessibilityAdjustableAction { direction in
            guard let index = shown.flatMap({ dates.firstIndex(of: $0) }) else { return }
            switch direction {
            case .increment: selection.wrappedValue = dates[min(index + 1, dates.count - 1)]
            case .decrement: selection.wrappedValue = dates[max(index - 1, 0)]
            @unknown default: break
            }
        }
    }

    private func chartValue(_ points: [BodySeries.Point], shown: Date?, normal: Double?) -> String {
        var parts: [String] = []
        if let shown, let point = points.first(where: { $0.date == shown }) {
            parts.append("\(shown.formatted(.dateTime.weekday(.wide).month(.wide).day())), \(pillarNumber(point.avg)) \(metric.spokenUnit)")
        }
        if let normal { parts.append("normal \(pillarNumber(normal)) \(metric.spokenUnit)") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func trendLine(_ series: BodySeries.Metric) -> some View {
        if let trend = metricTrend(values: series.averages, goodDirection: metric.goodDirection, threshold: metric.threshold) {
            Text("7-day average \(pillarNumber(trend.recentAvg)) \(metric.unit), \(trend.phrase).")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dayChange(_ series: BodySeries.Metric, on day: Date) -> String? {
        guard let index = series.index(on: day), index > 0 else { return nil }
        let delta = series.rows[index].avg - series.rows[index - 1].avg
        let size = pillarNumber(abs(delta))
        if abs(delta) < 0.05 { return "About the same as the previous reading." }
        let better = (delta > 0) == (metric.goodDirection == .higher)
        let direction = delta > 0 ? "Up" : "Down"
        let reading = better ? "usually better recovery" : "worth watching"
        return "\(direction) \(size) \(metric.unit) on the previous reading, \(reading)."
    }

    // MARK: Compared with normal

    @ViewBuilder
    private var compared: some View {
        if store.today.value != nil {
            OpenSection("Compared with normal") {
                if let all = MetricComparison.all(from: store.today.value?.baselines) {
                    let rows = all.filter { ($0.metric == .hrv || $0.metric == .restingHr) && $0.today != nil }
                    if rows.isEmpty {
                        quiet("No HRV or resting heart rate reading today yet.")
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                ComparisonRow(comparison: row, showsRule: index > 0)
                            }
                        }
                    }
                } else {
                    quiet("Your normals aren't available from the server yet.")
                }
            }
        }
    }

    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Last 7 days

    @ViewBuilder
    private func lastWeek(_ metrics: BodySeries) -> some View {
        let rows = RecoveryDayRow.lastWeek(metrics, endingOn: today)
        if rows.contains(where: { $0.hrv != nil || $0.restingHr != nil }) {
            OpenSection("Last 7 days") {
                VStack(alignment: .leading, spacing: 0) {
                    if !typeSize.isAccessibilitySize {
                        HStack {
                            Text("Daily average").frame(maxWidth: .infinity, alignment: .leading)
                            Text("HRV").frame(width: 72, alignment: .trailing)
                            Text("Resting HR").frame(width: 92, alignment: .trailing)
                        }
                        .font(.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.bottom, 8)
                        .accessibilityHidden(true)
                    }
                    ForEach(rows) { row in
                        Hairline()
                        dayRow(row)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ row: RecoveryDayRow) -> some View {
        let dayText = row.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let hrv = row.hrv.map { "\(pillarNumber($0)) ms" } ?? "—"
        let rhr = row.restingHr.map { "\(pillarNumber($0)) bpm" } ?? "—"
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayText).foregroundStyle(Palette.textPrimary)
                    Text("HRV \(hrv)").foregroundStyle(Palette.textSecondary)
                    Text("Resting HR \(rhr)").foregroundStyle(Palette.textSecondary)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
            } else {
                HStack {
                    Text(dayText).foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(hrv).frame(width: 72, alignment: .trailing)
                    Text(rhr).frame(width: 92, alignment: .trailing)
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .frame(minHeight: Space.target)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayAccessibility(row))
    }

    private func dayAccessibility(_ row: RecoveryDayRow) -> String {
        let day = row.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let hrv = row.hrv.map { "HRV \(pillarNumber($0)) milliseconds" } ?? "No HRV reading"
        let rhr = row.restingHr.map { "resting heart rate \(pillarNumber($0)) beats per minute" } ?? "no resting heart rate reading"
        return "\(day). \(hrv), \(rhr)."
    }

    // MARK: Heart-rate range

    @ViewBuilder
    private func heartRange(_ series: BodySeries.Metric) -> some View {
        let points = RecoveryWindow.points(series, days: days, endingOn: today)
        if !series.rows.isEmpty {
            OpenSection(title: "Heart rate · daily range", trailing: {
                Button {
                    showsHeartRange.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(showsHeartRange ? 180 : 0))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(minWidth: Space.target, minHeight: Space.target)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Heart rate daily range")
                .accessibilityValue(showsHeartRange ? "Expanded" : "Collapsed")
            }) {
                if showsHeartRange {
                    heartRangeContent(series, points: points)
                } else {
                    Text("Lowest, average and highest heart rate each day.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func heartRangeContent(_ series: BodySeries.Metric, points: [BodySeries.Point]) -> some View {
        let dates = points.map(\.date)
        let shown = hrSelection.date.flatMap { dates.contains($0) ? $0 : nil } ?? dates.last
        if points.isEmpty {
            quiet("No heart-rate readings in the last \(days) days.")
        } else {
            if let shown, let row = series.row(on: shown) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(shown, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                    Text("Min \(pillarNumber(row.min)) · Avg \(pillarNumber(row.avg)) · Max \(pillarNumber(row.max)) bpm")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            Chart {
                ForEach(points) { day in
                    AreaMark(x: .value("Date", day.date), yStart: .value("Min", day.min), yEnd: .value("Max", day.max))
                        .foregroundStyle(Palette.recovery.opacity(0.18))
                    LineMark(x: .value("Date", day.date), y: .value("Average", day.avg))
                        .foregroundStyle(Palette.recovery)
                        .interpolationMethod(ChartStyle.smooth)
                }
                if let shown {
                    RuleMark(x: .value("Selected", shown))
                        .foregroundStyle(Palette.textTertiary.opacity(0.6))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Palette.hairline)
                    AxisValueLabel().font(.caption2).foregroundStyle(Palette.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2).foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(height: 180)
            .chartOverlay { proxy in
                ChartDayScrubOverlay(proxy: proxy, dates: dates, selection: $hrSelection.date)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Heart rate daily range, last \(days) days")
            .accessibilityValue(shown.flatMap { day in series.row(on: day).map { row in
                "\(day.formatted(.dateTime.weekday(.wide).month(.wide).day())), minimum \(pillarNumber(row.min)), average \(pillarNumber(row.avg)), maximum \(pillarNumber(row.max)) beats per minute"
            } } ?? "")
            .accessibilityAdjustableAction { direction in
                guard let index = shown.flatMap({ dates.firstIndex(of: $0) }) else { return }
                switch direction {
                case .increment: hrSelection.date = dates[min(index + 1, dates.count - 1)]
                case .decrement: hrSelection.date = dates[max(index - 1, 0)]
                @unknown default: break
                }
            }
            Text(MetricExplain.heartRange.body)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The two Recovery trend metrics.
enum RecoveryMetric: CaseIterable {
    case hrv, restingHr

    var title: String { self == .hrv ? "HRV" : "Resting heart rate" }
    var shortTitle: String { self == .hrv ? "HRV" : "Resting HR" }
    var unit: String { self == .hrv ? "ms" : "bpm" }
    var spokenUnit: String { self == .hrv ? "milliseconds" : "beats per minute" }
    var vital: VitalMetric { self == .hrv ? .hrv : .restingHr }
    var goodDirection: GoodDirection { self == .hrv ? .higher : .lower }
    var threshold: Double { self == .hrv ? 2 : 1.5 }
    var explain: MetricExplain { self == .hrv ? .hrv : .restingHr }

    func series(in metrics: BodySeries) -> BodySeries.Metric {
        self == .hrv ? metrics.hrv : metrics.rhr
    }
}

extension MetricExplain {
    static let hrv = MetricExplain(
        title: "About HRV",
        body: "HRV is the tiny variation between heartbeats (SDNN, ms). Higher and rising usually means your nervous system is recovered. We compare today’s average to your recent baseline."
    )
    static let restingHr = MetricExplain(
        title: "About resting heart rate",
        body: "Your pulse at rest. Lower usually means better fitness and recovery. An unexpected rise — especially with low HRV — is a cue to ease off."
    )
    static let heartRange = MetricExplain(
        title: "About the daily range",
        body: "Each day shows your lowest, average, and highest heart rate from Apple Health. The band is min–max; the line is the daily average. Min is the calmest reading; max is usually exercise or stress."
    )
}

/// Chart series for each Body metric, oldest first, derived once per `BodyResponse`.
struct BodySeries {
    struct Point: Identifiable {
        let id: String
        let date: Date
        let min: Double
        let avg: Double
        let max: Double
    }

    struct Metric {
        let rows: [BodyDaily]
        let dates: [Date]
        let averages: [Double]
        let points: [Point]

        init(_ daily: [BodyDaily], type: String, timeZone: TimeZone = .current) {
            rows = daily.filter { $0.type == type }.sorted { $0.date < $1.date }
            dates = rows.map { ChartDate.day($0.date, timeZone: timeZone) }
            averages = rows.map(\.avg)
            points = zip(rows, dates).map { Point(id: $0.id, date: $1, min: $0.min, avg: $0.avg, max: $0.max) }
        }

        func index(on day: Date?) -> Int? {
            guard let day else { return nil }
            return dates.firstIndex(of: day)
        }

        func row(on day: Date?) -> BodyDaily? {
            index(on: day).map { rows[$0] }
        }
    }

    let hrv: Metric
    let rhr: Metric
    let hr: Metric

    init(_ daily: [BodyDaily], timeZone: TimeZone = .current) {
        hrv = Metric(daily, type: "hrv_sdnn", timeZone: timeZone)
        rhr = Metric(daily, type: "resting_heart_rate", timeZone: timeZone)
        hr = Metric(daily, type: "heart_rate", timeZone: timeZone)
    }
}
