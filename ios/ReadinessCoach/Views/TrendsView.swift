import SwiftUI
import Charts

/// Insights tab — Aether prototype: range selector, readiness trend bars (tappable),
/// pillar trends. Sleep detail lives on the Sleep tab.
struct TrendsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var tabs: TabRouter
    @State private var response: ReadinessHistoryResponse?
    @State private var error: String?
    @State private var isLoading = false
    @State private var rangeIndex = 1
    @State private var selectedPointID: String?
    @State private var pillarSelection: Date?
    @State private var pillars: Pillars?

    private let rangeLabels = ["7d", "30d", "90d"]
    private let rangeDays = [7, 30, 90]

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    header
                    SegmentedRange(rangeLabels, selection: $rangeIndex)
                    if let points, !points.isEmpty {
                        trendCard(points)
                        insightCards()
                        pillarsCard(points)
                    } else if isLoading {
                        ProgressView().padding(.top, 60)
                    } else {
                        ContentUnavailableCompat(
                            title: "No trend yet",
                            message: "Sync a few days of data to see your readiness trend.",
                            systemImage: "chart.bar.fill"
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
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: rangeIndex) { _, _ in
                selectedPointID = nil
                pillarSelection = nil
                Task { await load() }
            }
        }
    }

    private var points: [ReadinessPoint]? { response?.data }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Patterns")
                Text("Insights").font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
        }
    }

    private func trendCard(_ points: [ReadinessPoint]) -> some View {
        let avg = points.map(\.readiness).reduce(0, +) / Double(points.count)
        let selected = points.first(where: { $0.id == selectedPointID }) ?? points.last
        let deltaVsStart = (points.last?.readiness ?? 0) - (points.first?.readiness ?? 0)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Readiness trend")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(avg.rounded()))")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.textPrimary)
                        Text("avg").font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer()
                Pill(String(format: "%+d pts span", Int(deltaVsStart.rounded())),
                     tone: deltaVsStart >= 0 ? .good : .warn)
            }

            Text("Tap any bar to inspect that day.")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)

            trendBars(points)

            if let selected {
                dayDetail(selected, in: points)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .onAppear {
            if selectedPointID == nil {
                selectedPointID = points.last?.id
            }
        }
    }

    private func trendBars(_ points: [ReadinessPoint]) -> some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: max(2, 4 - Double(points.count) / 30)) {
                ForEach(points) { p in
                    let isSelected = p.id == (selectedPointID ?? points.last?.id)
                    Button {
                        selectedPointID = p.id
                    } label: {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(isSelected ? Palette.accent : Palette.accent.opacity(0.45))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(6, geo.size.height * (p.readiness / 100)))
                            .shadow(color: isSelected ? Palette.accent.opacity(0.5) : .clear, radius: 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(ChartDate.day(p.date).formatted(.dateTime.month().day())), readiness \(Int(p.readiness.rounded()))")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 130)
    }

    private func dayDetail(_ hit: ReadinessPoint, in points: [ReadinessPoint]) -> some View {
        let day = ChartDate.day(hit.date)
        let prior = priorPoint(for: hit, in: points)
        let delta = prior.map { hit.readiness - $0.readiness }

        return VStack(alignment: .leading, spacing: 8) {
            Text(day, format: .dateTime.weekday(.wide).month(.wide).day().year())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("Readiness \(Int(hit.readiness.rounded())) · \(hit.decision.title)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
            if let delta {
                Text(deltaExplanation(delta))
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let prior {
                pillarDeltaBlock(hit: hit, prior: prior)
            }
            Text("Sleep \(Int(hit.sleepScore.rounded())) · Recovery \(Int(hit.recoveryScore.rounded())) · Load \(Int(hit.loadScore.rounded()))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Palette.textSecondary)
            Text(decisionGuide)
                .font(.caption2)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var decisionGuide: String {
        "Decision bands: 75+ Push · 50–74 Maintain · under 50 Recover. Sleep = rest quality · Recovery = HRV/RHR · Load = training strain."
    }

    private func pillarDeltaBlock(hit: ReadinessPoint, prior: ReadinessPoint) -> some View {
        let rows: [(String, Double, Double)] = [
            ("Sleep", hit.sleepScore - prior.sleepScore, hit.sleepScore),
            ("Recovery", hit.recoveryScore - prior.recoveryScore, hit.recoveryScore),
            ("Load", hit.loadScore - prior.loadScore, hit.loadScore),
        ]
        let ranked = rows.sorted { abs($0.1) > abs($1.1) }
        let top = ranked.first
        return VStack(alignment: .leading, spacing: 4) {
            if let top, abs(top.1) >= 0.5 {
                Text(pillarDriverLine(name: top.0, delta: top.1))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(ranked, id: \.0) { row in
                HStack {
                    Text(row.0)
                        .font(.caption2)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text(signedPts(row.1))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(row.1 >= 0 ? Palette.mint : Palette.warn)
                    Text("→ \(Int(row.2.rounded()))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .padding(8)
        .background(Palette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func pillarDriverLine(name: String, delta: Double) -> String {
        let n = Int(delta.rounded())
        if n > 0 { return "Biggest lift: \(name) (\(signedPts(delta)))." }
        if n < 0 { return "Biggest drag: \(name) (\(signedPts(delta)))." }
        return "\(name) was unchanged vs the prior day."
    }

    private func signedPts(_ delta: Double) -> String {
        let n = Int(delta.rounded())
        if n > 0 { return "+\(n)" }
        return "\(n)"
    }

    private func priorPoint(for hit: ReadinessPoint, in points: [ReadinessPoint]) -> ReadinessPoint? {
        guard let idx = points.firstIndex(where: { $0.id == hit.id }), idx > 0 else { return nil }
        return points[idx - 1]
    }

    private func deltaExplanation(_ delta: Double) -> String {
        let n = Int(delta.rounded())
        if n == 0 {
            return "0 pts vs the previous day — readiness held steady."
        }
        if n > 0 {
            return "+\(n) pts vs the previous day — overall readiness improved."
        }
        return "\(n) pts vs the previous day — overall readiness softened."
    }

    @ViewBuilder
    private func insightCards() -> some View {
        if let pillars {
            Button { tabs.go(to: .sleep) } label: {
                insightCard("Sleep", .sleep, pillars.sleep,
                            meaning: "How well you rested — duration and consistency vs your need. Tap to open the Sleep tab.")
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the Sleep tab")

            insightCard("Recovery", .good, pillars.recovery,
                        meaning: "Nervous-system recovery from HRV and resting heart rate vs your baseline.")
            insightCard("Load", .accent, pillars.load,
                        meaning: "Recent training stress — how hard you’ve pushed vs your norm.")
        }
    }

    private func insightCard(_ name: String, _ tone: Pill.Tone, _ pillar: PillarScore, meaning: String) -> some View {
        let driver = pillar.drivers.first
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Pill(name, tone: tone)
                Spacer()
                HStack(spacing: 6) {
                    Text("Score \(Int(pillar.score.rounded()))")
                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(Palette.textTertiary)
                    if name == "Sleep" {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                    }
                }
            }
            Text(driver?.text ?? "No data yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
            Text(meaning)
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = driver?.detail {
                Text(detail).font(.callout).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func pillarsCard(_ points: [ReadinessPoint]) -> some View {
        let dates = points.map { ChartDate.day($0.date) }
        return VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Pillar scores")
            Text("Drag or tap to compare Sleep · Recovery · Load for a day.")
                .font(.caption).foregroundStyle(Palette.textSecondary)
            Chart {
                ForEach(points) { point in
                    line(point.date, point.sleepScore, "Sleep")
                    line(point.date, point.recoveryScore, "Recovery")
                    line(point.date, point.loadScore, "Load")
                }
                if let sel = pillarSelection {
                    RuleMark(x: .value("Date", sel))
                        .foregroundStyle(Palette.textTertiary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartForegroundStyleScale(domain: ["Sleep", "Recovery", "Load"],
                                       range: [Palette.lavender, Palette.mint, Palette.accent])
            .chartYScale(domain: 0 ... 100)
            .chartLegend(.hidden)
            .frame(height: 180)
            .chartOverlay { proxy in
                ChartDayScrubOverlay(proxy: proxy, dates: dates, selection: $pillarSelection)
            }
            .clipped()

            ScrubDetailBanner(
                date: pillarSelection,
                placeholder: "Tap the chart to inspect a day",
                lines: pillarLines(for: pillarSelection, in: points),
                note: pillarNote(for: pillarSelection, in: points)
            )

            HStack(spacing: 14) {
                legendDot("Sleep", Palette.lavender)
                legendDot("Recovery", Palette.mint)
                legendDot("Load", Palette.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .onAppear {
            if pillarSelection == nil, let last = dates.last {
                pillarSelection = last
            }
        }
    }

    private func pillarLines(for selection: Date?, in points: [ReadinessPoint]) -> [String] {
        guard let selection,
              let hit = points.first(where: { ChartDate.day($0.date) == selection })
        else { return [] }
        return [
            "Sleep \(Int(hit.sleepScore.rounded())) — rest quality",
            "Recovery \(Int(hit.recoveryScore.rounded())) — HRV & resting HR",
            "Load \(Int(hit.loadScore.rounded())) — training strain",
        ]
    }

    private func pillarNote(for selection: Date?, in points: [ReadinessPoint]) -> String? {
        guard let selection,
              let hit = points.first(where: { ChartDate.day($0.date) == selection })
        else { return nil }
        let ranked = [("Sleep", hit.sleepScore), ("Recovery", hit.recoveryScore), ("Load", hit.loadScore)]
            .sorted { $0.1 < $1.1 }
        if let weak = ranked.first {
            return "\(weak.0) was weakest this day (\(Int(weak.1.rounded()))/100)."
        }
        return nil
    }

    private func line(_ date: String, _ value: Double, _ series: String) -> some ChartContent {
        LineMark(x: .value("Date", ChartDate.day(date)), y: .value("Score", value),
                 series: .value("Pillar", series))
            .foregroundStyle(by: .value("Pillar", series))
            .interpolationMethod(ChartStyle.smooth)
    }

    private func legendDot(_ label: String, _ color: Color) -> some View {
        Label(label, systemImage: "circle.fill")
            .font(.caption2).foregroundStyle(color).labelStyle(.titleAndIcon)
    }

    private func load() async {
        guard let client = settings.makeClient() else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            response = try await client.getHistory(days: rangeDays[rangeIndex])
            if selectedPointID == nil {
                selectedPointID = response?.data.last?.id
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        pillars = try? await client.getToday().pillars
    }
}
