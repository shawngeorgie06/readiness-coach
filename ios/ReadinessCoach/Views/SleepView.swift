import SwiftUI
import Charts

/// Sleep tab: the Sleep pillar score, the selected night (duration, bed and
/// wake times, hypnogram, stages) chosen from 7/30/90-night bars, last night
/// against normal, schedule consistency and stages by night.
struct SleepView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var rangeIndex = 1
    @State private var selectedNightID: String?
    @State private var refreshCount = 0
    @State private var derived = Derived<SeriesStamp, SleepSeries>()

    private let ranges = [
        SegmentOption("7D", spoken: "7 nights"),
        SegmentOption("30D", spoken: "30 nights"),
        SegmentOption("90D", spoken: "90 nights"),
    ]
    private let rangeDays = [7, 30, 90]

    private var days: Int { rangeDays[min(max(rangeIndex, 0), rangeDays.count - 1)] }
    private var key: ResourceKey { .sleep(days: days) }
    private var resource: Resource<SleepDetailResponse> { store.sleep[days] ?? Resource() }

    /// True once real content (or an empty/error state) replaces the skeleton.
    private var perfContentReady: Bool { resource.value != nil || resource.error != nil }

    /// Nights that actually have sleep recorded, rebuilt only when the resource changes.
    private var series: SleepSeries? {
        guard let response = resource.value else { return nil }
        return derived.series(days: days, fetchedAt: resource.fetchedAt) { SleepSeries(response, timeZone: $0) }
    }

    var body: some View {
        let loaded = series
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    PillarHead(
                        model: PillarHeadModel(
                            pillar: .sleep,
                            today: store.today.value,
                            currentDay: store.currentDay.date,
                            detail: headDetail(loaded)
                        ),
                        isLoading: store.today.value == nil && store.today.error == nil
                    )
                    ResourceNotice(resource: store.today, noun: "your score", currentDay: store.currentDay.date, errorsOnly: true) {
                        Task { await store.refresh(.today, force: true) }
                    }
                    ResourceNotice(resource: resource, noun: "sleep data", currentDay: store.currentDay.date) {
                        Task { await refresh() }
                    }
                    if let series = loaded, let night = NightSelection.night(selectedNightID, in: series.nights) {
                        nightSection(series, selected: night)
                        timelineSection(night)
                        compared(selectedNight: night.id)
                        schedule(series.nights)
                        stagesByNight(series, selected: night)
                    } else if resource.value == nil, resource.error == nil {
                        rangeOnly
                        PillarSkeleton(name: "sleep history", heroHeight: 160)
                    } else {
                        rangeOnly
                        compared(selectedNight: nil)
                        if resource.value != nil {
                            PillarEmptyState(
                                title: "No nights in the last \(days) days",
                                message: "Sleep appears after your Watch records a night and Today syncs Health. Stages need Apple Watch sleep tracking.",
                                systemImage: "bed.double"
                            )
                        }
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .pillarScreen(title: "Sleep", day: store.currentDay.date)
            .sensoryFeedback(.success, trigger: refreshCount)
            .task(id: store.taskID(key)) { await store.refresh(key) }
            .onAppear { if perfContentReady { PerfSignpost.endTabSwitchIfNeeded(tab: "sleep") } }
            .onChange(of: perfContentReady) { _, ready in
                if ready { PerfSignpost.endTabSwitchIfNeeded(tab: "sleep") }
            }
            .refreshable { await refresh() }
            .onChange(of: rangeIndex) { _, _ in keepSelection() }
            .onChange(of: resource.fetchedAt) { _, _ in keepSelection() }
        }
    }

    private func refresh() async {
        if await store.refresh(key, force: true) { refreshCount += 1 }
    }

    /// Keeps the chosen night while it is still in range; otherwise falls back
    /// to the latest. Waits for the range to load so a pending fetch doesn't
    /// throw the choice away.
    private func keepSelection() {
        guard let nights = series?.nights else { return }
        selectedNightID = NightSelection.keep(selectedNightID, in: nights)
    }

    /// Latest recorded night under the score, dated when it isn't today's.
    private func headDetail(_ series: SleepSeries?) -> String {
        guard let night = series?.nights.last else { return "Duration and stages of your recent nights" }
        var text = DurationFormat.short(night.durationHours)
        if let span = span(night) { text += " · \(span)" }
        if night.date != store.currentDay.date {
            text = "\(ChartDate.day(night.date).formatted(.dateTime.month(.abbreviated).day())): \(text)"
        }
        return text
    }

    private func span(_ night: SleepDay) -> String? {
        guard let bed = PillarTime.clock(night.sleepStart), let wake = PillarTime.clock(night.sleepEnd) else { return nil }
        return "\(bed) – \(wake)"
    }

    private var rangePicker: some View {
        PillarPicker(name: "Range", options: ranges, selection: $rangeIndex)
    }

    /// The range control on its own while a range loads or is empty, so it can
    /// still be changed.
    private var rangeOnly: some View {
        PillarSection(title: "Nights", control: { rangePicker }, content: { EmptyView() })
    }

    // MARK: Selected night and bars

    private func nightSection(_ series: SleepSeries, selected night: SleepDay) -> some View {
        PillarSection(title: "Nights", control: { rangePicker }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ChartDate.day(night.date), format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                Text(DurationFormat.short(night.durationHours))
                    .font(Typeface.numeral(52))
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityLabel(DurationFormat.long(night.durationHours))
                if let span = span(night) {
                    Text("Asleep \(span)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                }
                if let average = NightSelection.averageHours(series.nights) {
                    Text(averageComparison(night.durationHours, average: average, count: series.nights.count))
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            nightBars(series, selected: night)
            if let average = NightSelection.averageHours(series.nights) {
                Text("Average across these \(series.nights.count) nights: \(DurationFormat.short(average)). Tap a bar to pick a night, or touch and hold, then drag, to move through them.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func averageComparison(_ hours: Double, average: Double, count: Int) -> String {
        let minutes = Int(((hours - average) * 60).rounded())
        let range = "the \(count)-night range average (\(DurationFormat.short(average)))"
        if abs(minutes) < 5 { return "About the same as \(range)." }
        let size = DurationFormat.short(Double(abs(minutes)) / 60)
        return "\(size) \(minutes > 0 ? "more" : "less") than \(range)."
    }

    private func nightBars(_ series: SleepSeries, selected night: SleepDay) -> some View {
        let dates = series.points.map(\.date)
        let selectedDate = series.points.first(where: { $0.id == night.id })?.date
        let selection = Binding<Date?>(
            get: { selectedDate },
            set: { date in
                guard let date, let point = series.points.first(where: { $0.date == date }) else { return }
                selectedNightID = point.id
            }
        )
        return Chart(series.points) { point in
            BarMark(
                x: .value("Night", point.date, unit: .day),
                y: .value("Hours", point.night.durationHours)
            )
            .foregroundStyle(Palette.sleep.opacity(point.id == night.id ? 1 : 0.4))
            .cornerRadius(2)
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text("\(Int(hours.rounded()))h").font(.caption2).foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.caption2).foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(height: 150)
        .chartOverlay { proxy in
            ChartDayScrubOverlay(proxy: proxy, dates: dates, selection: selection)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nightly sleep, last \(days) days, \(series.nights.count) nights recorded")
        .accessibilityValue("\(ChartDate.day(night.date).formatted(.dateTime.weekday(.wide).month(.wide).day())), \(DurationFormat.long(night.durationHours))")
        .accessibilityHint("Swipe up or down to choose a night")
        .accessibilityAdjustableAction { direction in
            let offset: Int
            switch direction {
            case .increment: offset = 1
            case .decrement: offset = -1
            @unknown default: return
            }
            selectedNightID = NightSelection.step(from: selectedNightID, by: offset, in: series.nights)
        }
    }

    // MARK: Night timeline

    @ViewBuilder
    private func timelineSection(_ night: SleepDay) -> some View {
        let segments = HypnogramSegment.segments(night.timeline)
        let shares = SleepStageShare.shares(night.stages)
        OpenSection("Stages") {
            if segments.isEmpty && shares.isEmpty {
                Text("No stage data for this night. Stages need Apple Watch sleep tracking.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if !segments.isEmpty { hypnogram(segments) }
                if !shares.isEmpty { stageBreakdown(shares) }
                Text("Restorative (deep + REM): \(DurationFormat.long(night.restorativeHours))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AboutDisclosure(explain: .sleepStages)
        }
    }

    private func hypnogram(_ segments: [HypnogramSegment]) -> some View {
        Chart(segments) { segment in
            RectangleMark(
                xStart: .value("Start", segment.start),
                xEnd: .value("End", segment.end),
                y: .value("Stage", segment.stage.title),
                height: .ratio(0.7)
            )
            .foregroundStyle(segment.stage.color)
            .cornerRadius(2)
        }
        .chartYScale(domain: SleepStage.allCases.map(\.title))
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisValueLabel().font(.caption2).foregroundStyle(Palette.textSecondary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Palette.hairline)
                AxisValueLabel(format: .dateTime.hour()).font(.caption2).foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Night timeline")
        .accessibilityValue(hypnogramSummary(segments))
    }

    private func hypnogramSummary(_ segments: [HypnogramSegment]) -> String {
        guard let first = segments.first, let last = segments.last else { return "" }
        let start = first.start.formatted(date: .omitted, time: .shortened)
        let end = last.end.formatted(date: .omitted, time: .shortened)
        let changes = segments.count
        return "From \(start) to \(end), \(changes) stage blocks. Stage totals follow."
    }

    private func stageBreakdown(_ shares: [SleepStageShare]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let gaps = CGFloat(max(shares.filter { $0.hours > 0 }.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(shares.filter { $0.hours > 0 }) { share in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(share.stage.color)
                            .frame(width: max(2, (geo.size.width - gaps) * share.fraction))
                    }
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            VStack(spacing: 0) {
                ForEach(shares) { share in
                    stageRow(share)
                }
            }
        }
    }

    private func stageRow(_ share: SleepStageShare) -> some View {
        let percent = Int((share.fraction * 100).rounded())
        return HStack(spacing: 10) {
            Circle().fill(share.stage.color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(share.stage.title).foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 8)
            Text(DurationFormat.short(share.hours)).foregroundStyle(Palette.textPrimary)
            Text("\(percent)%")
                .foregroundStyle(Palette.textSecondary)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .font(.subheadline.monospacedDigit())
        .frame(minHeight: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(share.stage.title), \(DurationFormat.long(share.hours)), \(percent) percent of the night")
    }

    // MARK: Compared with normal

    /// The server's comparison under today's score, so it always names that
    /// night, including when another night is selected above.
    @ViewBuilder
    private func compared(selectedNight: String?) -> some View {
        if let today = store.today.value {
            OpenSection("Compared with normal") {
                if let row = MetricComparison.all(from: today.baselines)?.first(where: { $0.metric == .sleepHours }), row.today != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(SleepComparisonSource.caption(
                            scoreDate: today.date,
                            selectedNight: selectedNight,
                            currentDay: store.currentDay.date
                        ))
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        ComparisonRow(comparison: row, showsRule: false)
                    }
                } else if today.baselines == nil {
                    quiet("Your normals aren't available from the server yet.")
                } else {
                    quiet("No sleep recorded for last night yet.")
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

    // MARK: Schedule

    @ViewBuilder
    private func schedule(_ nights: [SleepDay]) -> some View {
        let recent = Array(nights.suffix(7))
        let minutes = recent.compactMap { bedMinutes($0.sleepStart) }.map { ($0 + 720) % 1440 }
        if minutes.count >= 3 {
            let mean = Double(minutes.reduce(0, +)) / Double(minutes.count)
            let variance = minutes.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(minutes.count)
            let std = Int(variance.squareRoot().rounded())
            let label = std <= 30 ? "Very consistent"
                : std <= 60 ? "Fairly consistent"
                : std <= 90 ? "A little irregular" : "Irregular"
            OpenSection("Schedule") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(Typeface.value)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Bedtime varied by ±\(std) min across your last \(minutes.count) recorded nights.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                AboutDisclosure(explain: .sleepConsistency)
            }
        }
    }

    private func bedMinutes(_ iso: String?) -> Int? {
        guard let date = PillarTime.parse(iso) else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return hour * 60 + minute
    }

    // MARK: Stages by night

    @ViewBuilder
    private func stagesByNight(_ series: SleepSeries, selected night: SleepDay) -> some View {
        if series.nights.contains(where: { !SleepStageShare.shares($0.stages).isEmpty }) {
            OpenSection("Stages by night") {
                Chart {
                    ForEach(series.points) { point in
                        ForEach(SleepStage.breakdownOrder) { stage in
                            BarMark(
                                x: .value("Night", point.date, unit: .day),
                                y: .value("Hours", stage.hours(in: point.night.stages))
                            )
                            .foregroundStyle(by: .value("Stage", stage.title))
                            .opacity(point.id == night.id ? 1 : 0.55)
                        }
                    }
                }
                .chartForegroundStyleScale(
                    domain: SleepStage.breakdownOrder.map(\.title),
                    range: SleepStage.breakdownOrder.map(\.color)
                )
                .chartLegend(position: .bottom, alignment: .leading)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Palette.hairline)
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text("\(Int(hours.rounded()))h").font(.caption2).foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2).foregroundStyle(Palette.textTertiary)
                    }
                }
                .frame(height: 200)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Stages by night, last \(days) days")
                .accessibilityValue(stageSummary(night))
            }
        }
    }

    private func stageSummary(_ night: SleepDay) -> String {
        let day = ChartDate.day(night.date).formatted(.dateTime.weekday(.wide).month(.wide).day())
        let parts = SleepStage.breakdownOrder.map { "\($0.title) \(DurationFormat.long($0.hours(in: night.stages)))" }
        return "Selected night \(day): " + parts.joined(separator: ", ")
    }
}

extension MetricExplain {
    static let sleepStages = MetricExplain(
        title: "About sleep stages",
        body: "Each block is a stretch of Deep, REM, Core or Awake through the night, from your Watch sleep analysis. Deep and REM are when your body and brain recover. Core is lighter sleep; Awake is brief wake-ups. Restorative = deep + REM."
    )
    static let sleepConsistency = MetricExplain(
        title: "About consistency",
        body: "Going to bed and waking at similar times helps recovery. This is how much your bedtime varied over your last seven recorded nights."
    )
}

/// Recorded nights for one sleep range, derived once per `SleepDetailResponse`.
struct SleepSeries {
    struct Point: Identifiable {
        let night: SleepDay
        let date: Date
        var id: String { night.id }
    }

    let nights: [SleepDay]
    let points: [Point]
    let maxHours: Double

    init(_ response: SleepDetailResponse, timeZone: TimeZone = .current) {
        nights = response.data.filter { $0.durationHours > 0 }
        points = nights.map { Point(night: $0, date: ChartDate.day($0.date, timeZone: timeZone)) }
        maxHours = max(nights.map(\.durationHours).max() ?? 8, 1)
    }
}
