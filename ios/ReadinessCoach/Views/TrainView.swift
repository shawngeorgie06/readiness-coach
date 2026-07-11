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
                                    x: .value("Day", shortDate(workout.startAt)),
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

    private func shortDate(_ iso: String) -> String {
        guard let date = DateFormatting.date(fromISO: iso) else { return String(iso.prefix(10)) }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }
}

struct WorkoutRow: View {
    let workout: WorkoutDTO

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.sport.capitalized).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("strain \(String(format: "%.1f", workout.strain))")
                    .font(.subheadline.monospacedDigit())
                if let hr = workout.avgHrBpm {
                    Text("\(Int(hr.rounded())) bpm avg")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts = ["\(Int(workout.durationMin.rounded())) min"]
        if let cal = workout.calories { parts.append("\(Int(cal.rounded())) kcal") }
        return parts.joined(separator: " · ")
    }
}
