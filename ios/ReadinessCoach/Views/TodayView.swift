import SwiftUI

/// The decision, why, and what to do about it: the readiness head, three pillar
/// gauges, the plan and the vitals, open on the canvas. Everything else is one
/// tap away.
struct TodayView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var coachRequest: CoachRequest?
    @State private var showHistoryAfterCoach = false
    @State private var showHistory = false
    @Namespace private var coachZoom
    @State private var showScoringDrivers = false
    @State private var healthStatus: HealthKitService.AccessStatus?
    @State private var healthRequestError: HealthAccessMessage?
    @State private var refreshCount = 0
    @State private var pillarJumps = 0

    private let health = HealthKitService()

    private var statusItems: [StatusItem] {
        StatusLineModel.items(.init(
            freshness: sync.freshness(using: settings),
            today: sync.today,
            healthStatus: healthStatus,
            healthSyncFailed: sync.healthSyncFailed,
            healthSyncSucceeded: sync.healthSyncSucceeded,
            uploadFailed: sync.healthUploadFailed
        ))
    }

    private func perfTodayContentShown() {
        PerfSignpost.endLaunchIfNeeded()
        PerfSignpost.endTabSwitchIfNeeded(tab: "today")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    StatusLine(items: statusItems, onHealthAction: healthAction)

                    if let today = sync.today {
                        content(today)
                    } else if sync.isSyncing {
                        TodaySkeleton()
                    } else {
                        ContentUnavailableCompat(
                            title: "No readiness yet",
                            message: "Sync your Health data to compute today's score.",
                            systemImage: "sun.max"
                        )
                        .frame(maxWidth: .infinity)
                    }

                    if sync.today == nil {
                        Button { showHistory = true } label: {
                            Label("Readiness history", systemImage: "chart.bar")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.accent)
                                .frame(maxWidth: .infinity, minHeight: Space.target)
                        }
                    }

                    if let error = sync.todayError {
                        InlineNotice(
                            title: "Couldn't refresh",
                            message: error,
                            actionTitle: "Retry",
                            action: { Task { await refresh() } }
                        )
                    }

                    syncDetail
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .refreshable { await refresh() }
            .screenBackground()
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if sync.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(sync.isSyncing)
                    .accessibilityLabel("Sync now")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Text(initials)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Palette.canvas)
                            .frame(width: 30, height: 30)
                            .background(Palette.accent, in: Circle())
                            .frame(minWidth: Space.target, minHeight: Space.target)
                    }
                    .accessibilityLabel("Profile and settings")
                }
            }
            .sensoryFeedback(.success, trigger: refreshCount)
            .sensoryFeedback(.selection, trigger: pillarJumps)
            .navigationDestination(isPresented: $showHistory) { TrendsView() }
            .sheet(item: $coachRequest, onDismiss: {
                // Presenting while a sheet is still dismissing silently fails,
                // so history waits for the dismissal to finish.
                if showHistoryAfterCoach {
                    showHistoryAfterCoach = false
                    showHistory = true
                }
            }) { request in
                CoachView(today: request.today, focus: request.focus, autoAsk: request.autoAsk) {
                    showHistoryAfterCoach = true
                    coachRequest = nil
                }
                .modifier(CoachZoomDestination(
                    id: request.focus, namespace: coachZoom,
                    enabled: request.fromNumber && !reduceMotion
                ))
            }
            .sheet(isPresented: $showScoringDrivers) {
                if let today = sync.today { ScoringDriversSheet(pillars: today.pillars) }
            }
            .sheet(item: $healthRequestError) { error in
                MessageSheet(
                    title: "Health access",
                    message: error.message,
                    systemImage: "heart.text.square",
                    tone: .danger,
                    context: "Health connection"
                )
            }
            .task { healthStatus = await health.accessStatus() }
            .onAppear { if sync.today != nil { perfTodayContentShown() } }
            .onChange(of: sync.today != nil) { _, hasToday in
                if hasToday { perfTodayContentShown() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { healthStatus = await health.accessStatus() } }
            }
            .onChange(of: sync.lastSyncSummary) { _, _ in
                Task { healthStatus = await health.accessStatus() }
            }
        }
    }

    /// A user-started refresh (pull, toolbar, retry) buzzes only when it fully
    /// succeeded. Background and foreground syncs don't buzz.
    private func refresh() async {
        if await sync.syncNow(settings) == .succeeded { refreshCount += 1 }
    }

    @ViewBuilder
    private func content(_ today: TodayDTO) -> some View {
        DecisionBlock(today: today) {
            pillarJumps += 1
            coachRequest = CoachRequest(
                today: today, focus: .readiness,
                autoAsk: CoachPrompts.autoQuestion(for: .readiness, today: today),
                fromNumber: true
            )
        }
        .modifier(CoachZoomSource(id: .readiness, namespace: coachZoom, enabled: !reduceMotion))

        CoachCard(today: today) { question in
            coachRequest = CoachRequest(today: today, focus: .readiness, autoAsk: question, fromNumber: false)
        }

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Score breakdown")
                    .font(Typeface.sectionTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { showScoringDrivers = true } label: {
                    if typeSize.isAccessibilitySize {
                        Image(systemName: "info.circle")
                            .font(.body)
                            .frame(minWidth: Space.target, minHeight: Space.target)
                    } else {
                        Label("Drivers", systemImage: "info.circle")
                            .font(.subheadline)
                            .frame(minHeight: Space.target)
                    }
                }
                .foregroundStyle(Palette.textSecondary)
                .accessibilityLabel("All scoring drivers")
            }
            PillarGaugeRow(
                pillars: today.pillars,
                open: { pillar in
                    pillarJumps += 1
                    coachRequest = CoachRequest(
                        today: today, focus: .pillar(pillar),
                        autoAsk: CoachPrompts.autoQuestion(for: .pillar(pillar), today: today),
                        fromNumber: true
                    )
                },
                zoom: (coachZoom, !reduceMotion)
            )
        }

        TodayPlanSection(note: today.advisor)

        if let vitals = MetricComparison.all(from: today.baselines) {
            VitalsSection(comparisons: vitals)
        }
    }

    @ViewBuilder
    private var syncDetail: some View {
        if let count = sync.uploadingCount {
            Label("Uploading \(count) samples…", systemImage: "arrow.up.circle")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
        } else if let detail = SyncFreshness.detailLine(
            sync.freshness(using: settings),
            settings: settings,
            summary: sync.lastSyncSummary,
            uploadError: sync.lastUploadError
        ) {
            Text(detail)
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var initials: String {
        let name = settings.appleDisplayName?.trimmingCharacters(in: .whitespaces) ?? ""
        if !name.isEmpty {
            let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
            return String(parts).uppercased()
        }
        let id = settings.userId
        return id.isEmpty ? "RC" : String(id.prefix(2)).uppercased()
    }

    private func healthAction() {
        if healthStatus == .needsPermission {
            Task {
                do {
                    try await health.requestAuthorization()
                    healthStatus = await health.accessStatus()
                    await sync.syncNow(settings)
                } catch {
                    healthRequestError = HealthAccessMessage(message: error.localizedDescription)
                }
            }
        } else if let url = URL(string: "x-apple-health://") {
            openURL(url)
        }
    }
}

/// One opening of the coach sheet. `fromNumber` is true when a score or ring
/// was tapped, which is when the number zooms into the coach header.
private struct CoachRequest: Identifiable {
    let id = UUID()
    /// Frozen at the tap so a refresh cannot change the day mid-conversation.
    let today: TodayDTO
    let focus: CoachFocus
    let autoAsk: String?
    let fromNumber: Bool
}

private struct HealthAccessMessage: Identifiable {
    let id = UUID()
    let message: String
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
                .foregroundStyle(Palette.textTertiary)
            Text(title).font(.headline).foregroundStyle(Palette.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }
}
