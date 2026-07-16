import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService

    @State private var showDeleteAccountConfirm = false
    @State private var showResetConfirm = false
    @State private var actionMessage: String?
    @State private var isDeleting = false
    @State private var notificationDenied = false
    @State private var isRequestingHealth = false
    @State private var healthRequested = false
    private let notifications = NotificationService()
    private let health = HealthKitService()

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledField(label: "API URL", text: $settings.apiBaseURL, keyboard: .default)
                    LabeledField(label: "API token", text: $settings.apiToken, secure: true)
                    LabeledField(label: "User ID", text: $settings.userId)
                }

                Section("Sync") {
                    Button {
                        Task { await sync.syncNow(settings) }
                    } label: {
                        HStack {
                            Text("Sync now")
                            Spacer()
                            if sync.isSyncing { ProgressView() }
                        }
                    }
                    .disabled(sync.isSyncing)

                    if let last = settings.lastSyncAt {
                        LabeledContent("Last sync", value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let summary = sync.lastSyncSummary {
                        Text(summary).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Health") {
                    Button {
                        Task { await requestHealth() }
                    } label: {
                        HStack {
                            Image(systemName: healthRequested ? "checkmark.circle.fill" : "heart.text.square")
                            Text(healthRequested ? "Health access requested" : "Allow Health access")
                            Spacer()
                            if isRequestingHealth { ProgressView() }
                        }
                    }
                    .disabled(isRequestingHealth)
                    Text("Reads heart rate, resting HR, HRV, sleep, and workouts. Never writes to Health. If you already granted this, manage it in iOS Settings → Health → Data Access & Devices.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Daily readiness") {
                    Toggle("Morning notification", isOn: Binding(
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
                    ))

                    if settings.notificationsEnabled {
                        DatePicker("Time", selection: notificationTime, displayedComponents: .hourAndMinute)
                    }

                    if notificationDenied {
                        Text("Turn on notifications for Readiness Coach in iOS Settings to use this.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Text("Sent in the morning after your data syncs. iOS decides the exact time, so some mornings it may arrive late or not at all.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: AppBuild.label)
                }

                Section("Data & privacy") {
                    Button("Delete local settings", role: .destructive) {
                        showResetConfirm = true
                    }
                    Button("Delete account data", role: .destructive) {
                        showDeleteAccountConfirm = true
                    }
                    Text("Account deletion permanently erases your user and all synced health samples, workouts, scores, and advisor notes on the server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let actionMessage {
                    Section { Text(actionMessage).font(.footnote) }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete all account data on the server? This cannot be undone.",
                isPresented: $showDeleteAccountConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete account data", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Clear local settings on this device?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear settings", role: .destructive) {
                    settings.clearLocalSettings()
                    sync.today = nil
                    actionMessage = "Local settings cleared."
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func deleteAccount() async {
        guard let client = settings.makeClient() else {
            actionMessage = APIError.notConfigured.localizedDescription
            return
        }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await client.deleteAccount()
            settings.clearLocalSettings()
            sync.today = nil
            actionMessage = "Account data deleted."
        } catch {
            actionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func requestHealth() async {
        isRequestingHealth = true
        defer { isRequestingHealth = false }
        do {
            try await health.requestAuthorization()
            healthRequested = true
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
                BackgroundRefreshService.schedule(for: settings)
            }
        )
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
            Text(label).font(.caption).foregroundStyle(.secondary)
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

                if secure {
                    Button {
                        revealed.toggle()
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealed ? "Hide \(label)" : "Show \(label)")
                }
            }
        }
    }
}
