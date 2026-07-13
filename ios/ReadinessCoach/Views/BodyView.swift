import SwiftUI
import Charts

struct BodyView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var response: BodyResponse?
    @State private var error: String?
    @State private var isLoading = false
    @State private var lineSelection: Date?
    @State private var hrSelection: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let response, !response.daily.isEmpty {
                        lineCard("HRV (SDNN, ms)", type: "hrv_sdnn", color: .teal, rows: response.daily)
                        lineCard("Resting heart rate (bpm)", type: "resting_heart_rate", color: .pink, rows: response.daily)
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
                .padding()
            }
            .navigationTitle("Body")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    /// Daily-average line for a single metric type.
    @ViewBuilder
    private func lineCard(_ title: String, type: String, color: Color, rows: [BodyDaily]) -> some View {
        let series = rows.filter { $0.type == type }.sorted { $0.date < $1.date }
        if !series.isEmpty {
            SectionCard(title: title) {
                Chart(series) { day in
                    LineMark(x: .value("Date", ChartDate.day(day.date)), y: .value("Avg", day.avg))
                        .foregroundStyle(color)
                    PointMark(x: .value("Date", ChartDate.day(day.date)), y: .value("Avg", day.avg))
                        .foregroundStyle(color).symbolSize(18)
                    if let sel = nearestDate(lineSelection, in: series.map { ChartDate.day($0.date) }),
                       let hit = series.first(where: { ChartDate.day($0.date) == sel }) {
                        RuleMark(x: .value("Date", sel))
                            .foregroundStyle(.gray.opacity(0.4))
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                ScrubReadout(date: sel, lines: ["\(fmt(hit.avg)) avg"])
                            }
                    }
                }
                .frame(height: 190)
                .chartXSelection(value: $lineSelection)
                if let latest = series.last {
                    Text("Latest avg \(fmt(latest.avg))  (range \(fmt(latest.min))–\(fmt(latest.max)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Heart rate as a daily min–max band with the average line on top.
    @ViewBuilder
    private func heartRateCard(_ rows: [BodyDaily]) -> some View {
        let series = rows.filter { $0.type == "heart_rate" }.sorted { $0.date < $1.date }
        if !series.isEmpty {
            SectionCard(title: "Heart rate (bpm) — daily min · avg · max") {
                Chart(series) { day in
                    AreaMark(
                        x: .value("Date", ChartDate.day(day.date)),
                        yStart: .value("Min", day.min),
                        yEnd: .value("Max", day.max)
                    )
                    .foregroundStyle(.red.opacity(0.15))
                    LineMark(x: .value("Date", ChartDate.day(day.date)), y: .value("Avg", day.avg))
                        .foregroundStyle(.red)
                    if let sel = nearestDate(hrSelection, in: series.map { ChartDate.day($0.date) }),
                       let hit = series.first(where: { ChartDate.day($0.date) == sel }) {
                        RuleMark(x: .value("Date", sel))
                            .foregroundStyle(.gray.opacity(0.4))
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                ScrubReadout(date: sel, lines: [
                                    "min \(fmt(hit.min))", "avg \(fmt(hit.avg))", "max \(fmt(hit.max))",
                                ])
                            }
                    }
                }
                .frame(height: 200)
                .chartXSelection(value: $hrSelection)
                if let latest = series.last {
                    Text("Latest — min \(fmt(latest.min)) · avg \(fmt(latest.avg)) · max \(fmt(latest.max)) bpm")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
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
    }

    private func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
