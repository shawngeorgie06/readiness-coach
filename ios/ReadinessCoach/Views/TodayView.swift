import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.openURL) private var openURL

    @State private var showAsk = false
    @State private var showSettings = false
    @State private var pillarInfo: PillarInfo?
    @State private var healthStatus: HealthKitService.AccessStatus?
    @State private var recent: [ReadinessPoint] = []
    @State private var hrv: Double?
    @State private var rhr: Double?
    @State private var sleepHours: Double?
    @State private var strain: Double?
    @State private var strainAvg: Double?

    private let health = HealthKitService()

    private var freshness: DataFreshness {
        sync.freshness(using: settings)
    }

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
            // Today has unique wide chrome (hero + ring shadows). Pin width and
            // continuously clamp horizontal UIScrollView offset — other tabs don't need this.
            WidthPinnedVerticalScroll(onRefresh: {
                await sync.syncNow(settings)
                await loadRecent()
                await loadMiniStats()
            }) {
                VStack(spacing: 16) {
                    header
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
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAsk) { NavigationStack { AskCoachView() } }
            .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
            .sheet(item: $pillarInfo) { PillarDetailSheet(info: $0) }
            .task {
                healthStatus = await health.accessStatus()
                await loadRecent()
                await loadMiniStats()
            }
            .onChange(of: sync.lastSyncSummary) { _, _ in
                Task { healthStatus = await health.accessStatus() }
            }
        }
    }

    /// Big in-content header matching the prototype's screen-head (date + "Today" + actions).
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: Date().formatted(.dateTime.weekday(.wide).month().day()))
                Text("Today")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
            HStack(spacing: 8) {
                iconButton("gearshape") { showSettings = true }
                iconButton("bubble.left.and.text.bubble.right") { showAsk = true }
                iconButton(sync.isSyncing ? "hourglass" : "arrow.clockwise") {
                    Task { await sync.syncNow(settings); await loadRecent(); await loadMiniStats() }
                }
            }
        }
    }

    private func iconButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 40, height: 40)
                .background(Palette.surface, in: Circle())
                .overlay(Circle().strokeBorder(Palette.strokeSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(sync.isSyncing && system == "hourglass")
    }

    @ViewBuilder
    private func content(_ today: TodayDTO) -> some View {
        freshnessBanners

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
                    Text("Calibrated from sleep, HRV & load")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Pill(today.decision.title, tone: pillTone(today.decision))
            }
            ReadinessRing(readiness: today.readiness, decision: today.decision)
                .frame(maxWidth: .infinity)
            if today.isSleepPending {
                Label("Showing last night — you haven't slept yet tonight", systemImage: "moon.zzz")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            Text(today.decision.meaning).font(.system(.body, design: .rounded))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                miniStat("HRV", hrv.map { "\(Int($0.rounded()))" } ?? "—", "ms")
                miniStat("RHR", rhr.map { "\(Int($0.rounded()))" } ?? "—", "bpm")
                miniStat("Sleep", today.isSleepPending ? "Not yet" : (sleepHours.map { DurationFormat.short($0) } ?? "—"), nil)
            }
        }
        .frame(maxWidth: .infinity)
        .heroCard()

        if let count = sync.uploadingCount {
            Label("Uploading \(count) samples…", systemImage: "arrow.up.circle")
                .font(.caption2).foregroundStyle(Palette.textSecondary)
        } else if let detail = SyncFreshness.detailLine(freshness, settings: settings, summary: sync.lastSyncSummary) {
            Text(detail)
                .font(.caption2)
                .foregroundStyle(freshness == .offline ? Palette.warn : Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        metricTiles(today.pillars)
        if recent.count > 1 {
            Button {
                tabs.go(to: .insights)
            } label: {
                SectionCard(title: "Readiness trend") {
                    ReadinessSparkline(points: recent)
                    HStack(spacing: 4) {
                        Text("Last \(recent.count) days · tap for Insights detail")
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the Insights tab")
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
    private func miniStat(_ label: String, _ value: String, _ unit: String?) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(Palette.textPrimary)
                if let unit { Text(unit).font(.system(size: 11)).foregroundStyle(Palette.textSecondary) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 2×2 grid without LazyVGrid (avoids occasional width overflows in ScrollView).
    private func metricTiles(_ pillars: Pillars) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                metricTileButton("Strain", "training load",
                    StrainExplain.scaleBlurb,
                    PillarScore(score: min(100, (strain ?? 0) / 21 * 100),
                                drivers: [Driver(text: strain.map { String(format: "Strain %.1f / 21" , $0) } ?? "No recent workout",
                                                 detail: strainDelta.map { "\($0). \(StrainExplain.shortBlurb)" }
                                                    ?? "\(StrainExplain.shortBlurb) Sync workouts from Apple Health to populate strain.")])) {
                    MetricTile(label: "Strain",
                               value: strain.map { fmt1($0) } ?? "—", unit: "/21",
                               delta: strainDelta,
                               fraction: (strain ?? 0) / 21, tone: .strain)
                }
                metricTileButton("Recovery", "40%",
                    "HRV and resting heart rate vs your 30-day baseline — the strongest readiness signal.",
                    pillars.recovery) {
                    MetricTile(label: "Recovery", value: "\(Int(pillars.recovery.score.rounded()))",
                               delta: "40% of readiness", fraction: pillars.recovery.score / 100, tone: .recovery)
                }
            }
            HStack(spacing: 12) {
                metricTileButton("Sleep", "35%",
                    "Last night's duration and quality vs your ~8h need, plus recent sleep debt and consistency.",
                    pillars.sleep,
                    opensSleep: true) {
                    MetricTile(label: "Sleep",
                               value: (sync.today?.isSleepPending ?? false) ? "—" : (sleepHours.map { DurationFormat.short($0) } ?? "—"),
                               delta: (sync.today?.isSleepPending ?? false) ? "Haven't slept yet" : sleepDelta,
                               fraction: (sync.today?.isSleepPending ?? false) ? 0 : (sleepHours ?? 0) / 8, tone: .sleep)
                }
                metricTileButton("Load", "25%",
                    "Recent training strain and the acute:chronic ratio — how hard you've pushed lately vs your norm.",
                    pillars.load) {
                    MetricTile(label: "Load", value: "\(Int(pillars.load.score.rounded()))",
                               delta: "25% of readiness", fraction: pillars.load.score / 100, tone: .strain)
                }
            }
        }
    }

    private func fmt1(_ v: Double) -> String { String(format: "%.1f", v) }
    private var strainDelta: String? {
        guard let strain, let strainAvg, strainAvg > 0 else { return nil }
        return String(format: "%+.1f vs 7d avg", strain - strainAvg)
    }
    private var sleepDelta: String? {
        guard let sleepHours else { return nil }
        let vsNeed = sleepHours - 8
        let sign = vsNeed >= 0 ? "+" : "−"
        return "\(sign)\(DurationFormat.short(abs(vsNeed))) vs 8h need"
    }

    private func metricTileButton(_ name: String, _ weight: String, _ description: String, _ pillar: PillarScore,
                                   opensSleep: Bool = false,
                                   @ViewBuilder tile: () -> MetricTile) -> some View {
        Button {
            if opensSleep {
                tabs.go(to: .sleep)
            } else {
                pillarInfo = PillarInfo(name: name, weight: weight, description: description, pillar: pillar)
            }
        } label: {
            tile()
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityHint(opensSleep ? "Opens the Sleep tab" : "Shows more about \(name)")
    }

    private func advisor(_ note: AdvisorNote) -> some View {
        SectionCard(title: "Strict advisor") {
            if !note.why.isEmpty {
                ForEach(note.why, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle")
                        Text(line)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Text(note.prescription)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Text("If ignored: \(note.ifIgnored)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var freshnessBanners: some View {
        switch freshness {
        case .offline:
            FreshnessBanner(
                title: "Offline",
                message: "Showing your last saved score. Connect to refresh today's readiness.",
                color: Palette.warn,
                icon: "wifi.slash"
            )
        case .stale:
            FreshnessBanner(
                title: "Score may be outdated",
                message: "This readiness ring may not reflect today yet. Pull down or tap sync to refresh.",
                color: Palette.warn,
                icon: "clock.arrow.circlepath"
            )
        case .aging:
            FreshnessBanner(
                title: "Not refreshed recently",
                message: "Background sync runs when Health gets new data, but you can pull to refresh now.",
                color: Palette.textSecondary,
                icon: "arrow.triangle.2.circlepath"
            )
        default:
            EmptyView()
        }

        if healthStatus == .needsPermission || sync.healthSyncFailed {
            FreshnessBanner(
                title: "Health access needed",
                message: "Readiness needs heart rate, HRV, sleep, and workouts from Apple Health.",
                color: Palette.accent,
                icon: "heart.text.square",
                actionTitle: healthStatus == .needsPermission ? "Allow Health access" : "Open Health settings",
                action: {
                    if healthStatus == .needsPermission {
                        Task {
                            try? await health.requestAuthorization()
                            healthStatus = await health.accessStatus()
                            await sync.syncNow(settings)
                        }
                    } else if let url = URL(string: "x-apple-health://") {
                        openURL(url)
                    }
                }
            )
        }
    }

    private func banner(_ title: String, _ message: String, color: Color, icon: String,
                        infoTitle: String, infoMessage: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            InfoBadge(title: infoTitle, message: infoMessage)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        async let train = try? client.getTrain(days: 7)
        if let b = await body {
            hrv = b.daily.filter { $0.type == "hrv_sdnn" }.sorted { $0.date < $1.date }.last?.current
            rhr = b.daily.filter { $0.type == "resting_heart_rate" }.sorted { $0.date < $1.date }.last?.current
        }
        if let s = await sleep { sleepHours = s.data.filter { $0.durationHours > 0 }.last?.durationHours }
        if let t = await train {
            let sorted = t.data.sorted { $0.startAt < $1.startAt }
            strain = sorted.last?.strain
            let all = t.data.map(\.strain)
            strainAvg = all.isEmpty ? nil : all.reduce(0, +) / Double(all.count)
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
