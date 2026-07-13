import SwiftUI
import Charts

struct TrainView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var response: TrainResponse?
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let response, !response.data.isEmpty {
                        weeklyCard(response.data)
                        SectionCard(title: "Daily strain — last \(response.days) days") {
                            Chart(dailyStrain(response.data)) { day in
                                BarMark(
                                    x: .value("Day", day.day),
                                    y: .value("Strain", day.strain)
                                )
                                .foregroundStyle(.orange)
                            }
                            .frame(height: 200)
                        }

                        SectionCard(title: "Workouts") {
                            HStack(spacing: 6) {
                                Text("Strain 0–21").font(.caption2).foregroundStyle(.secondary)
                                InfoBadge(title: "Strain", message: "Strain rates how hard a session was, 0–21, from heart rate and duration.")
                                Spacer()
                                Text("HR zones").font(.caption2).foregroundStyle(.secondary)
                                InfoBadge(title: "Heart-rate zones", message: "Zones are shares of your session spent at rising heart rates — Easy is a warm-up pace, Max is near your ceiling.")
                            }
                            ForEach(response.data) { workout in
                                WorkoutRow(workout: workout)
                                if workout.id != response.data.last?.id { Divider() }
                            }
                        }
                    } else if isLoading {
                        ProgressView().padding(.top, 60)
                    } else {
                        ContentUnavailableCompat(
                            title: "No workouts",
                            message: "Sync from the Today tab to load training history.",
                            systemImage: "figure.run"
                        )
                    }
                    if let error {
                        ErrorCard(message: error) { Task { await load() } }
                    }
                }
                .padding()
            }
            .navigationTitle("Train")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard let client = settings.makeClient() else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            response = try await client.getTrain(days: 28)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private struct DayStrain: Identifiable {
        let day: Date
        let strain: Double
        var id: Date { day }
    }

    /// One summed-strain bar per calendar day.
    private func dailyStrain(_ workouts: [WorkoutDTO]) -> [DayStrain] {
        let groups = Dictionary(grouping: workouts) { ChartDate.day($0.startAt) }
        return groups.map { DayStrain(day: $0.key, strain: $0.value.reduce(0) { $0 + $1.strain }) }
            .sorted { $0.day < $1.day }
    }

    private func weeklyWorkouts(_ workouts: [WorkoutDTO]) -> [WorkoutDTO] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return workouts.filter { (Self.isoParser.date(from: $0.startAt) ?? .distantPast) >= cutoff }
    }

    private func weekday(_ iso: String) -> String {
        guard let date = Self.isoParser.date(from: iso) else { return "—" }
        return date.formatted(.dateTime.weekday())
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return total >= 60 ? "\(total / 60)h \(total % 60)m" : "\(total)m"
    }

    @ViewBuilder
    private func weeklyCard(_ workouts: [WorkoutDTO]) -> some View {
        let week = weeklyWorkouts(workouts)
        if !week.isEmpty {
            let totalStrain = week.reduce(0) { $0 + $1.strain }
            let totalMin = week.reduce(0) { $0 + $1.durationMin }
            let hardest = week.max { $0.strain < $1.strain }
            SectionCard(title: "This week") {
                Text("\(week.count) session\(week.count == 1 ? "" : "s") · \(formatMinutes(totalMin)) · \(Int(totalStrain.rounded())) total strain")
                    .font(.subheadline.weight(.medium))
                if let hardest {
                    Text("Hardest: \(weekday(hardest.startAt)) (\(Int(hardest.strain.rounded())))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct WorkoutRow: View {
    let workout: WorkoutDTO
    private let zoneColors: [Color] = [.gray, .blue, .green, .orange, .red]
    private let zoneNames = ["Easy", "Light", "Moderate", "Hard", "Max"]

    private func strainBand(_ strain: Double) -> String {
        if strain < 8 { return "easy" }
        if strain < 14 { return "moderately hard" }
        if strain < 18 { return "hard" }
        return "all-out"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.sport.capitalized).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Strain \(Int(workout.strain.rounded())) · \(strainBand(workout.strain))")
                        .font(.subheadline.monospacedDigit())
                    if !hrText.isEmpty {
                        Text(hrText).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let zones = workout.hrZonesMin, zones.contains(where: { $0 > 0 }) {
                zoneBar(zones)
            }
        }
        .padding(.vertical, 2)
    }

    private func zoneBar(_ zones: [Double]) -> some View {
        let total = max(zones.reduce(0, +), 0.001)
        return VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { index, minutes in
                        zoneColors[min(index, 4)]
                            .frame(width: max(0, geo.size.width * (minutes / total)))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            Text(zones.enumerated()
                .map { "\(zoneNames[min($0.offset, 4)]) \(fmtMin($0.element))m" }
                .joined(separator: "  "))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var hrText: String {
        var parts: [String] = []
        if let avg = workout.avgHrBpm { parts.append("\(Int(avg.rounded())) avg") }
        if let max = workout.maxHrBpm { parts.append("\(Int(max.rounded())) max") }
        return parts.isEmpty ? "" : parts.joined(separator: " · ") + " bpm"
    }

    private var subtitle: String {
        var parts = ["\(Int(workout.durationMin.rounded())) min"]
        if let cal = workout.calories { parts.append("\(Int(cal.rounded())) kcal") }
        return parts.joined(separator: " · ")
    }

    private func fmtMin(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
