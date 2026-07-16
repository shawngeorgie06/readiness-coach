import SwiftUI

/// Activity tab — Aether: filter chips, workout list, weekly load. Real HealthKit sports.
struct TrainView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var response: TrainResponse?
    @State private var error: String?
    @State private var isLoading = false
    @State private var filter = "All"
    @State private var selectedWorkout: WorkoutDTO?

    private let filters = ["All", "Run", "Strength", "Recovery"]

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    header
                    if let response, !response.data.isEmpty {
                        chips
                        weeklyCard(response.data)
                        workoutList(filtered(response.data))
                    } else if isLoading {
                        ProgressView().padding(.top, 60)
                    } else {
                        ContentUnavailableCompat(
                            title: "No workouts",
                            message: "Sync from the Today tab to load training history.",
                            systemImage: "bolt.fill"
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
            .sheet(item: $selectedWorkout) { WorkoutDetailSheet(workout: $0) }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Log")
                Text("Activity").font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { f in
                    Button { filter = f } label: {
                        Text(f)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(filter == f ? Palette.accent : Palette.textSecondary)
                            .background(
                                Capsule().fill(filter == f ? Palette.accent.opacity(0.16) : .clear)
                                    .overlay(Capsule().strokeBorder(filter == f ? Palette.accent.opacity(0.35) : Palette.stroke, lineWidth: 1))
                            )
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func workoutList(_ workouts: [WorkoutDTO]) -> some View {
        VStack(spacing: 0) {
            Text("Tap a workout for full details")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(workouts) { w in
                Button {
                    selectedWorkout = w
                } label: {
                    AetherListRow(systemImage: WorkoutSport.symbolName(forKey: w.sport),
                                  tone: rowTone(w.sport),
                                  title: WorkoutSport.title(forKey: w.sport),
                                  subtitle: rowSubtitle(w)) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(fmt(w.strain)).font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.textPrimary)
                            Text("strain · \(Int(w.durationMin.rounded()))m")
                                .font(.caption2).foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                if w.id != workouts.last?.id {
                    Divider().overlay(Palette.strokeSoft).padding(.leading, 14)
                }
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.strokeSoft, lineWidth: 1))
    }

    @ViewBuilder
    private func weeklyCard(_ workouts: [WorkoutDTO]) -> some View {
        let week = weeklyWorkouts(workouts)
        if !week.isEmpty {
            let totalStrain = week.reduce(0) { $0 + $1.strain }
            let totalMin = week.reduce(0) { $0 + $1.durationMin }
            let hardest = week.max { $0.strain < $1.strain }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "This week")
                    Spacer()
                    Text(fmt(totalStrain)).font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.accent)
                }
                Text("\(week.count) session\(week.count == 1 ? "" : "s") · \(formatMinutes(totalMin)) · cumulative strain this week")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
                if let hardest {
                    Text("Hardest: \(WorkoutSport.title(forKey: hardest.sport)) · \(weekday(hardest.startAt))")
                        .font(.caption).foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
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

    private func filtered(_ workouts: [WorkoutDTO]) -> [WorkoutDTO] {
        let sorted = workouts.sorted { $0.startAt > $1.startAt }
        return filter == "All" ? sorted : sorted.filter { WorkoutSport.filterCategory(forKey: $0.sport) == filter }
    }

    private func rowSubtitle(_ w: WorkoutDTO) -> String {
        var parts = [weekday(w.startAt)]
        if let cal = w.calories { parts.append("\(Int(cal.rounded())) kcal") }
        if let hr = w.avgHrBpm { parts.append("\(Int(hr.rounded())) bpm") }
        return parts.joined(separator: " · ")
    }

    private func rowTone(_ sport: String) -> AetherRowTone {
        WorkoutSport.filterCategory(forKey: sport) == "Recovery" ? .mint : .accent
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

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

    private func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct WorkoutDetailSheet: View {
    let workout: WorkoutDTO
    @Environment(\.dismiss) private var dismiss

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(WorkoutSport.title(forKey: workout.sport),
                          systemImage: WorkoutSport.symbolName(forKey: workout.sport))
                        .font(.headline)
                    Text(WorkoutSport.detailBlurb(forKey: workout.sport))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Session") {
                    LabeledContent("When", value: whenText)
                    LabeledContent("Duration", value: "\(Int(workout.durationMin.rounded())) min")
                    if let cal = workout.calories {
                        LabeledContent("Calories", value: "\(Int(cal.rounded())) kcal")
                    }
                }
                Section("Effort") {
                    LabeledContent("Strain", value: String(format: "%.1f / 21", workout.strain))
                    Text(StrainExplain.scaleBlurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let avg = workout.avgHrBpm {
                        LabeledContent("Avg heart rate", value: "\(Int(avg.rounded())) bpm")
                    }
                    if let max = workout.maxHrBpm {
                        LabeledContent("Max heart rate", value: "\(Int(max.rounded())) bpm")
                    }
                }
                if let zones = workout.hrZonesMin, zones.contains(where: { $0 > 0 }) {
                    Section("Heart-rate zones") {
                        let names = ["Easy", "Light", "Moderate", "Hard", "Max"]
                        ForEach(Array(zones.enumerated()), id: \.offset) { index, minutes in
                            if minutes > 0 {
                                LabeledContent(names[min(index, 4)], value: String(format: "%.0f min", minutes))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private var whenText: String {
        guard let start = Self.isoParser.date(from: workout.startAt) else { return workout.startAt }
        return start.formatted(.dateTime.weekday(.wide).month().day().hour().minute())
    }
}
