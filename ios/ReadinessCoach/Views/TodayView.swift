import SwiftUI

/// The decision, why, and what to do about it. Everything else is one tap away.
struct TodayView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var showAsk = false
    @State private var showHistory = false
    @State private var pillarInfo: PillarInfo?
    @State private var healthStatus: HealthKitService.AccessStatus?
    @State private var healthRequestError: String?

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)

                    StatusLine(items: statusItems, onHealthAction: healthAction)

                    if let today = sync.today {
                        content(today)
                    } else if sync.isLoadingToday || sync.isSyncing {
                        loading
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
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let error = sync.errorMessage {
                        ErrorCard(message: error) { Task { await sync.syncNow(settings) } }
                    }

                    syncDetail
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .refreshable { await sync.syncNow(settings) }
            .screenBackground()
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
                    }
                    .accessibilityLabel("Profile and settings")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if sync.today != nil {
                    askButton
                }
            }
            .navigationDestination(isPresented: $showHistory) { TrendsView() }
            .sheet(isPresented: $showAsk) {
                if let today = sync.today { AskCoachView(today: today) }
            }
            .sheet(item: $pillarInfo) { PillarDetailSheet(info: $0) }
            .alert("Health access", isPresented: Binding(
                get: { healthRequestError != nil },
                set: { if !$0 { healthRequestError = nil } }
            )) {
                Button("OK", role: .cancel) { healthRequestError = nil }
            } message: {
                Text(healthRequestError ?? "")
            }
            .task { healthStatus = await health.accessStatus() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { healthStatus = await health.accessStatus() } }
            }
            .onChange(of: sync.lastSyncSummary) { _, _ in
                Task { healthStatus = await health.accessStatus() }
            }
        }
    }

    @ViewBuilder
    private func content(_ today: TodayDTO) -> some View {
        DecisionBlock(today: today) { showHistory = true }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "What's driving it")
                Spacer()
                Menu {
                    ForEach(Pillar.allCases) { pillar in
                        Button(pillar.title) {
                            pillarInfo = PillarInfo(
                                name: pillar.title, weight: "\(pillar.weightPercent)%",
                                description: pillar.summary, pillar: pillar.score(in: today.pillars)
                            )
                        }
                    }
                } label: {
                    if typeSize.isAccessibilitySize {
                        Image(systemName: "info.circle")
                            .font(.body)
                            .frame(minWidth: 44, minHeight: 44)
                    } else {
                        Label("Details", systemImage: "info.circle")
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                }
                .accessibilityLabel("All scoring drivers")
            }
            PillarBreakdown(pillars: today.pillars) { pillar in
                tabs.go(to: AppTab(pillar))
            }
        }

        advisor(today.advisor)
    }

    private var loading: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading today…")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func advisor(_ note: AdvisorNote) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Coach")
            VStack(alignment: .leading, spacing: 14) {
                Text(note.prescription)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !note.why.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(note.why, id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle()
                                    .fill(Palette.textTertiary)
                                    .frame(width: 4, height: 4)
                                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                                Text(line)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Text("If ignored: \(note.ifIgnored)")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private var askButton: some View {
        Button { showAsk = true } label: {
            Label("Ask the coach", systemImage: "bubble.left.and.text.bubble.right")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .primaryAction()
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Palette.canvas.opacity(0.92))
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
                    healthRequestError = error.localizedDescription
                }
            }
        } else if let url = URL(string: "x-apple-health://") {
            openURL(url)
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
