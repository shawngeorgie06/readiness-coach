import SwiftUI

/// Activity tab — matches the Aether prototype's Activities panel: screen-head,
/// filter chips, a workout list, and a weekly-load card. All real workout data.
struct TrainView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var response: TrainResponse?
    @State private var error: String?
    @State private var isLoading = false
    @State private var filter = "All"

    private let filters = ["All", "Run", "Strength", "Recovery"]

    var body: some View {
        NavigationStack {
            ScrollView {
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
                .padding()
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
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
            ForEach(workouts) { w in
                AetherListRow(systemImage: icon(w.sport), tone: rowTone(w.sport),
                              title: prettySport(w.sport),
                              subtitle: "\(weekday(w.startAt)) · \(Int(w.durationMin.rounded())) min") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(fmt(w.strain)).font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                        Text("strain").font(.caption2).foregroundStyle(Palette.textSecondary)
                    }
                }
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
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "This week")
                    Spacer()
                    Text(fmt(totalStrain)).font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.accent)
                }
                Text("\(week.count) session\(week.count == 1 ? "" : "s") · \(formatMinutes(totalMin)) · cumulative strain this week")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    // MARK: - Data

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
        return filter == "All" ? sorted : sorted.filter { category($0.sport) == filter }
    }

    private func category(_ sport: String) -> String {
        let s = sport.lowercased()
        if s.contains("run") || s.contains("walk") || s.contains("cycl") || s.contains("ride") { return "Run" }
        if s.contains("strength") || s.contains("function") || s.contains("traditional") || s.contains("lift") { return "Strength" }
        if s.contains("yoga") || s.contains("mind") || s.contains("flex") || s.contains("cool") || s.contains("breath") { return "Recovery" }
        return "Other"
    }

    private func prettySport(_ sport: String) -> String {
        sport.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func icon(_ sport: String) -> String {
        switch category(sport) {
        case "Run": return "figure.run"
        case "Strength": return "dumbbell.fill"
        case "Recovery": return "figure.mind.and.body"
        default: return "bolt.fill"
        }
    }

    private func rowTone(_ sport: String) -> AetherRowTone {
        switch category(sport) {
        case "Recovery": return .mint
        default: return .accent
        }
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
