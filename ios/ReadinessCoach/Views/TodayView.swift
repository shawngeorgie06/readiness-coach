import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService

    @State private var showAsk = false
    @State private var showSettings = false
    @State private var pillarInfo: PillarInfo?
    @State private var recent: [ReadinessPoint] = []

    /// Maps raw missing-metric keys to human names for the banner.
    static func friendlyMissing(_ keys: [String]) -> String {
        let names = keys.map { key -> String in
            switch key {
            case "hrv": return "heart-rate variability"
            case "resting_heart_rate": return "resting pulse"
            case "sleep": return "sleep"
            default: return key
            }
        }
        return names.isEmpty ? "" : " (\(names.joined(separator: ", ")))"
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
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
                        ErrorCard(message: error) {
                            Task { await sync.syncNow(settings); await loadRecent() }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .pageWidthLocked()
                .padding()
            }
            .verticalScrollLocked()
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAsk = true } label: { Image(systemName: "bubble.left.and.text.bubble.right") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await sync.syncNow(settings); await loadRecent() }
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
            .sheet(isPresented: $showAsk) { NavigationStack { AskCoachView() } }
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
            .sheet(item: $pillarInfo) { PillarDetailSheet(info: $0) }
            .refreshable { await sync.syncNow(settings); await loadRecent() }
            .task { await loadRecent() }
        }
    }

    @ViewBuilder
    private func content(_ today: TodayDTO) -> some View {
        if today.calibrating {
            banner(
                "Calibrating",
                "Baselines are still forming from your recent history. Treat scores as provisional.",
                color: .orange,
                icon: "gauge.with.dots.needle.33percent",
                infoTitle: "Calibrating",
                infoMessage: "Your baselines are still forming from recent history. Scores are provisional until ~14 days of data exist."
            )
        }
        if today.isLowConfidence {
            banner(
                "Low confidence",
                "Some data is missing today\(Self.friendlyMissing(today.missing)), so we're keeping the call cautious.",
                color: .yellow,
                icon: "exclamationmark.triangle",
                infoTitle: "Low confidence",
                infoMessage: "Some signals are missing today, so the decision stays conservative. Sync your Watch data to improve it."
            )
        }

        VStack(spacing: 12) {
            ReadinessRing(readiness: today.readiness, decision: today.decision)
            DecisionChip(decision: today.decision)
            Text(today.decision.meaning)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let count = sync.uploadingCount {
                Label("Uploading \(count) samples…", systemImage: "arrow.up.circle")
                    .font(.caption).foregroundStyle(.secondary)
            } else             if let synced = settings.lastSyncRelativeText {
                Text("Last synced \(synced)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("App update \(AppBuild.stamp) · pull main & Run to install")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if !today.overridesApplied.isEmpty {
                Text("Overrides: \(today.overridesApplied.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)

        pillars(today.pillars)
        if recent.count > 1 {
            SectionCard(title: "Readiness trend") {
                ReadinessSparkline(points: recent)
                Text("Last \(recent.count) days · tap Trends for detail")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        advisor(today.advisor)
        Button { showAsk = true } label: {
            Label("Ask the coach", systemImage: "bubble.left.and.text.bubble.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func pillars(_ pillars: Pillars) -> some View {
        SectionCard(title: "Pillars") {
            pillarButton("Sleep", "35%",
                "Last night's duration and quality vs your ~8h need, plus recent sleep debt and consistency.",
                pillars.sleep)
            Divider()
            pillarButton("Recovery", "40%",
                "HRV and resting heart rate vs your 30-day baseline — the strongest readiness signal.",
                pillars.recovery)
            Divider()
            pillarButton("Load", "25%",
                "Recent training strain and the acute:chronic ratio — how hard you've pushed lately vs your norm.",
                pillars.load)
        }
    }

    private func pillarButton(_ name: String, _ weight: String, _ description: String, _ pillar: PillarScore) -> some View {
        Button {
            pillarInfo = PillarInfo(name: name, weight: weight, description: description, pillar: pillar)
        } label: {
            PillarRow(name: name, weight: weight, pillar: pillar)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows what \(name) measures and today's drivers")
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

    private func banner(_ title: String, _ message: String, color: Color, icon: String,
                        infoTitle: String, infoMessage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            InfoBadge(title: infoTitle, message: infoMessage)
        }
        .padding()
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Loads the 7-day readiness history for the sparkline; failures hide it silently.
    private func loadRecent() async {
        guard let client = settings.makeClient() else { return }
        recent = (try? await client.getHistory(days: 7).data) ?? []
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
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            // ProgressView eats taps when the bar is full (common for Sleep at ~100).
            ProgressView(value: min(max(pillar.score / 100, 0), 1))
                .allowsHitTesting(false)
            if !pillar.drivers.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(pillar.drivers, id: \.self) { driver in
                        Text(driver.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .allowsHitTesting(false)
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
