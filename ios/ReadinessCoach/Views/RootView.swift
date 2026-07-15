import SwiftUI

/// Gates the app behind onboarding until connection details are set and
/// HealthKit permission has been requested.
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if settings.isReady {
                MainTabView()
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active { Task { await sync.autoSync(settings) } }
                        else if phase == .background { BackgroundRefreshService.schedule(for: settings) }
                    }
                    .task {
                        await sync.autoSync(settings)
                        BackgroundRefreshService.schedule(for: settings)
                    }
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(.dark)
        .tint(Palette.accent)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "circle.circle.fill") }
            TrendsView().tabItem { Label("Insights", systemImage: "chart.bar.fill") }
            TrainView().tabItem { Label("Activity", systemImage: "bolt.fill") }
            BodyView().tabItem { Label("Body", systemImage: "figure.stand") }
            YouView().tabItem { Label("You", systemImage: "person.fill") }
        }
        .toolbarBackground(Palette.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .tint(Palette.accent)
    }
}

/// Shared helpers for date-based chart axes (auto-thinned, formatted labels).
enum ChartDate {
    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Parse a "yyyy-MM-dd" (or ISO) string to a Date for plotting.
    static func day(_ iso: String) -> Date {
        parser.date(from: String(iso.prefix(10))) ?? Date()
    }
}

// MARK: - Shared UI

extension Decision {
    var tint: Color { Palette.decisionColor(self) }

    var systemImage: String {
        switch self {
        case .push: return "bolt.fill"
        case .maintain: return "equal.circle.fill"
        case .recover: return "moon.zzz.fill"
        }
    }

    var meaning: String {
        switch self {
        case .push: return "You're recovered — a hard session is on the table."
        case .maintain: return "Train, but keep intensity moderate; no maximal efforts."
        case .recover: return "Back off today — rest or light movement only."
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
    @State private var animated = false

    var body: some View {
        let fraction = min(max(readiness / 100, 0), 1)
        let color = Palette.decisionColor(decision)
        ZStack {
            Circle().stroke(Palette.textPrimary.opacity(0.08), lineWidth: 10)
            Circle().trim(from: 0, to: animated ? fraction : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.5), radius: 12)
            VStack(spacing: 2) {
                Text("\(Int(readiness.rounded()))")
                    .font(.system(size: 64, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                Eyebrow(text: "Score")
            }
        }
        .frame(width: 210, height: 210)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { animated = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness \(Int(readiness.rounded())), decision \(decision.title)")
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: title)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
