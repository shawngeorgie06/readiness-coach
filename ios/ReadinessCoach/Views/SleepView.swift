import SwiftUI
import Charts

struct SleepView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var response: SleepDetailResponse?
    @State private var error: String?
    @State private var isLoading = false

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let needHours = 8.0

    private func clockTime(_ iso: String?) -> String? {
        guard let iso, let date = Self.isoParser.date(from: iso) else { return nil }
        return date.formatted(.dateTime.hour().minute())
    }

    /// Local minutes-past-midnight for a bedtime, or nil.
    private func bedMinutes(_ iso: String?) -> Int? {
        guard let iso, let date = Self.isoParser.date(from: iso) else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let h = c.hour, let m = c.minute else { return nil }
        return h * 60 + m
    }

    private func durationQualifier(_ hours: Double) -> String {
        if hours < 6 { return "well below" }
        if hours < 7.5 { return "a bit below" }
        if hours <= 8.5 { return "right on" }
        return "above"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let nights, !nights.isEmpty {
                        summaryCard(nights)
                        SleepChartsSection()
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
                        ErrorCard(message: error) { Task { await load() } }
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

    @ViewBuilder
    private func summaryCard(_ nights: [SleepDay]) -> some View {
        if let last = nights.last {
            let recent = nights.suffix(7)
            let avg = recent.map(\.durationHours).reduce(0, +) / Double(max(recent.count, 1))
            SectionCard(title: "Last night") {
                Text("You slept \(fmt(last.durationHours))h — \(durationQualifier(last.durationHours)) your \(Int(Self.needHours))h target.")
                    .font(.subheadline.weight(.medium))
                if let bed = clockTime(last.sleepStart), let wake = clockTime(last.sleepEnd) {
                    Label("Asleep \(bed) → woke \(wake)", systemImage: "bed.double")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("vs your \(recent.count)-day average of \(fmt(avg))h.")
                    .font(.caption).foregroundStyle(.secondary)
                consistencyRow(nights)
                HStack(spacing: 6) {
                    Text("Deep + REM \(fmt(last.restorativeHours))h — the recovery stages.")
                        .font(.caption).foregroundStyle(.secondary)
                    InfoBadge(title: "Sleep stages",
                              message: "Deep and REM are when your body and brain recover. Core is lighter sleep; Awake is brief wake-ups. Restorative = deep + REM.")
                }
            }
        }
    }

    @ViewBuilder
    private func consistencyRow(_ nights: [SleepDay]) -> some View {
        let mins = nights.suffix(7).compactMap { bedMinutes($0.sleepStart) }
            .map { ($0 + 720) % 1440 }
        if mins.count >= 3 {
            let mean = Double(mins.reduce(0, +)) / Double(mins.count)
            let variance = mins.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(mins.count)
            let std = Int(variance.squareRoot().rounded())
            let label = std <= 30 ? "very consistent"
                : std <= 60 ? "fairly consistent"
                : std <= 90 ? "a little irregular" : "irregular"
            HStack(spacing: 6) {
                Text("Schedule: \(label) (±\(std) min this week).")
                    .font(.caption).foregroundStyle(.secondary)
                InfoBadge(title: "Sleep consistency",
                          message: "Going to bed and waking at similar times helps recovery. This is how much your bedtime varied over the past week.")
            }
        }
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

/// Total-sleep and stage-breakdown charts, shared by the Sleep tab and folded into
/// Insights (`TrendsView`). Fetches its own `SleepDetailResponse` so callers need no
/// extra plumbing.
struct SleepChartsSection: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var response: SleepDetailResponse?
    @State private var error: String?
    @State private var isLoading = false

    private let stageColors: [(name: String, color: Color)] = [
        ("Deep", .indigo), ("REM", .purple), ("Core", .blue), ("Awake", .orange),
    ]

    var body: some View {
        Group {
            if let nights, !nights.isEmpty {
                totalCard(nights)
                stageCard(nights)
            } else if isLoading {
                ProgressView().padding(.top, 20)
            } else if let error {
                ErrorCard(message: error) { Task { await load() } }
            }
        }
        .task { await load() }
    }

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
            Text("Blue is total sleep; darker is deep + REM (restorative).")
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
