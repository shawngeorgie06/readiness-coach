import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService

    @State private var showAsk = false
    @State private var showSettings = false
    @State private var pillarInfo: PillarInfo?
    @State private var recent: [ReadinessPoint] = []
    @State private var hrv: Double?
    @State private var rhr: Double?
    @State private var sleepHours: Double?

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
                        ErrorCard(message: error) {
                            Task { await sync.syncNow(settings); await loadRecent(); await loadMiniStats() }
                        }
                    }
                }
                .padding()
            }
            .screenBackground()
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
                        Task { await sync.syncNow(settings); await loadRecent(); await loadMiniStats() }
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
            .refreshable { await sync.syncNow(settings); await loadRecent(); await loadMiniStats() }
            .task { await loadRecent(); await loadMiniStats() }
        }
    }

    @ViewBuilder
    private func content(_ today: TodayDTO) -> some View {
        if today.calibrating {
            banner(
                "Calibrating",
                "Baselines are still forming from your recent history. Treat scores as provisional.",
                color: Palette.warn,
                icon: "gauge.with.dots.needle.33percent",
                infoTitle: "Calibrating",
                infoMessage: "Your baselines are still forming from recent history. Scores are provisional until ~14 days of data exist."
            )
        }
        if today.isLowConfidence {
            banner(
                "Low confidence",
                "Some data is missing today\(Self.friendlyMissing(today.missing)), so we're keeping the call cautious.",
                color: Palette.warn,
                icon: "exclamationmark.triangle.fill",
                infoTitle: "Low confidence",
                infoMessage: "Some signals are missing today, so the decision stays conservative. Sync your Watch data to improve it."
            )
        }

        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Readiness", color: Palette.accent)
                    Text("Calibrated from sleep, HRV & load").font(.caption).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Pill(today.decision.title, tone: pillTone(today.decision))
            }
            ReadinessRing(readiness: today.readiness, decision: today.decision)
            Text(today.decision.meaning).font(.system(.body, design: .rounded))
                .foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
            HStack(spacing: 8) {
                miniStat("HRV", hrv.map { "\(Int($0.rounded()))" } ?? "—", "ms")
                miniStat("RHR", rhr.map { "\(Int($0.rounded()))" } ?? "—", "bpm")
                miniStat("Sleep", sleepHours.map { String(format: "%.1f", $0) } ?? "—", "h")
            }
        }
        .frame(maxWidth: .infinity)
        .heroCard()

        if let count = sync.uploadingCount {
            Label("Uploading \(count) samples…", systemImage: "arrow.up.circle")
                .font(.caption2).foregroundStyle(Palette.textSecondary)
        } else if let synced = settings.lastSyncRelativeText {
            Text("Last synced \(synced)")
                .font(.caption2).foregroundStyle(Palette.textSecondary)
        }
        if !today.overridesApplied.isEmpty {
            Text("Overrides: \(today.overridesApplied.joined(separator: ", "))")
                .font(.caption2)
                .foregroundStyle(Palette.textSecondary)
        }

        metricTiles(today.pillars)
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
        .buttonStyle(.borderedProminent)
        .tint(Palette.accent)
    }

    private func pillTone(_ d: Decision) -> Pill.Tone {
        switch d { case .push: return .good; case .maintain: return .warn; case .recover: return .accent }
    }

    /// A small labeled value inside the hero card (HRV / RHR / Sleep).
    private func miniStat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(Palette.textPrimary)
                Text(unit).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 2-column grid of Load / Recovery / Sleep tiles, each showing its real pillar score
    /// (0–100, higher is better) so the tile number always matches its PillarDetailSheet.
    private func metricTiles(_ pillars: Pillars) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            metricTileButton("Load", "25%",
                "Recent training strain and the acute:chronic ratio — how hard you've pushed lately vs your norm.",
                pillars.load) {
                MetricTile(label: "Load", value: "\(Int(pillars.load.score.rounded()))", fraction: pillars.load.score / 100, tone: .strain)
            }
            metricTileButton("Recovery", "40%",
                "HRV and resting heart rate vs your 30-day baseline — the strongest readiness signal.",
                pillars.recovery) {
                MetricTile(label: "Recovery", value: "\(Int(pillars.recovery.score.rounded()))", fraction: pillars.recovery.score / 100, tone: .recovery)
            }
            metricTileButton("Sleep", "35%",
                "Last night's duration and quality vs your ~8h need, plus recent sleep debt and consistency.",
                pillars.sleep) {
                MetricTile(label: "Sleep", value: "\(Int(pillars.sleep.score.rounded()))", fraction: pillars.sleep.score / 100, tone: .sleep)
            }
        }
    }

    private func metricTileButton(_ name: String, _ weight: String, _ description: String, _ pillar: PillarScore,
                                   @ViewBuilder tile: () -> MetricTile) -> some View {
        Button {
            pillarInfo = PillarInfo(name: name, weight: weight, description: description, pillar: pillar)
        } label: {
            tile()
        }
        .buttonStyle(.plain)
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
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(message).font(.caption2).foregroundStyle(Palette.textSecondary).lineLimit(2)
            Spacer(minLength: 4)
            InfoBadge(title: infoTitle, message: infoMessage)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.22), lineWidth: 1))
    }

    /// Loads the 7-day readiness history for the sparkline; failures hide it silently.
    private func loadRecent() async {
        guard let client = settings.makeClient() else { return }
        recent = (try? await client.getHistory(days: 7).data) ?? []
    }

    /// Loads the latest HRV / RHR / sleep duration for the hero card's mini-stat row.
    private func loadMiniStats() async {
        guard let client = settings.makeClient() else { return }
        async let body = try? client.getBody(days: 7)
        async let sleep = try? client.getSleep(days: 2)
        if let b = await body {
            hrv = b.daily.filter { $0.type == "hrv_sdnn" }.sorted { $0.date < $1.date }.last?.avg
            rhr = b.daily.filter { $0.type == "resting_heart_rate" }.sorted { $0.date < $1.date }.last?.avg
        }
        if let s = await sleep { sleepHours = s.data.filter { $0.durationHours > 0 }.last?.durationHours }
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
