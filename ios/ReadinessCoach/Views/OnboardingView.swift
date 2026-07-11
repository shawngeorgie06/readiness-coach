import SwiftUI

/// First-run flow: explain permissions, request HealthKit access, save API
/// settings, then run the first sync.
struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService

    @State private var isRequestingHealth = false
    @State private var healthGranted = false
    @State private var error: String?
    @State private var isFinishing = false

    private let health = HealthKitService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    SectionCard(title: "1 · Connect your API") {
                        LabeledField(label: "API URL", text: $settings.apiBaseURL, keyboard: .URL)
                        LabeledField(label: "API token", text: $settings.apiToken, secure: true)
                        LabeledField(label: "User ID", text: $settings.userId)
                        Text("The score is computed on your API. Point this at your backend and use a private bearer token.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        .disabled(isRequestingHealth)
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
