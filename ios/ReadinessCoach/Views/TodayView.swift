import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let today = sync.today {
                        content(today)
                    } else if sync.isLoadingToday || sync.isSyncing {
                        ProgressView("Loading today…")
                            .padding(.top, 60)
                    } else {
                        ContentUnavailableCompat(
                            title: "No readiness yet",
                            message: "Sync your Health data to compute today's score.",
                            systemImage: "sun.max"
                        )
                    }

                    if let error = sync.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await sync.syncNow(settings) }
                    } label: {
                        if sync.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(sync.isSyncing)
                }
            }
            .refreshable { await sync.syncNow(settings) }
            .task {
                if sync.today == nil { await sync.refreshToday(settings) }
            }
        }
    }

    @ViewBuilder
    private func content(_ today: TodayDTO) -> some View {
        if today.calibrating {
            banner(
                "Calibrating",
                "Baselines are still forming from your recent history. Treat scores as provisional.",
                color: .orange,
                icon: "gauge.with.dots.needle.33percent"
            )
        }
        if today.isLowConfidence {
            banner(
                "Low confidence",
                "Missing \(today.missing.isEmpty ? "some signals" : today.missing.joined(separator: ", ")). The decision stays conservative.",
                color: .yellow,
                icon: "exclamationmark.triangle"
            )
        }

        VStack(spacing: 12) {
            ReadinessRing(readiness: today.readiness, decision: today.decision)
            DecisionChip(decision: today.decision)
            if !today.overridesApplied.isEmpty {
                Text("Overrides: \(today.overridesApplied.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)

        pillars(today.pillars)
        advisor(today.advisor)
    }

    private func pillars(_ pillars: Pillars) -> some View {
        SectionCard(title: "Pillars") {
            PillarRow(name: "Sleep", weight: "35%", pillar: pillars.sleep)
            Divider()
            PillarRow(name: "Recovery", weight: "40%", pillar: pillars.recovery)
            Divider()
            PillarRow(name: "Load", weight: "25%", pillar: pillars.load)
        }
    }

    private func advisor(_ note: AdvisorNote) -> some View {
        SectionCard(title: "Strict advisor") {
            if !note.why.isEmpty {
                ForEach(note.why, id: \.self) { line in
                    Label(line, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .labelStyle(.titleAndIcon)
                }
            }
            Text(note.prescription)
                .font(.subheadline.weight(.medium))
                .padding(.top, 4)
            Text("If ignored: \(note.ifIgnored)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(note.source == "llm" ? "Written by coach model" : "Template note")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func banner(_ title: String, _ message: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PillarRow: View {
    let name: String
    let weight: String
    let pillar: PillarScore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.subheadline.weight(.semibold))
                Text(weight).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(pillar.score.rounded()))")
                    .font(.subheadline.monospacedDigit())
            }
            ProgressView(value: min(max(pillar.score / 100, 0), 1))
            if !pillar.drivers.isEmpty {
                Text(pillar.drivers.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Small back-compat wrapper so the empty state renders on iOS 17.
struct ContentUnavailableCompat: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }
}
