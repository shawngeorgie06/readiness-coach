import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService

    @State private var showDeleteAccountConfirm = false
    @State private var showResetConfirm = false
    @State private var actionMessage: String?
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledField(label: "API URL", text: $settings.apiBaseURL, keyboard: .URL)
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
}

struct LabeledField: View {
    let label: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Group {
                if secure {
                    SecureField(label, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } else {
                    TextField(label, text: $text)
                        .keyboardType(keyboard)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
        }
    }
}
