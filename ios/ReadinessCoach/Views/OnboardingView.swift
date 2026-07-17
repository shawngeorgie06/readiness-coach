import AuthenticationServices
import SwiftUI

/// First-run flow: authenticate, request HealthKit access, then run the first sync.
struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService

    @State private var isRequestingHealth = false
    @State private var healthGranted = false
    @State private var error: String?
    @State private var isFinishing = false
    @State private var showAdvanced = false

    private let health = HealthKitService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    SectionCard(title: "1 · Sign in") {
                        if settings.isSignedIn {
                            Label("Signed in with Apple", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            SignInWithAppleButton(.signIn) { request in
                                request.requestedScopes = [.fullName, .email]
                            } onCompletion: { result in
                                Task { await handleSignIn(result) }
                            }
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 48)
                        }
                        Text("Your data is tied to your Apple ID. No token to copy.")
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
                        .disabled(isRequestingHealth || !settings.isSignedIn)
                    }

                    DisclosureGroup("Advanced (developer)", isExpanded: $showAdvanced) {
                        LabeledField(label: "API URL", text: $settings.apiBaseURL, keyboard: .default)
                        LabeledField(label: "API token", text: $settings.apiToken, secure: true)
                        LabeledField(label: "User ID", text: $settings.userId)
                    }
                    .font(.subheadline)

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
                    .disabled(!settings.isSignedIn || isFinishing)
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

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) async {
        error = nil
        switch result {
        case .success(let authorization):
            guard let credential = AppleSignIn.credential(from: authorization) else {
                error = "Could not read your Apple sign-in."
                return
            }
            guard let client = settings.makeClientForAuth() else {
                error = "API URL is not set."
                return
            }
            do {
                let claimUserId = settings.userId.isEmpty ? nil : settings.userId
                let claimToken = settings.apiToken.isEmpty ? nil : settings.apiToken
                let auth = try await client.signInWithApple(
                    identityToken: credential.identityToken,
                    fullName: credential.fullName,
                    claimUserId: claimUserId,
                    claimToken: claimToken
                )
                settings.applyAuth(auth, displayName: credential.fullName)
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        case .failure(let authorizationError):
            if (authorizationError as? ASAuthorizationError)?.code != .canceled {
                error = authorizationError.localizedDescription
            }
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
        guard settings.isSignedIn else { return }
        isFinishing = true
        defer { isFinishing = false }
        await sync.syncNow(settings)
        if sync.errorMessage == nil {
            settings.hasCompletedOnboarding = true
        } else {
            error = sync.errorMessage
        }
    }
}
