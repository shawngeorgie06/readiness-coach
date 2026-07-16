import SwiftUI

/// You tab — matches the Aether prototype's Profile panel: screen-head, a profile
/// header card, the daily-readiness preference, and an entry to connection/data settings.
struct YouView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService
    @State private var notificationDenied = false
    @State private var showSettings = false
    private let notifications = NotificationService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    profileCard
                    preferencesCard
                    accountCard
                    Text("Readiness Coach · \(AppBuild.label)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .accessibilityIdentifier("app-build-label")
                }
                .padding()
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "You")
                Text("Profile").font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
        }
    }

    private var profileCard: some View {
        HStack(spacing: 14) {
            Text(initials)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.accent)
                .frame(width: 56, height: 56)
                .background(Palette.accent.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("Readiness Coach").font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                Text(AppBuild.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                Text(settings.userId.isEmpty ? "Not configured" : settings.userId)
                    .font(.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                HStack(spacing: 8) {
                    Pill(sync.today == nil ? "Offline" : "Synced", tone: sync.today == nil ? .warn : .good)
                    if let synced = settings.lastRefreshRelativeText {
                        Text(synced).font(.caption2).foregroundStyle(Palette.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var initials: String {
        let id = settings.userId
        return id.isEmpty ? "RC" : String(id.prefix(2)).uppercased()
    }

    // MARK: - Preferences

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Preferences")
            Toggle(isOn: notificationBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily readiness").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                    Text("A morning notification with today's call")
                        .font(.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            .tint(Palette.accent)
            if settings.notificationsEnabled {
                Divider().overlay(Palette.strokeSoft)
                DatePicker("Time", selection: notificationTime, displayedComponents: .hourAndMinute)
                    .font(.system(size: 15, weight: .semibold))
                    .tint(Palette.accent)
            }
            if notificationDenied {
                Text("Turn on notifications for Readiness Coach in iOS Settings to use this.")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Account

    private var accountCard: some View {
        VStack(spacing: 0) {
            AetherListRow(systemImage: "arrow.triangle.2.circlepath", tone: .accent,
                          title: "Sync now", subtitle: settings.lastRefreshRelativeText.map { "Last synced \($0)" } ?? "Never synced") {
                if sync.isSyncing { ProgressView() } else { chevron }
            }
            .contentShape(Rectangle())
            .onTapGesture { Task { await sync.syncNow(settings) } }
            Divider().overlay(Palette.strokeSoft).padding(.leading, 14)
            Button { showSettings = true } label: {
                AetherListRow(systemImage: "gearshape.fill", tone: .neutral,
                              title: "Connection & data", subtitle: "Server, token, privacy") { chevron }
            }.buttonStyle(.plain)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.strokeSoft, lineWidth: 1))
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.textTertiary)
    }

    // MARK: - Notification bindings (mirrors SettingsView)

    private var notificationBinding: Binding<Bool> {
        Binding(
            get: { settings.notificationsEnabled },
            set: { isOn in
                if isOn {
                    Task {
                        let granted = await notifications.requestAuthorization()
                        if granted {
                            settings.notificationsEnabled = true
                            notificationDenied = false
                            BackgroundRefreshService.schedule(for: settings)
                        } else {
                            settings.notificationsEnabled = false
                            notificationDenied = true
                        }
                    }
                } else {
                    settings.notificationsEnabled = false
                    notificationDenied = false
                    BackgroundRefreshService.cancel()
                    notifications.cancelPending()
                }
            }
        )
    }

    private var notificationTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: settings.notificationHour,
                                      minute: settings.notificationMinute, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings.notificationHour = c.hour ?? 7
                settings.notificationMinute = c.minute ?? 0
                BackgroundRefreshService.schedule(for: settings)
            }
        )
    }
}
