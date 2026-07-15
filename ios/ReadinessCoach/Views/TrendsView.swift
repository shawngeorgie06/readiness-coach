import SwiftUI
import Charts

/// Insights tab — matches the Aether prototype's Insights panel: screen-head,
/// a range selector, the readiness trend as bars, plus real pillar trends and
/// the folded sleep charts.
struct TrendsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var response: ReadinessHistoryResponse?
    @State private var error: String?
    @State private var isLoading = false
    @State private var rangeIndex = 1
    @State private var pillarSelection: Date?
    @State private var pillars: Pillars?

    private let rangeLabels = ["7d", "30d", "90d"]
    private let rangeDays = [7, 30, 90]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    SegmentedRange(rangeLabels, selection: $rangeIndex)
                    if let points, !points.isEmpty {
                        trendCard(points)
                        insightCards()
                        pillarsCard(points)
                        SleepChartsSection()
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
                .padding()
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: rangeIndex) { _, _ in Task { await load() } }
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

    // MARK: - Readiness trend (bars, avg, delta)

    private func trendCard(_ points: [ReadinessPoint]) -> some View {
        let avg = points.map(\.readiness).reduce(0, +) / Double(points.count)
        let delta = (points.last?.readiness ?? 0) - (points.first?.readiness ?? 0)
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
                Pill(String(format: "%+d pts", Int(delta.rounded())), tone: delta >= 0 ? .good : .warn)
            }
            trendBars(points)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func trendBars(_ points: [ReadinessPoint]) -> some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: max(2, 4 - Double(points.count) / 30)) {
                ForEach(points) { p in
                    let isToday = p.id == points.last?.id
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isToday ? Palette.accent : Palette.accent.opacity(0.5))
                        .frame(height: max(6, geo.size.height * (p.readiness / 100)))
                        .shadow(color: isToday ? Palette.accent.opacity(0.5) : .clear, radius: 6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 130)
    }

    // MARK: - Insight cards (real, from the pillar drivers)

    @ViewBuilder
    private func insightCards() -> some View {
        if let pillars {
            insightCard("Sleep", .sleep, pillars.sleep)
            insightCard("Recovery", .good, pillars.recovery)
            insightCard("Load", .accent, pillars.load)
        }
    }

    private func insightCard(_ name: String, _ tone: Pill.Tone, _ pillar: PillarScore) -> some View {
        let driver = pillar.drivers.first
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Pill(name, tone: tone)
                Spacer()
                Text("Score \(Int(pillar.score.rounded()))")
                    .font(.system(.caption2, design: .monospaced)).foregroundStyle(Palette.textTertiary)
            }
            Text(driver?.text ?? "No data yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
            if let detail = driver?.detail {
                Text(detail).font(.callout).foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Pillar trends (real, restyled to the Aether palette)

    private func pillarsCard(_ points: [ReadinessPoint]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Pillar scores")
            Chart {
                ForEach(points) { point in
                    line(point.date, point.sleepScore, "Sleep")
                    line(point.date, point.recoveryScore, "Recovery")
                    line(point.date, point.loadScore, "Load")
                }
                if let sel = pillarSelection {
                    RuleMark(x: .value("Date", sel))
                        .foregroundStyle(Palette.textTertiary.opacity(0.5))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            if let snapped = nearestDate(sel, in: points.map { ChartDate.day($0.date) }),
                               let hit = points.first(where: { ChartDate.day($0.date) == snapped }) {
                                ScrubReadout(date: snapped, lines: [
                                    "Sleep \(Int(hit.sleepScore.rounded()))",
                                    "Recovery \(Int(hit.recoveryScore.rounded()))",
                                    "Load \(Int(hit.loadScore.rounded()))",
                                ])
                            }
                        }
                }
            }
            .chartForegroundStyleScale(domain: ["Sleep", "Recovery", "Load"],
                                       range: [Palette.lavender, Palette.mint, Palette.accent])
            .chartYScale(domain: 0 ... 100)
            .chartLegend(.hidden)
            .frame(height: 180)
            .chartXSelection(value: $pillarSelection)
            HStack(spacing: 14) {
                legendDot("Sleep", Palette.lavender)
                legendDot("Recovery", Palette.mint)
                legendDot("Load", Palette.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func line(_ date: String, _ value: Double, _ series: String) -> some ChartContent {
        LineMark(x: .value("Date", ChartDate.day(date)), y: .value("Score", value),
                 series: .value("Pillar", series))
            .foregroundStyle(by: .value("Pillar", series))
            .interpolationMethod(.catmullRom)
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
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        pillars = try? await client.getToday().pillars
    }
}
