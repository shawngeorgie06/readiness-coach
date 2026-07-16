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
    // Optional preselected tab (used for testing/screenshots): SIMCTL_CHILD_START_TAB=n.
    @StateObject private var tabs = TabRouter(
        initial: ProcessInfo.processInfo.environment["START_TAB"].flatMap { Int($0) } ?? 0
    )

    var body: some View {
        // Custom six-tab shell: system TabView only shows five (+ More) and our solid
        // replacement dropped Liquid Glass. Float a glass bar over content instead.
        ZStack(alignment: .bottom) {
            ZStack {
                tabPage(.today) { TodayView() }
                tabPage(.insights) { TrendsView() }
                tabPage(.sleep) { SleepView() }
                tabPage(.activity) { TrainView() }
                tabPage(.body) { BodyView() }
                tabPage(.you) { YouView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Leave room so scroll content isn’t trapped under the floating bar.
            .safeAreaPadding(.bottom, 56)

            AetherTabBar(selection: $tabs.selection)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
        }
        .background(Palette.canvas.ignoresSafeArea())
        .environmentObject(tabs)
        .tint(Palette.accent)
    }

    @ViewBuilder
    private func tabPage<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        let selected = tabs.selection == tab.rawValue
        content()
            .opacity(selected ? 1 : 0)
            .allowsHitTesting(selected)
            .accessibilityHidden(!selected)
    }
}

/// Floating six-item bar with Liquid Glass when the SDK has it, material glass otherwise.
struct AetherTabBar: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selection = tab.rawValue
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .symbolEffect(.bounce, value: selection == tab.rawValue)
                        Text(tab.title)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(selection == tab.rawValue ? Palette.accent : Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab.rawValue ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .liquidGlassChrome()
    }
}

extension View {
    /// Tab-bar chrome: native Liquid Glass on iOS 26+, frosted material fallback earlier.
    @ViewBuilder
    func liquidGlassChrome() -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular.interactive(), in: .capsule)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        } else {
            self
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.38),
                                            Color.white.opacity(0.06),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        }
                        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                }
        }
    }
}

/// Shared tab indices so Today (and others) can jump to Insights / Sleep, etc.
enum AppTab: Int, CaseIterable, Identifiable {
    case today = 0
    case insights = 1
    case sleep = 2
    case activity = 3
    case body = 4
    case you = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .insights: return "Insights"
        case .sleep: return "Sleep"
        case .activity: return "Activity"
        case .body: return "Body"
        case .you: return "You"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "circle.circle.fill"
        case .insights: return "chart.bar.fill"
        case .sleep: return "bed.double.fill"
        case .activity: return "bolt.fill"
        case .body: return "figure.stand"
        case .you: return "person.fill"
        }
    }
}

final class TabRouter: ObservableObject {
    @Published var selection: Int
    init(initial: Int = 0) { selection = initial }
    func go(to tab: AppTab) { selection = tab.rawValue }
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
        // Fit the ring to available width so stroke + score never spill past the hero card.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 200)
            .overlay {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    let line = max(7, side * 0.05)
                    // Stroke is centered on the path — inset so the full ring stays inside bounds.
                    let inset = line / 2 + 2
                    let color = Palette.decisionColor(decision)
                    let fraction = min(max(readiness / 100, 0), 1)
                    let fontSize = min(52, (side - inset * 2) * 0.34)

                    ZStack {
                        Circle()
                            .stroke(Palette.textPrimary.opacity(0.08), lineWidth: line)
                            .padding(inset)
                        Circle()
                            .trim(from: 0, to: animated ? fraction : 0)
                            .stroke(color.opacity(0.28), style: StrokeStyle(lineWidth: line + 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .blur(radius: 3)
                            .padding(inset)
                            .allowsHitTesting(false)
                        Circle()
                            .trim(from: 0, to: animated ? fraction : 0)
                            .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(inset)
                        VStack(spacing: 2) {
                            Text("\(Int(readiness.rounded()))")
                                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                                .foregroundStyle(Palette.textPrimary)
                            Eyebrow(text: "Score")
                        }
                        .frame(maxWidth: max(40, side - inset * 2 - line * 2 - 12))
                    }
                    .frame(width: side, height: side)
                }
            }
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
