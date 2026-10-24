import SwiftUI

/// First-run flow: confirm the pre-filled API connection, request HealthKit
/// access, then run the first sync. The backend URL and (on this machine) the
/// token are pre-filled, so the happy path is "Allow Health → Start & sync".
struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService

    @State private var isRequestingHealth = false
    @State private var healthStatus: HealthKitService.AccessStatus?
    @State private var error: String?
    @State private var isFinishing = false
    @State private var isTesting = false
    @State private var testOK: Bool?
    @State private var showAdvanced = false

    private let health = HealthKitService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    header

                    step(1, "Connect", done: settings.isConfigured) {
                        statusLine(
                            settings.isConfigured ? "Connected to your backend" : "Add your API token under Advanced to connect.",
                            systemImage: settings.isConfigured ? "checkmark.circle.fill" : "link",
                            color: settings.isConfigured ? Palette.success : Palette.textTertiary
                        )
                        DisclosureGroup(isExpanded: $showAdvanced) {
                            VStack(alignment: .leading, spacing: 12) {
                                LabeledField(label: "API URL", text: $settings.apiBaseURL, keyboard: .default)
                                LabeledField(label: "API token", text: $settings.apiToken, secure: true)
                                LabeledField(label: "User ID", text: $settings.userId)
                                Button {
                                    Task { await testConnection() }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: testIcon)
                                            .foregroundStyle(testColor)
                                            .accessibilityHidden(true)
                                        Text(isTesting ? "Testing…" : "Test connection")
                                            .foregroundStyle(Palette.textPrimary)
                                        Spacer(minLength: 8)
                                        if isTesting { ProgressView() }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: Space.target, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(isTesting || !settings.isConfigured)
                                .accessibilityValue(testOK == true ? "Connection works" : testOK == false ? "Connection failed" : "")
                            }
                            .padding(.top, 8)
                        } label: {
                            Text("Advanced")
                                .font(.subheadline)
                                .foregroundStyle(Palette.textSecondary)
                                .frame(minHeight: Space.target, alignment: .leading)
                        }
                        .tint(Palette.textSecondary)
                    }

                    step(2, "Allow Health access", done: healthStatus == .connected) {
                        Text("Readiness Coach reads heart rate, resting HR, HRV, sleep, and workouts. It never writes to Health.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        switch healthStatus {
                        case .connected:
                            statusLine("Health permission request completed", systemImage: "heart.text.square", color: Palette.recovery)
                            Text("iOS does not tell apps whether read access was granted or denied. If data is missing, check your Health permissions.")
                                .font(.footnote)
                                .foregroundStyle(Palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        case .needsPermission, .none:
                            Button {
                                Task { await requestHealth() }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "heart.text.square")
                                        .foregroundStyle(settings.isConfigured ? Palette.accent : Palette.textTertiary)
                                        .accessibilityHidden(true)
                                    Text("Allow Health access")
                                        .foregroundStyle(settings.isConfigured ? Palette.textPrimary : Palette.textTertiary)
                                    Spacer(minLength: 8)
                                    if isRequestingHealth { ProgressView() }
                                }
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: Space.target, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isRequestingHealth || !settings.isConfigured)
                        case .unavailable:
                            Text("Health data is not available on this device.")
                                .font(.subheadline)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your data")
                            .font(Typeface.sectionTitle)
                            .foregroundStyle(Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Health readings sync to the backend you connect above, which computes your scores. You can delete them any time in Settings → Data & privacy.")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let error {
                        InlineNotice(title: "Couldn't continue", message: error)
                    }

                    Button {
                        Task { await finish() }
                    } label: {
                        HStack(spacing: 8) {
                            if isFinishing { ProgressView().tint(Palette.canvas) }
                            Text(isFinishing ? "Syncing…" : "Start & sync")
                        }
                        .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .primaryAction()
                    .disabled(!settings.isConfigured || isFinishing)
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Welcome")
            .onAppear { settings.ensureUserId() }
            .task { healthStatus = await health.accessStatus() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Readiness Coach")
                .font(.largeTitle.weight(.heavy).width(.condensed))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("One score each morning locks the call: Push, Maintain or Recover. The coach only explains it.")
                .font(.title3)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    /// A numbered setup step: a hairline, the step number (a check once done)
    /// and title, then its content on the canvas.
    private func step<Content: View>(_ number: Int, _ title: String, done: Bool,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Hairline()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Group {
                    if done {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Palette.success)
                    } else {
                        Text("\(number)")
                            .font(Typeface.value)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .frame(minWidth: 22, alignment: .leading)
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.textPrimary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(number): \(title)\(done ? ", done" : "")")
            .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func statusLine(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private var testColor: Color {
        switch testOK {
        case .some(true): return Palette.success
        case .some(false): return Palette.danger
        case nil: return Palette.accent
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
            healthStatus = await health.accessStatus()
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
