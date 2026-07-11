import SwiftUI

/// Gates the app behind onboarding until connection details are set and
/// HealthKit permission has been requested.
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        if settings.isReady {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            SleepView()
                .tabItem { Label("Sleep", systemImage: "bed.double") }
            TrainView()
                .tabItem { Label("Train", systemImage: "figure.run") }
            BodyView()
                .tabItem { Label("Body", systemImage: "heart") }
            AskCoachView()
                .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

// MARK: - Shared UI

extension Decision {
    var tint: Color {
        switch self {
        case .push: return .green
        case .maintain: return .yellow
        case .recover: return .red
        }
    }

    var systemImage: String {
        switch self {
        case .push: return "bolt.fill"
        case .maintain: return "equal.circle.fill"
        case .recover: return "moon.zzz.fill"
        }
    }
}

/// The locked-decision chip shown wherever the user needs to see the constraint,
/// including Ask Coach.
struct DecisionChip: View {
    let decision: Decision

    var body: some View {
        Label(decision.title, systemImage: decision.systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(decision.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(decision.tint)
            .accessibilityLabel("Locked decision: \(decision.title)")
    }
}

struct ReadinessRing: View {
    let readiness: Double
    let decision: Decision

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: min(max(readiness / 100, 0), 1))
                .stroke(decision.tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(Int(readiness.rounded()))")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("readiness")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 160, height: 160)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness \(Int(readiness.rounded())), decision \(decision.title)")
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
