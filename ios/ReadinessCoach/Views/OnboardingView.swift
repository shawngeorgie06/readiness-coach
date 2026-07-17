import SwiftUI

/// First-run flow: confirm the pre-filled API connection, request HealthKit
/// access, then run the first sync. The backend URL and (on this machine) the
/// token are pre-filled, so the happy path is "Allow Health → Start & sync".
struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService

    @State private var isRequestingHealth = false
    @State private var healthGranted = false
    @State private var error: String?
    @State private var isFinishing = false
    @State private var isTesting = false
    @State private var testOK: Bool?
    @State private var showAdvanced = false

    private let health = HealthKitService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    SectionCard(title: "1 · Connect") {
                        if settings.isConfigured {
                            Label("Connected to your backend", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text("Add your API token under Advanced to connect.")
                                .font(.subheadline)
                        }
                        DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                            LabeledField(label: "API URL", text: $settings.apiBaseURL, keyboard: .default)
                            LabeledField(label: "API token", text: $settings.apiToken, secure: true)
                            LabeledField(label: "User ID", text: $settings.userId)
                            Button {
                                Task { await testConnection() }
                            } label: {
                                HStack {
                                    Image(systemName: testIcon)
                                    Text(isTesting ? "Testing…" : "Test connection")
                                    Spacer()
                                    if isTesting { ProgressView() }
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isTesting || !settings.isConfigured)
                            .padding(.top, 4)
                        }
                        .font(.subheadline)
                    }

                    SectionCard(title: "2 · Allow Health access") {
                        Text("Readiness Coach reads heart rate, resting HR, HRV, sleep, and workouts. It never writes to Health.")
                            .font(.subheadline)
                        Button {
                            Task { await requestHealth() }
                        } label: {
                            HStack {
                                Image(systemName: healthGranted ? "checkmark.circle.fill" : "heart.text.square")
                                Text(healthGranted ? "Health access requested" : "Allow Health access")
                                Spacer()
                                if isRequestingHealth { ProgressView() }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRequestingHealth || !settings.isConfigured)
                    }

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }

                    Button {
                        Task { await finish() }
                    } label: {
                        if isFinishing {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Start & sync").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!settings.isConfigured || isFinishing)
                }
                .padding()
            }
            .navigationTitle("Welcome")
            .onAppear { settings.ensureUserId() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Readiness Coach")
                .font(.largeTitle.bold())
            Text("A strict, evidence-backed readiness advisor. The score locks the decision; the coach only explains it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var testIcon: String {
        switch testOK {
        case .some(true): return "checkmark.circle.fill"
        case .some(false): return "xmark.circle.fill"
        case nil: return "bolt.horizontal.circle"
        }
    }

    private func testConnection() async {
        guard let client = settings.makeClient() else { return }
        isTesting = true; error = nil
        defer { isTesting = false }
        do { try await client.testConnection(); testOK = true }
        catch {
            testOK = false
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func requestHealth() async {
        isRequestingHealth = true
        error = nil
        defer { isRequestingHealth = false }
        do {
            try await health.requestAuthorization()
            healthGranted = true
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func finish() async {
        guard settings.isConfigured else { return }
        isFinishing = true
        defer { isFinishing = false }
        settings.ensureUserId()
        await sync.syncNow(settings)
        if sync.errorMessage == nil {
            settings.hasCompletedOnboarding = true
        } else {
            error = sync.errorMessage
        }
    }
}
