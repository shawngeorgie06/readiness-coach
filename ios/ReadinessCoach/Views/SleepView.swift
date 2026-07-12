import SwiftUI
import Charts

struct SleepView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var response: SleepDetailResponse?
    @State private var error: String?
    @State private var isLoading = false

    private let stageColors: [(name: String, color: Color)] = [
        ("Deep", .indigo), ("REM", .purple), ("Core", .blue), ("Awake", .orange),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let nights, !nights.isEmpty {
                        totalCard(nights)
                        stageCard(nights)
                    } else if isLoading {
                        ProgressView().padding(.top, 60)
                    } else {
                        ContentUnavailableCompat(
                            title: "No sleep data",
                            message: "Sync from the Today tab to load sleep history.",
                            systemImage: "bed.double"
                        )
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Sleep")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    /// Nights that actually have sleep recorded.
    private var nights: [SleepDay]? {
        response?.data.filter { $0.durationHours > 0 }
    }

    private func totalCard(_ nights: [SleepDay]) -> some View {
        SectionCard(title: "Total sleep — last \(response?.days ?? 0) days") {
            Chart(nights) { day in
                BarMark(
                    x: .value("Date", ChartDate.day(day.date)),
                    y: .value("Hours", day.durationHours)
                )
                .foregroundStyle(.blue.opacity(0.5))
                BarMark(
                    x: .value("Date", ChartDate.day(day.date)),
                    y: .value("Restorative", day.restorativeHours)
                )
                .foregroundStyle(.indigo)
            }
            .frame(height: 200)
            Text("Darker portion is deep + REM (restorative).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func stageCard(_ nights: [SleepDay]) -> some View {
        SectionCard(title: "Stages by night") {
            Chart {
                ForEach(nights) { day in
                    stageBar(day, "Deep", day.stages.deep, .indigo)
                    stageBar(day, "REM", day.stages.rem, .purple)
                    stageBar(day, "Core", day.stages.core, .blue)
                    stageBar(day, "Awake", day.stages.awake, .orange)
                }
            }
            .chartForegroundStyleScale(domain: stageColors.map(\.name), range: stageColors.map(\.color))
            .frame(height: 220)
            if let latest = nights.last {
                Text("Last night — deep \(fmt(latest.stages.deep))h · REM \(fmt(latest.stages.rem))h · core \(fmt(latest.stages.core))h · awake \(fmt(latest.stages.awake))h")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func stageBar(_ day: SleepDay, _ name: String, _ hours: Double, _ color: Color) -> some ChartContent {
        BarMark(
            x: .value("Date", ChartDate.day(day.date)),
            y: .value("Hours", hours)
        )
        .foregroundStyle(by: .value("Stage", name))
    }

    private func load() async {
        guard let client = settings.makeClient() else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            response = try await client.getSleep(days: 30)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func fmt(_ value: Double) -> String { String(format: "%.1f", value) }
}
