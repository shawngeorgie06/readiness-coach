import SwiftUI
import Charts

/// Train tab: the Load pillar score with this week's strain against the week
/// before, seven daily strain bars, and workouts grouped by day.
struct TrainView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var filterIndex = 0
    @State private var selectedWorkout: WorkoutDTO?
    @State private var refreshCount = 0
    @State private var derived = Derived<TrainStamp, TrainSeries>()

    private static let filters = ["All", "Run", "Strength", "Recovery"]

    private var resource: Resource<TrainResponse> { store.train }
    private var filter: String { Self.filters[min(max(filterIndex, 0), Self.filters.count - 1)] }

    /// True once real content (or an empty/error state) replaces the skeleton.
    private var perfContentReady: Bool { resource.value != nil || resource.error != nil }

    /// Week totals, daily bars and day groups, rebuilt only when the resource,
    /// the zone or the day changes.
    private func series(_ response: TrainResponse) -> TrainSeries {
        let zone = TimeZone.current
        let day = store.currentDay.date
        return derived.get(TrainStamp(fetchedAt: resource.fetchedAt, timeZone: zone, day: day)) {
            var calendar = Calendar.current
            calendar.timeZone = zone
            return TrainSeries(response.data, now: ChartDate.day(day, timeZone: zone), calendar: calendar)
        }
    }

    var body: some View {
        let loaded = resource.value.map(series)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    PillarHead(
                        model: PillarHeadModel(
                            pillar: .load,
                            today: store.today.value,
                            currentDay: store.currentDay.date,
                            detail: loaded.map(headDetail)
                        ),
                        isLoading: store.today.value == nil && store.today.error == nil
                    )
                    ResourceNotice(resource: store.today, noun: "your score", currentDay: store.currentDay.date, errorsOnly: true) {
                        Task { await store.refresh(.today, force: true) }
                    }
                    ResourceNotice(resource: resource, noun: "training data", currentDay: store.currentDay.date) {
                        Task { await refresh() }
                    }
                    if let series = loaded, !series.sorted.isEmpty {
                        week(series)
                        compared
                        workouts(series)
                    } else if resource.value == nil, resource.error == nil {
                        PillarSkeleton(name: "training", heroHeight: 140)
                    } else {
                        compared
                        if resource.value != nil {
                            PillarEmptyState(
                                title: "No workouts in the last four weeks",
                                message: "Workouts appear after you record them on your Watch or iPhone and Today syncs Health.",
                                systemImage: "figure.run"
                            )
                        }
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .pillarScreen(title: "Train", day: store.currentDay.date)
            .sensoryFeedback(.success, trigger: refreshCount)
            .sheet(item: $selectedWorkout) { WorkoutDetailSheet(workout: $0) }
            .task(id: store.taskID(.train)) { await store.refresh(.train) }
            .onAppear { if perfContentReady { PerfSignpost.endTabSwitchIfNeeded(tab: "train") } }
            .onChange(of: perfContentReady) { _, ready in
                if ready { PerfSignpost.endTabSwitchIfNeeded(tab: "train") }
            }
            .refreshable { await refresh() }
        }
    }

    private func refresh() async {
        if await store.refresh(.train, force: true) { refreshCount += 1 }
    }

    private func headDetail(_ series: TrainSeries) -> String {
        "\(pillarNumber(series.weekStrain)) strain in the last 7 days · \(pillarNumber(series.priorWeekStrain)) the 7 before"
    }

    // MARK: Week

    private func week(_ series: TrainSeries) -> some View {
        OpenSection("Last 7 days") {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(series.days.reversed()) { day in
                        Hairline()
                        Text(dayLine(day))
                            .font(.subheadline)
                            .foregroundStyle(day.isRest ? Palette.textSecondary : Palette.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: Space.target, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                weekChart(series.days)
            }
            Text(weekSummary(series))
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            AboutDisclosure(explain: .strain)
        }
    }

    private func weekChart(_ days: [TrainDay]) -> some View {
        let peak = days.map(\.strain).max() ?? 0
        let stub = max(peak * 0.04, 0.2)
        return Chart(days) { day in
            BarMark(
                x: .value("Day", day.date, unit: .day),
                y: .value("Strain", day.isRest ? stub : day.strain),
                width: .ratio(0.55)
            )
            .foregroundStyle(day.isRest ? Palette.track : Palette.load)
            .cornerRadius(3)
            .annotation(position: .top, spacing: 4) {
                Text(day.isRest ? "Rest" : pillarNumber(day.strain))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(day.isRest ? Palette.textTertiary : Palette.textSecondary)
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...max(peak * 1.2, 1))
        .chartXAxis {
            AxisMarks(values: days.map(\.date)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    .font(.caption2)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(height: 150)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily strain, last 7 days")
        .accessibilityChartDescriptor(TrainWeekDescriptor(days: days, line: dayLine))
    }

    private func dayLine(_ day: TrainDay) -> String {
        let date = day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        guard !day.isRest else { return "\(date): rest day" }
        let sessions = "\(day.sessions) session\(day.sessions == 1 ? "" : "s")"
        return "\(date): \(pillarNumber(day.strain)) strain, \(DurationFormat.short(day.minutes / 60)), \(sessions)"
    }

    private func weekSummary(_ series: TrainSeries) -> String {
        let count = series.week.count
        var parts = ["\(count) session\(count == 1 ? "" : "s")", DurationFormat.short(series.weekMinutes / 60)]
        if let hardest = series.weekHardest {
            parts.append("hardest \(WorkoutSport.title(forKey: hardest.sport)), \(pillarNumber(hardest.strain))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Compared with normal

    @ViewBuilder
    private var compared: some View {
        if let today = store.today.value {
            OpenSection("Compared with normal") {
                if let row = MetricComparison.all(from: today.baselines)?.first(where: { $0.metric == .load7d }), row.today != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(TrainLoadCopy.dailyAverageNote(scoreDate: today.date))
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ComparisonRow(comparison: row, showsRule: false)
                    }
                } else {
                    Text(today.baselines == nil ? "Your normals aren't available from the server yet." : "No 7-day load yet.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Workouts

    private func workouts(_ series: TrainSeries) -> some View {
        let groups = filter == "All"
            ? series.groups
            : WorkoutDayGroup.filter(series.groups) { WorkoutSport.filterCategory(forKey: $0.sport) == filter }
        return PillarSection(
            title: "Workouts",
            control: {
                PillarPicker(
                    name: "Filter",
                    options: Self.filters.map { SegmentOption($0, spoken: $0 == "All" ? "All workouts" : $0) },
                    selection: $filterIndex
                )
            }
        ) {
            if groups.isEmpty {
                Text("No \(filter.lowercased()) workouts in the last four weeks.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.textSecondary)
                                .padding(.bottom, 6)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.workouts) { workout in
                                Hairline()
                                row(workout)
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(_ workout: WorkoutDTO) -> some View {
        Button {
            selectedWorkout = workout
        } label: {
            HStack(spacing: 12) {
                SportBadge(sport: workout.sport, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(WorkoutSport.title(forKey: workout.sport))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(rowSubtitle(workout))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                    if typeSize.isAccessibilitySize {
                        Text("\(pillarNumber(workout.strain)) strain")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                    }
                }
                Spacer(minLength: 8)
                if !typeSize.isAccessibilitySize {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(pillarNumber(workout.strain))
                            .font(Typeface.numeral(24))
                            .foregroundStyle(Palette.textPrimary)
                        Text("strain")
                            .font(.caption2)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibility(workout))
        .accessibilityHint("Opens workout details")
        .accessibilityAddTraits(.isButton)
    }

    private func rowSubtitle(_ workout: WorkoutDTO) -> String {
        var parts: [String] = []
        if let start = PillarTime.parse(workout.startAt) {
            parts.append(start.formatted(date: .omitted, time: .shortened))
        }
        parts.append(DurationFormat.short(workout.durationMin / 60))
        if let hr = workout.avgHrBpm { parts.append("\(Int(hr.rounded())) bpm avg") }
        return parts.joined(separator: " · ")
    }

    private func rowAccessibility(_ workout: WorkoutDTO) -> String {
        var parts = [WorkoutSport.title(forKey: workout.sport)]
        if let start = PillarTime.parse(workout.startAt) {
            parts.append(start.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))
        }
        parts.append(DurationFormat.long(workout.durationMin / 60))
        if let hr = workout.avgHrBpm { parts.append("average heart rate \(Int(hr.rounded())) beats per minute") }
        parts.append("strain \(pillarNumber(workout.strain)) of 21")
        return parts.joined(separator: ", ")
    }
}

/// VoiceOver audio-graph description of the week bars: each day by name.
private struct TrainWeekDescriptor: AXChartDescriptorRepresentable {
    let days: [TrainDay]
    let line: (TrainDay) -> String

    func makeChartDescriptor() -> AXChartDescriptor {
        let names = days.map { $0.date.formatted(.dateTime.weekday(.wide)) }
        let peak = days.map(\.strain).max() ?? 0
        let x = AXCategoricalDataAxisDescriptor(title: "Day", categoryOrder: names)
        let y = AXNumericDataAxisDescriptor(
            title: "Strain",
            range: 0...max(peak, 1),
            gridlinePositions: []
        ) { pillarNumber($0) }
        let points = zip(days, names).map { day, name in
            AXDataPoint(x: name, y: day.strain, label: line(day))
        }
        return AXChartDescriptor(
            title: "Daily strain, last 7 days",
            summary: nil,
            xAxis: x,
            yAxis: y,
            additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: "Strain", isContinuous: false, dataPoints: points)]
        )
    }
}

/// Identifies one build of the Train series: the fetch, the zone and the day
/// that "last 7 days" counts back from.
struct TrainStamp: Equatable {
    let fetchedAt: Date?
    let timeZone: TimeZone
    let day: String
}

/// Values the Train tab derives from one `TrainResponse`.
struct TrainSeries {
    /// Newest first.
    let sorted: [WorkoutDTO]
    /// Workouts in the seven calendar days ending on `now`'s day.
    let week: [WorkoutDTO]
    let weekStrain: Double
    let weekMinutes: Double
    let weekHardest: WorkoutDTO?
    /// Total strain in the seven calendar days before `week`.
    let priorWeekStrain: Double
    /// Seven days, oldest first; days without workouts are rest days.
    let days: [TrainDay]
    let groups: [WorkoutDayGroup]

    init(_ workouts: [WorkoutDTO], now: Date = Date(), calendar: Calendar = .current) {
        let dated = workouts.map { (workout: $0, start: PillarTime.parse($0.startAt)) }
        sorted = dated
            .sorted { ($0.start ?? .distantPast, $0.workout.startAt) > ($1.start ?? .distantPast, $1.workout.startAt) }
            .map(\.workout)

        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let priorStart = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now

        func within(_ start: Date?, _ from: Date, _ to: Date) -> Bool {
            guard let start else { return false }
            return start >= from && start < to
        }

        week = sorted.filter { within(PillarTime.parse($0.startAt), weekStart, tomorrow) }
        weekStrain = week.reduce(0) { $0 + $1.strain }
        weekMinutes = week.reduce(0) { $0 + $1.durationMin }
        weekHardest = week.max { $0.strain < $1.strain }
        priorWeekStrain = sorted
            .filter { within(PillarTime.parse($0.startAt), priorStart, weekStart) }
            .reduce(0) { $0 + $1.strain }

        let weekByDay = Dictionary(grouping: week) { workout in
            PillarTime.parse(workout.startAt).map { calendar.startOfDay(for: $0) } ?? today
        }
        days = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let sessions = weekByDay[day] ?? []
            return TrainDay(
                date: day,
                strain: sessions.reduce(0) { $0 + $1.strain },
                minutes: sessions.reduce(0) { $0 + $1.durationMin },
                sessions: sessions.count
            )
        }
        groups = WorkoutDayGroup.groups(sorted, now: now, calendar: calendar)
    }
}

/// Circular sport icon. The Load colour is used only for the glyph and tint,
/// never for text.
struct SportBadge: View {
    let sport: String
    var size: CGFloat = 36

    private var tint: Color {
        switch WorkoutSport.filterCategory(forKey: sport) {
        case "Recovery": return Palette.recovery
        case "Other": return Palette.textSecondary
        default: return Palette.load
        }
    }

    var body: some View {
        Image(systemName: WorkoutSport.symbolName(forKey: sport))
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }
}

struct WorkoutDetailSheet: View {
    let workout: WorkoutDTO
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var strainSize: CGFloat = 56

    var body: some View {
        SheetScaffold(
            title: WorkoutSport.title(forKey: workout.sport),
            context: "Workout",
            systemImage: WorkoutSport.symbolName(forKey: workout.sport),
            tone: .load
        ) {
            header
            effort
            session
            heartRate
            zones
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(whenText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
            Text(WorkoutSport.detailBlurb(forKey: workout.sport))
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var effort: some View {
        OpenSection("Effort") {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
            layout {
                Text(String(format: "%.1f", workout.strain))
                    .font(Typeface.numeral(strainSize))
                    .foregroundStyle(Palette.textPrimary)
                Text("/ 21 strain")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Strain \(String(format: "%.1f", workout.strain)) out of 21")
            AboutDisclosure(explain: .strain)
        }
    }

    private var session: some View {
        OpenSection("Session") {
            VStack(spacing: 0) {
                detailRow("When", whenText, first: true)
                detailRow("Duration", "\(Int(workout.durationMin.rounded())) min")
                if let calories = workout.calories {
                    detailRow("Calories", "\(Int(calories.rounded())) kcal")
                }
            }
        }
    }

    private var heartRate: some View {
        OpenSection("Heart rate") {
            if workout.avgHrBpm == nil && workout.maxHrBpm == nil {
                Text("No heart rate recorded for this workout.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                VStack(spacing: 0) {
                    if let avg = workout.avgHrBpm {
                        detailRow("Avg heart rate", "\(Int(avg.rounded())) bpm", first: true)
                    }
                    if let max = workout.maxHrBpm {
                        detailRow("Max heart rate", "\(Int(max.rounded())) bpm", first: workout.avgHrBpm == nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var zones: some View {
        let segments = HRZoneSegment.segments(workout.hrZonesMin)
        OpenSection("Heart-rate zones") {
            if segments.isEmpty {
                Text("No heart-rate zone data for this workout.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                GeometryReader { geo in
                    let gaps = CGFloat(segments.count - 1) * 2
                    HStack(spacing: 2) {
                        ForEach(segments) { zone in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(zoneColor(zone.index))
                                .frame(width: max(2, (geo.size.width - gaps) * zone.fraction))
                        }
                    }
                }
                .frame(height: 10)
                .accessibilityHidden(true)
                VStack(spacing: 0) {
                    ForEach(segments) { zone in
                        let percent = Int((zone.fraction * 100).rounded())
                        Group {
                            if typeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(zone.label).foregroundStyle(Palette.textPrimary)
                                    Text("\(Int(zone.minutes.rounded())) min · \(percent)%")
                                        .foregroundStyle(Palette.textSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                            } else {
                                HStack(spacing: 10) {
                                    Circle().fill(zoneColor(zone.index)).frame(width: 8, height: 8).accessibilityHidden(true)
                                    Text(zone.label).foregroundStyle(Palette.textPrimary)
                                    Spacer(minLength: 8)
                                    Text("\(Int(zone.minutes.rounded())) min").foregroundStyle(Palette.textPrimary)
                                    Text("\(percent)%")
                                        .foregroundStyle(Palette.textSecondary)
                                        .frame(minWidth: 40, alignment: .trailing)
                                }
                            }
                        }
                        .font(.subheadline.monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: Space.target)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Zone \(zone.index + 1), \(zone.name): \(Int(zone.minutes.rounded())) minutes, \(percent) percent")
                    }
                }
                Text(HRZoneSegment.estimateNote)
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One hue, rising opacity: zone order reads without relying on colour
    /// because every zone is also named.
    private func zoneColor(_ index: Int) -> Color {
        let ramp = [0.3, 0.45, 0.6, 0.8, 1.0]
        return Palette.load.opacity(ramp[min(max(index, 0), ramp.count - 1)])
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String, first: Bool = false) -> some View {
        if !first { Hairline() }
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).foregroundStyle(Palette.textSecondary)
                    Text(value).foregroundStyle(Palette.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                HStack {
                    Text(label).foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 12)
                    Text(value)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
                .frame(minHeight: Space.target)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private var whenText: String {
        guard let start = PillarTime.parse(workout.startAt) else { return workout.startAt }
        return start.formatted(.dateTime.weekday(.wide).month().day().hour().minute())
    }
}

extension MetricExplain {
    static let strain = MetricExplain(title: "About strain", body: StrainExplain.scaleBlurb)
}
