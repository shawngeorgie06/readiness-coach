import SwiftUI
import UIKit
import Charts

/// History, pushed from the Today head: the selected day's readiness and pillar
/// scores up top, readiness bars coloured by decision (drag to scrub, tap a day
/// for its read-only summary), then what changed, pillar trends, the latest
/// drivers and every day in the range. Reads the store only.
struct TrendsView: View {
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var rangeIndex = 1
    @State private var selectedPointID: String?
    @State private var summary: DaySummary?
    @State private var showsAllDays = false
    @State private var zoneChanges = 0
    @State private var derived = Derived<SeriesStamp, TrendSeries?>()

    private let rangeLabels = ["7d", "30d", "90d"]
    private let rangeDays = [7, 30, 90]
    /// Days listed before "Show all".
    private let collapsedDayCount = 7

    private var days: Int { rangeDays[rangeIndex] }
    private var key: ResourceKey { .history(days: days) }
    private var resource: Resource<ReadinessHistoryResponse> { store.history[days] ?? Resource() }

    var body: some View {
        // Chart dates are midnights in the current zone; reading this redraws
        // after a zone change so the series rebuilds in the new zone.
        let _ = zoneChanges
        let series = self.series
        let points = series?.points ?? []
        let selected = HistoryModel.selected(selectedPointID, in: points)

        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                if let series, let selected {
                    staleNotice
                    head(selected)
                    pillarReadout(selected, prior: HistoryModel.prior(of: selected, in: points))
                    readinessSection { bars(series, selected: selected) }
                    if let prior = HistoryModel.prior(of: selected, in: points) {
                        changeSection(selected, prior: prior)
                    }
                    pillarTrendSection(series, selected: selected)
                    snapshotSection
                    daysSection(points)
                    Text(HistoryModel.decisionGuide)
                        .font(.footnote)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if resource.value == nil, let error = resource.error {
                    readinessSection { EmptyView() }
                    InlineNotice(
                        title: "Couldn't load history",
                        message: error,
                        actionTitle: "Retry",
                        action: retry
                    )
                } else if resource.value == nil {
                    SkeletonHead()
                    readinessSection {
                        SkeletonBlock(height: 160, cornerRadius: 8)
                            .accessibilityLabel("Loading history")
                    }
                } else {
                    readinessSection {
                        ContentUnavailableCompat(
                            title: "No trend yet",
                            message: "Sync a few days of data to see your readiness trend.",
                            systemImage: "chart.bar.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("History")
        .sensoryFeedback(.selection, trigger: selectedPointID)
        .onChange(of: rangeIndex) { _, _ in
            selectedPointID = nil
            showsAllDays = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            zoneChanges += 1
        }
        .navigationDestination(item: $summary) { DaySummaryView(summary: $0) }
        .task(id: store.taskID(key)) { await store.refresh(key) }
        .refreshable { await store.refresh(key, force: true) }
    }

    /// This range's points with their average, span and chart dates, rebuilt
    /// only when the resource changes.
    private var series: TrendSeries? {
        let response = resource.value
        let requestedDays = days
        return derived.series(days: requestedDays, fetchedAt: resource.fetchedAt) { zone in
            Self.points(in: response, requestedDays: requestedDays).map { TrendSeries($0, timeZone: zone) }
        }
    }

    static func points(in response: ReadinessHistoryResponse?, requestedDays: Int) -> [ReadinessPoint]? {
        guard let response, response.days == requestedDays else { return nil }
        return response.data
    }

    private func retry() { Task { await store.refresh(key, force: true) } }

    private func open(_ point: ReadinessPoint) { summary = DaySummary(point) }

    // MARK: Head

    @ViewBuilder
    private var staleNotice: some View {
        if resource.value != nil, resource.error != nil {
            InlineNotice(
                title: "Couldn't refresh",
                message: HistoryModel.staleMessage(fetchedAt: resource.fetchedAt),
                actionTitle: "Retry",
                action: retry
            )
        }
    }

    private func head(_ point: ReadinessPoint) -> some View {
        let day = DaySummary(point)
        return ScoreHead(
            score: point.readiness,
            verdict: point.decision.title,
            verdictColor: day.verdictBand.color,
            meaning: "Readiness · \(day.dayText)",
            note: point.calibrating ? "Calibrating — baseline still forming" : nil,
            noteSystemImage: "hourglass",
            accessibilityLabel: day.accessibilityLabel,
            accessibilityHint: "Opens this day's summary",
            action: { open(point) }
        )
    }

    /// The selected day's three pillar scores, with the change from the day
    /// before when there is one.
    private func pillarReadout(_ point: ReadinessPoint, prior: ReadinessPoint?) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        let day = DaySummary(point)
        let before = prior.map(DaySummary.init)
        return layout {
            ForEach(Pillar.allCases) { pillar in
                let score = day.score(pillar)
                let delta = before.map { score - $0.score(pillar) }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle().fill(pillar.color).frame(width: 7, height: 7)
                        Text(pillar.title)
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(score.rounded()))")
                            .font(Typeface.value)
                            .foregroundStyle(ScoreBand(score: score).numeralColor)
                            .contentTransition(.numericText(value: score))
                        if let delta {
                            Text(HistoryModel.signed(delta))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(HistoryModel.pillarReadoutLabel(pillar, score: score, delta: delta))
            }
        }
    }

    // MARK: Readiness bars

    private func readinessSection<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        let picker = HistoryRangePicker(labels: rangeLabels, days: rangeDays, selection: $rangeIndex)
        return Group {
            if typeSize.isAccessibilitySize {
                OpenSection("Readiness", showsRule: false) {
                    picker
                    content()
                }
            } else {
                OpenSection(title: "Readiness", showsRule: false) {
                    picker.frame(width: 176)
                } content: {
                    content()
                }
            }
        }
    }

    private func bars(_ series: TrendSeries, selected: ReadinessPoint) -> some View {
        let points = series.points
        return VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(Array(zip(points, series.dates)), id: \.0.id) { point, date in
                    BarMark(x: .value("Day", date, unit: .day), y: .value("Readiness", point.readiness))
                        .foregroundStyle(point.decision.band.color.opacity(point.id == selected.id ? 1 : 0.4))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Average", series.average))
                    .foregroundStyle(Palette.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            .chartYScale(domain: 0 ... 100)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .chartLegend(.hidden)
            .frame(height: 160)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    HistoryScrubSurface(
                        onSelect: { select(atX: $0, proxy: proxy, geo: geo, series: series) },
                        onTap: { x in
                            if let point = select(atX: x, proxy: proxy, geo: geo, series: series) { open(point) }
                        }
                    )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Readiness by day, last \(days) days")
            .accessibilityValue(DaySummary(selected).accessibilityLabel)
            .accessibilityHint("Swipe up or down to change the day.")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 1 : (direction == .decrement ? -1 : 0)
                selectedPointID = HistoryModel.step(from: selected.id, by: step, in: points)
            }
            .accessibilityAction(named: "Open day summary") { open(selected) }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Average \(Int(series.average.rounded()))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                Text("· \(HistoryModel.signed(series.deltaVsStart)) pts first to last day")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .monospacedDigit()
            Text("Drag to compare days. Tap a day for its summary.")
                .font(.footnote)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    /// Selects the day under `x` in the overlay and returns it.
    @discardableResult
    private func select(atX x: CGFloat, proxy: ChartProxy, geo: GeometryProxy, series: TrendSeries) -> ReadinessPoint? {
        guard let plotFrame = proxy.plotFrame,
              let raw: Date = proxy.value(atX: x - geo[plotFrame].origin.x),
              let index = HistoryModel.dayIndex(for: raw, in: series.dates)
        else { return nil }
        let point = series.points[index]
        if point.id != selectedPointID {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { selectedPointID = point.id }
        }
        return point
    }

    // MARK: Change from the previous day

    private func changeSection(_ hit: ReadinessPoint, prior: ReadinessPoint) -> some View {
        let changes = HistoryModel.pillarChanges(hit, prior: prior)
        return OpenSection("Change from \(StatusLineModel.formattedDay(prior.date))") {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    if let top = changes.first, let line = HistoryModel.driverLine(top) {
                        Text(line)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    Text(HistoryModel.deltaExplanation(hit.readiness - prior.readiness))
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

                ForEach(changes, id: \.pillar) { change in
                    Hairline()
                    HStack(spacing: 10) {
                        Image(systemName: change.pillar.systemImage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(change.pillar.color)
                            .frame(width: 20)
                        Text(change.pillar.title)
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                        Spacer(minLength: 8)
                        changeBadge(change.delta)
                        Text("\(Int(change.score.rounded()))")
                            .font(Typeface.value)
                            .foregroundStyle(ScoreBand(score: change.score).numeralColor)
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                    .frame(minHeight: Space.target)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(HistoryModel.pillarReadoutLabel(change.pillar, score: change.score, delta: change.delta))
                }
            }
        }
    }

    /// Arrow and signed points; colour never carries the change alone.
    private func changeBadge(_ delta: Double) -> some View {
        let n = Int(delta.rounded())
        let color = n > 0 ? Palette.success : (n < 0 ? Palette.warn : Palette.textTertiary)
        return HStack(spacing: 3) {
            if n != 0 {
                Image(systemName: n > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.caption2.weight(.bold))
            }
            Text(HistoryModel.signed(delta)).font(.footnote.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(color)
    }

    // MARK: Pillar trends

    private func pillarTrendSection(_ series: TrendSeries, selected: ReadinessPoint) -> some View {
        let points = series.points
        let selectedDate = points.firstIndex(where: { $0.id == selected.id }).map { series.dates[$0] }
        return OpenSection("Pillar trends") {
            VStack(alignment: .leading, spacing: 12) {
                Chart {
                    ForEach(Array(zip(points, series.dates)), id: \.0.id) { point, date in
                        line(date, point.recoveryScore, Pillar.recovery)
                        line(date, point.sleepScore, Pillar.sleep)
                        line(date, point.loadScore, Pillar.load)
                    }
                    if let selectedDate {
                        RuleMark(x: .value("Date", selectedDate))
                            .foregroundStyle(Palette.textTertiary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartForegroundStyleScale(domain: Pillar.allCases.map(\.title),
                                           range: Pillar.allCases.map(\.color))
                .chartYScale(domain: 0 ... 100)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 170)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        HistoryScrubSurface { select(atX: $0, proxy: proxy, geo: geo, series: series) }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Pillar scores by day")
                .accessibilityValue(DaySummary(selected).pillarsSpoken)
                .accessibilityHint("Swipe up or down to change the day.")
                .accessibilityAdjustableAction { direction in
                    let step = direction == .increment ? 1 : (direction == .decrement ? -1 : 0)
                    selectedPointID = HistoryModel.step(from: selected.id, by: step, in: points)
                }

                HStack(spacing: 16) {
                    ForEach(Pillar.allCases) { pillar in
                        HStack(spacing: 6) {
                            Circle().fill(pillar.color).frame(width: 7, height: 7)
                            Text(pillar.title)
                                .font(.footnote)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
                .accessibilityHidden(true)

                let weakest = HistoryModel.weakest(selected)
                Text("\(StatusLineModel.formattedDay(selected.date)): \(weakest.pillar.title) was weakest (\(Int(weakest.score.rounded()))/100).")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func line(_ date: Date, _ value: Double, _ pillar: Pillar) -> some ChartContent {
        LineMark(x: .value("Date", date), y: .value("Score", value), series: .value("Pillar", pillar.title))
            .foregroundStyle(by: .value("Pillar", pillar.title))
            .interpolationMethod(ChartStyle.smooth)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    // MARK: Latest drivers

    @ViewBuilder
    private var snapshotSection: some View {
        if let today = store.today.value {
            OpenSection("Latest snapshot · \(StatusLineModel.formattedDay(today.date))") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Pillar.allCases) { pillar in
                        if pillar != Pillar.allCases.first { Hairline() }
                        snapshotRow(pillar, score: pillar.score(in: today.pillars))
                    }
                }
            }
        }
    }

    private func snapshotRow(_ pillar: Pillar, score: PillarScore) -> some View {
        let driver = score.drivers.first
        let tab = AppTab(pillar)
        return Button { tabs.go(to: tab) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: pillar.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(pillar.color)
                    .frame(width: 22)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(pillar.title)
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                        Spacer(minLength: 8)
                        Text("\(Int(score.score.rounded()))")
                            .font(Typeface.value)
                            .foregroundStyle(ScoreBand(score: score.score).numeralColor)
                    }
                    Text(driver?.text ?? "No data yet")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                    if let detail = driver?.detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Text(HistoryModel.meaning(pillar))
                        .font(.footnote)
                        .foregroundStyle(Palette.textTertiary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 4)
            }
            .padding(.vertical, Space.row)
            .frame(minHeight: Space.target)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the \(tab.title) tab")
    }

    // MARK: Days

    private func daysSection(_ points: [ReadinessPoint]) -> some View {
        let newestFirst = Array(points.reversed())
        let shown = showsAllDays ? newestFirst : Array(newestFirst.prefix(collapsedDayCount))
        return OpenSection("Daily scores") {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(shown) { point in
                    if point.id != shown.first?.id { Hairline() }
                    dayRow(point)
                }
                if newestFirst.count > collapsedDayCount {
                    Hairline()
                    Button(showsAllDays ? "Show fewer days" : "Show all \(newestFirst.count) days") {
                        showsAllDays.toggle()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: Space.target, alignment: .leading)
                }
            }
        }
    }

    private func dayRow(_ point: ReadinessPoint) -> some View {
        let day = DaySummary(point)
        return Button { open(point) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(day.dayText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                        Text(point.decision.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(day.verdictBand.color)
                    }
                    Text(day.pillarsShort + (point.calibrating ? " · Calibrating" : ""))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(Int(point.readiness.rounded()))")
                    .font(Typeface.value)
                    .foregroundStyle(Palette.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.vertical, 10)
            .frame(minHeight: Space.target)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel + " " + day.pillarsSpoken)
        .accessibilityHint("Opens this day's summary")
        .accessibilityAddTraits(.isButton)
    }
}

/// The 7/30/90-day range control. Looks like the shared segmented control,
/// but each option is its own 44pt button with a spoken day count and the
/// selected trait, so VoiceOver hears three distinct choices.
private struct HistoryRangePicker: View {
    let labels: [String]
    let days: [Int]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(labels.indices, id: \.self) { index in
                let isSelected = selection == index
                Button { selection = index } label: {
                    Text(labels[index])
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: Space.target)
                        .background(isSelected ? Palette.surfaceHi : .clear,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(HistoryModel.rangeLabel(days: days[index]))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// A History chart's touch surface: a tap, a touch and hold, or a sideways
/// drag picks a day at an overlay x, and a tap can also open it; a vertical
/// drag belongs to the page. UIKit recognizers, because a SwiftUI gesture on
/// scroll content keeps the touch from the enclosing scroll view.
struct HistoryScrubSurface: UIViewRepresentable {
    let onSelect: (CGFloat) -> Void
    /// What a tap does instead of selecting, when set.
    var onTap: ((CGFloat) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect, onTap: onTap) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        context.coordinator.install(on: view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.onTap = onTap
    }

    enum Response { case select, tap }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onSelect: (CGFloat) -> Void
        var onTap: ((CGFloat) -> Void)?
        let tap = UITapGestureRecognizer()
        let hold = UILongPressGestureRecognizer()
        let pan = UIPanGestureRecognizer()

        init(onSelect: @escaping (CGFloat) -> Void, onTap: ((CGFloat) -> Void)?) {
            self.onSelect = onSelect
            self.onTap = onTap
            super.init()
            hold.minimumPressDuration = 0.25
            for recognizer in [tap, hold, pan] as [UIGestureRecognizer] {
                recognizer.addTarget(self, action: #selector(handle(_:)))
                recognizer.delegate = self
            }
        }

        func install(on view: UIView) {
            for recognizer in [tap, hold, pan] as [UIGestureRecognizer] { view.addGestureRecognizer(recognizer) }
        }

        /// A tap lands once it ends; a hold marks its day once, and moving
        /// afterwards is the pan's or the page's; a pan follows the finger.
        func response(to recognizer: UIGestureRecognizer) -> Response? {
            switch (recognizer, recognizer.state) {
            case (tap, .ended): .tap
            case (hold, .began), (pan, .began), (pan, .changed): .select
            default: nil
            }
        }

        @objc func handle(_ recognizer: UIGestureRecognizer) {
            let x = recognizer.location(in: recognizer.view).x
            switch response(to: recognizer) {
            case .tap: (onTap ?? onSelect)(x)
            case .select: onSelect(x)
            case nil: break
            }
        }

        /// The pan starts only for a mostly sideways movement.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard recognizer === pan else { return true }
            let translation = pan.translation(in: pan.view)
            return Self.isSideways(translation == .zero ? pan.velocity(in: pan.view) : translation)
        }

        static func isSideways(_ movement: CGPoint) -> Bool {
            abs(movement.x) > abs(movement.y)
        }

        /// The hold never takes the touch away from the page or the pan.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            (recognizer === hold || other === hold) && recognizer !== tap && other !== tap
        }

        /// A tap waits for the hold to fail, so releasing a hold never opens
        /// the day it marked. A short press fails the hold as it lifts.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            recognizer === tap && other === hold
        }

        /// The page's scroll waits for the pan to decline, so a vertical drag
        /// still scrolls and a sideways one scrubs without moving the page.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            recognizer === pan && other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}

/// Values the History screen derives from one range's points.
struct TrendSeries {
    let points: [ReadinessPoint]
    let dates: [Date]
    let average: Double
    let deltaVsStart: Double

    init(_ points: [ReadinessPoint], timeZone: TimeZone = .current) {
        self.points = points
        dates = points.map { ChartDate.day($0.date, timeZone: timeZone) }
        average = points.isEmpty ? 0 : points.map(\.readiness).reduce(0, +) / Double(points.count)
        deltaVsStart = (points.last?.readiness ?? 0) - (points.first?.readiness ?? 0)
    }
}

/// Pure History logic, kept out of the view so it can be tested. Every number
/// comes from the history response; nothing is fetched or invented here.
enum HistoryModel {
    struct PillarChange: Equatable {
        let pillar: Pillar
        let delta: Double
        let score: Double
    }

    static let decisionGuide =
        "Decision bands: 75+ Push · 50–74 Maintain · under 50 Recover. Sleep = rest quality · Recovery = HRV/RHR · Load = training strain."

    /// The selected point, or the latest when nothing (or a day outside this
    /// range) is selected.
    static func selected(_ id: String?, in points: [ReadinessPoint]) -> ReadinessPoint? {
        if let id, let hit = points.first(where: { $0.id == id }) { return hit }
        return points.last
    }

    static func prior(of point: ReadinessPoint, in points: [ReadinessPoint]) -> ReadinessPoint? {
        guard let index = points.firstIndex(where: { $0.id == point.id }), index > 0 else { return nil }
        return points[index - 1]
    }

    /// Moves the selection one day, clamped to the range.
    static func step(from id: String, by offset: Int, in points: [ReadinessPoint]) -> String? {
        guard let index = points.firstIndex(where: { $0.id == id }) else { return points.last?.id }
        return points[min(max(index + offset, 0), points.count - 1)].id
    }

    /// The day a chart position falls in. Day bars span midnight to midnight,
    /// so the containing day wins over the nearest midnight.
    static func dayIndex(for raw: Date, in dates: [Date], calendar: Calendar = .current) -> Int? {
        let start = calendar.startOfDay(for: raw)
        if let exact = dates.firstIndex(of: start) { return exact }
        guard let nearest = nearestDate(raw, in: dates) else { return nil }
        return dates.firstIndex(of: nearest)
    }

    /// Pillar changes from the prior day, biggest move first.
    static func pillarChanges(_ hit: ReadinessPoint, prior: ReadinessPoint) -> [PillarChange] {
        let day = DaySummary(hit)
        let before = DaySummary(prior)
        return Pillar.allCases
            .map { PillarChange(pillar: $0, delta: day.score($0) - before.score($0), score: day.score($0)) }
            .sorted { abs($0.delta) > abs($1.delta) }
    }

    static func driverLine(_ change: PillarChange) -> String? {
        guard abs(change.delta) >= 0.5 else { return nil }
        let n = Int(change.delta.rounded())
        if n > 0 { return "Biggest lift: \(change.pillar.title) (\(signed(change.delta)))." }
        if n < 0 { return "Biggest drag: \(change.pillar.title) (\(signed(change.delta)))." }
        return "\(change.pillar.title) was unchanged vs the prior day."
    }

    static func deltaExplanation(_ delta: Double) -> String {
        let n = Int(delta.rounded())
        if n == 0 { return "0 pts vs the previous day — readiness held steady." }
        if n > 0 { return "+\(n) pts vs the previous day — overall readiness improved." }
        return "\(n) pts vs the previous day — overall readiness softened."
    }

    /// Spoken name of a range option: "7 days".
    static func rangeLabel(days: Int) -> String { "\(days) days" }

    static func signed(_ delta: Double) -> String {
        let n = Int(delta.rounded())
        return n > 0 ? "+\(n)" : "\(n)"
    }

    static func weakest(_ point: ReadinessPoint) -> (pillar: Pillar, score: Double) {
        let day = DaySummary(point)
        let pillar = Pillar.allCases.min { day.score($0) < day.score($1) } ?? .recovery
        return (pillar, day.score(pillar))
    }

    static func pillarReadoutLabel(_ pillar: Pillar, score: Double, delta: Double?) -> String {
        var label = "\(pillar.title) \(Int(score.rounded())) of 100"
        if let delta {
            let n = Int(delta.rounded())
            label += n == 0 ? ", unchanged from the previous day" : ", \(n > 0 ? "up" : "down") \(abs(n)) from the previous day"
        }
        return label
    }

    static func meaning(_ pillar: Pillar) -> String {
        switch pillar {
        case .recovery: return "Nervous-system recovery from HRV and resting heart rate vs your baseline."
        case .sleep: return "How well you rested — duration and consistency vs your need."
        case .load: return "Recent training stress — how hard you’ve pushed vs your norm."
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func staleMessage(fetchedAt: Date?, now: Date = Date()) -> String {
        guard let fetchedAt else { return "Showing saved data." }
        return "Showing data from \(relative.localizedString(for: fetchedAt, relativeTo: now))."
    }
}

extension DaySummary {
    /// "Recovery 78 · Sleep 70 · Load 64"
    var pillarsShort: String {
        Pillar.allCases.map { "\($0.title) \(Int(score($0).rounded()))" }.joined(separator: " · ")
    }

    var pillarsSpoken: String {
        Pillar.allCases.map { "\($0.title) \(Int(score($0).rounded()))" }.joined(separator: ", ") + "."
    }
}
