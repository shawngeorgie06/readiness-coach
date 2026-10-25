import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var showDeleteAccountConfirm = false
    @State private var showResetConfirm = false
    @State private var actionMessage: String?
    @State private var isDeleting = false
    @State private var notificationDenied = false
    @State private var isRequestingHealth = false
    @State private var healthStatus: HealthKitService.AccessStatus?
    private let notifications = NotificationService()
    private let health = HealthKitService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                accountSection
                syncSection
                healthSection
                notificationSection
                connectionSection
                OpenSection("About") {
                    SettingsRow {
                        Text("Version").foregroundStyle(Palette.textSecondary)
                        Spacer(minLength: 8)
                        Text(AppBuild.label).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
                privacySection
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle("Settings")
        .screenBackground()
        .task { await refreshHealthStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshHealthStatus() } }
        }
        .onChange(of: actionMessage) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
        .sheet(isPresented: $showDeleteAccountConfirm) {
            ConfirmationSheet(
                title: "Delete account data?",
                message: "Delete all account data on the server? This cannot be undone.\n\nThis permanently erases your user and all synced health samples, workouts, scores, and advisor notes.",
                systemImage: "person.crop.circle.badge.minus",
                actionTitle: "Delete account data"
            ) {
                Task { await deleteAccount() }
            }
        }
        .sheet(isPresented: $showResetConfirm) {
            ConfirmationSheet(
                title: "Clear local settings?",
                message: "Clears the saved account and connection settings on this device and returns you to setup. Daily readiness notifications will be cancelled.\n\nAccount data on the server is kept.",
                systemImage: "iphone.slash",
                actionTitle: "Clear settings"
            ) {
                settings.clearLocalSettings()
                StoreActivation.reset(store)
                notifications.cancelDaily()
                actionMessage = "Local settings cleared."
            }
        }
    }

    // MARK: Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Palette.surfaceHi)
                    if let initials = Self.initials(settings.isSignedIn ? settings.appleDisplayName : nil) {
                        Text(initials)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Palette.textPrimary)
                    } else {
                        Image(systemName: settings.isConfigured ? "person.fill" : "person.slash")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(accountTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Palette.textPrimary)
                    HStack(spacing: 6) {
                        if settings.isSignedIn || settings.isConfigured {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Palette.success)
                                .accessibilityHidden(true)
                        }
                        Text(accountStatus)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .font(.subheadline)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            if settings.isSignedIn {
                Hairline()
                Button(role: .destructive) {
                    settings.signOut()
                    StoreActivation.reset(store)
                } label: {
                    SettingsRow {
                        Text("Sign out")
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.danger)
                    }
                }
                .buttonStyle(.plain)
            } else if settings.isConfigured {
                Hairline()
                SettingsRow {
                    Text("User ID").foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 8)
                    Text(settings.userId)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var accountTitle: String {
        if settings.isSignedIn { return settings.appleDisplayName ?? "Apple ID" }
        return settings.isConfigured ? "Connected" : "Not connected"
    }

    private var accountStatus: String {
        if settings.isSignedIn { return "Signed in" }
        return settings.isConfigured ? "Via API token" : "Add your API URL and token under Connection."
    }

    /// Up to two initials from a display name; nil when there's no name.
    static func initials(_ name: String?) -> String? {
        guard let name else { return nil }
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
        return letters.isEmpty ? nil : String(letters).uppercased()
    }

    // MARK: Sync

    private var syncSection: some View {
        OpenSection("Sync") {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    Task { await sync.syncNow(settings) }
                } label: {
                    SettingsRow {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Palette.accent)
                            .accessibilityHidden(true)
                        Text(sync.isSyncing ? "Syncing…" : "Sync now")
                            .foregroundStyle(Palette.textPrimary)
                        Spacer(minLength: 8)
                        if sync.isSyncing { ProgressView() }
                    }
                }
                .buttonStyle(.plain)
                .disabled(sync.isSyncing)

                if let last = settings.lastSyncAt {
                    // This is the resume point, not the last attempt: after a
                    // partial upload it sits at the oldest data still pending.
                    Hairline()
                    SettingsRow {
                        Text("Health synced through").foregroundStyle(Palette.textSecondary)
                        Spacer(minLength: 8)
                        Text(last.formatted(date: .abbreviated, time: .shortened))
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let summary = sync.lastSyncSummary {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                if let uploadError = sync.lastUploadError {
                    Label(SyncFreshness.detailLine(.fresh, settings: settings, summary: nil, uploadError: uploadError) ?? uploadError,
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
            }
        }
    }

    // MARK: Health

    private var healthSection: some View {
        OpenSection("Health") {
            VStack(alignment: .leading, spacing: 8) {
                switch healthStatus {
                case .connected:
                    SettingsRow {
                        Image(systemName: "heart.text.square")
                            .foregroundStyle(Palette.recovery)
                            .accessibilityHidden(true)
                        Text("Health permission request completed")
                            .foregroundStyle(Palette.textPrimary)
                    }
                    Text("iOS does not tell apps whether read access was granted or denied. If data is missing, check your Health permissions.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .needsPermission, .none:
                    Button {
                        Task { await requestHealth() }
                    } label: {
                        SettingsRow {
                            Image(systemName: "heart.text.square")
                                .foregroundStyle(Palette.accent)
                                .accessibilityHidden(true)
                            Text("Allow Health access")
                                .foregroundStyle(Palette.textPrimary)
                            Spacer(minLength: 8)
                            if isRequestingHealth { ProgressView() }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequestingHealth)
                case .unavailable:
                    Text("Health data is not available on this device.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(minHeight: Space.target, alignment: .leading)
                }
                if let summary = sync.lastSyncSummary, summary.hasPrefix("Couldn't read Health") {
                    Label(summary, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Reads heart rate, resting HR, HRV, sleep, and workouts. Never writes to Health. Manage permissions in iOS Settings → Health → Data Access & Devices.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Notifications

    private var notificationSection: some View {
        OpenSection("Daily readiness") {
            VStack(alignment: .leading, spacing: 0) {
                Toggle("Morning notification", isOn: Binding(
                    get: { settings.notificationsEnabled },
                    set: { isOn in
                        if isOn {
                            Task {
                                let granted = await notifications.requestAuthorization()
                                if granted {
                                    settings.notificationsEnabled = true
                                    notificationDenied = false
                                    notifications.refreshDailySchedule(settings: settings, latest: sync.today)
                                } else {
                                    settings.notificationsEnabled = false
                                    notificationDenied = true
                                }
                            }
                        } else {
                            settings.notificationsEnabled = false
                            notificationDenied = false
                            notifications.cancelDaily()
                        }
                    }
                ))
                .tint(Palette.accent)
                .frame(minHeight: Space.target)

                if settings.notificationsEnabled {
                    Hairline()
                    DatePicker("Time", selection: notificationTime, displayedComponents: .hourAndMinute)
                        .frame(minHeight: Space.target)
                }

                if notificationDenied {
                    Label("Turn on notifications for Readiness Coach in iOS Settings to use this.",
                          systemImage: "bell.slash")
                        .font(.footnote)
                        .foregroundStyle(Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }

                Text("Delivered daily at your chosen time. Shows your latest synced score — open the app for today's fresh number.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: Connection

    private var connectionSection: some View {
        OpenSection("Connection") {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledField(label: "API URL", text: $settings.apiBaseURL, keyboard: .default)
                    LabeledField(label: "API token", text: $settings.apiToken, secure: true)
                    LabeledField(label: "User ID", text: $settings.userId)
                }
                .padding(.top, 8)
            } label: {
                Text("API URL, token and user ID")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(minHeight: Space.target, alignment: .leading)
            }
            .tint(Palette.textSecondary)
        }
    }

    // MARK: Data & privacy

    private var privacySection: some View {
        OpenSection("Data & privacy") {
            VStack(alignment: .leading, spacing: 0) {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    SettingsRow {
                        Text("Delete local settings").foregroundStyle(Palette.danger)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
                Hairline()
                Button(role: .destructive) {
                    showDeleteAccountConfirm = true
                } label: {
                    SettingsRow {
                        Text(isDeleting ? "Deleting account data…" : "Delete account data")
                            .foregroundStyle(Palette.danger)
                        Spacer(minLength: 8)
                        if isDeleting { ProgressView() }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
                Text("Account deletion permanently erases your user and all synced health samples, workouts, scores, and advisor notes on the server.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                if let actionMessage {
                    Label(actionMessage, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
            }
        }
    }

    private func deleteAccount() async {
        guard !isDeleting else { return }
        guard let client = settings.makeClient() else {
            actionMessage = APIError.notConfigured.localizedDescription
            return
        }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await client.deleteAccount()
            settings.clearLocalSettings()
            StoreActivation.reset(store)
            notifications.cancelDaily()
            actionMessage = "Account data deleted."
        } catch {
            actionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func refreshHealthStatus() async {
        healthStatus = await health.accessStatus()
    }

    private func requestHealth() async {
        isRequestingHealth = true
        defer { isRequestingHealth = false }
        do {
            try await health.requestAuthorization()
            await refreshHealthStatus()
        } catch {
            actionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Bridges the stored hour/minute to a `DatePicker` Date, rescheduling on change.
    private var notificationTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: settings.notificationHour,
                    minute: settings.notificationMinute,
                    second: 0, of: Date()
                ) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings.notificationHour = c.hour ?? 7
                settings.notificationMinute = c.minute ?? 0
                notifications.refreshDailySchedule(settings: settings, latest: sync.today)
            }
        )
    }
}

/// One settings line: at least 44pt tall, content laid out horizontally.
struct SettingsRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 12) { content() }
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: Space.target, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
    }
}

struct LabeledField: View {
    let label: String
    @Binding var text: String
    /// Secret fields (API token) mask by default via SecureField and expose a
    /// reveal (eye) toggle. Paste works in both states — and the TextField
    /// fallback guarantees paste even if SecureField's context menu misbehaves.
    /// `.textContentType(.none)` avoids the AutoFill strong-password overlay
    /// that used to block manual paste.
    var secure = false
    var keyboard: UIKeyboardType = .default
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)
            HStack(spacing: 8) {
                Group {
                    if secure && !revealed {
                        SecureField(label, text: $text)
                    } else {
                        TextField(label, text: $text)
                            .keyboardType(keyboard)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.none)
                .font(secure || keyboard == .URL ? .body.monospaced() : .body)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityLabel(label)

                if secure {
                    Button {
                        revealed.toggle()
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .foregroundStyle(Palette.textSecondary)
                            .frame(minWidth: Space.target, minHeight: Space.target)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealed ? "Hide \(label)" : "Show \(label)")
                }
            }
            .frame(minHeight: Space.target)
            Hairline()
        }
    }
}
