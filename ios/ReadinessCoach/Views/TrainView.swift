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
                        SectionCard(title: "Strain — last \(response.days) days") {
                            Chart(response.data) { workout in
                                BarMark(
                                    x: .value("Day", ChartDate.day(workout.startAt)),
                                    y: .value("Strain", workout.strain)
                                )
                                .foregroundStyle(.orange)
                            }
                            .frame(height: 200)
                        }

                        SectionCard(title: "Workouts") {
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
                        Text(error).font(.footnote).foregroundStyle(.red)
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

}

struct WorkoutRow: View {
    let workout: WorkoutDTO
    private let zoneColors: [Color] = [.gray, .blue, .green, .orange, .red]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.sport.capitalized).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("strain \(String(format: "%.1f", workout.strain))")
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
            Text("HR zones · " + zones.enumerated()
                .map { "Z\($0.offset + 1) \(fmtMin($0.element))m" }
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
