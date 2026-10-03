import SwiftUI

/// Gates the app behind onboarding until connection details are set and
/// HealthKit permission has been requested.
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var sync: SyncService
    @Environment(\.scenePhase) private var scenePhase
    private let notifications = NotificationService()
    private let healthBackground = HealthBackgroundDelivery()

    var body: some View {
        Group {
            if settings.isReady {
                MainTabView()
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active {
                            Task {
                                await sync.autoSync(settings)
                                notifications.refreshDailySchedule(settings: settings, latest: sync.today)
                            }
                        }
                    }
                    .onChange(of: sync.today?.date) { _, _ in
                        notifications.refreshDailySchedule(settings: settings, latest: sync.today)
                    }
                    .task {
                        await sync.autoSync(settings)
                        notifications.refreshDailySchedule(settings: settings, latest: sync.today)
                        healthBackground.start {
                            await sync.backgroundSync(settings)
                            notifications.refreshDailySchedule(settings: settings, latest: sync.today)
                        }
                    }
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(.dark)
        .tint(Palette.accent)
    }
}

/// Four tabs: the decision, then one per pillar of the score.
struct MainTabView: View {
    // Optional preselected tab (used for testing/screenshots): SIMCTL_CHILD_START_TAB=n.
    @StateObject private var tabs = TabRouter(
        initial: ProcessInfo.processInfo.environment["START_TAB"].flatMap { Int($0) } ?? 0
    )

    var body: some View {
        TabView(selection: $tabs.selection) {
            TodayView()
                .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.systemImage) }
                .tag(AppTab.today.rawValue)
            BodyView()
                .tabItem { Label(AppTab.recovery.title, systemImage: AppTab.recovery.systemImage) }
                .tag(AppTab.recovery.rawValue)
            SleepView()
                .tabItem { Label(AppTab.sleep.title, systemImage: AppTab.sleep.systemImage) }
                .tag(AppTab.sleep.rawValue)
            TrainView()
                .tabItem { Label(AppTab.train.title, systemImage: AppTab.train.systemImage) }
                .tag(AppTab.train.rawValue)
        }
        .environmentObject(tabs)
        .tint(Palette.accent)
    }
}

/// Shared tab indices so Today can jump to a pillar tab.
enum AppTab: Int, CaseIterable, Identifiable {
    case today = 0
    case recovery = 1
    case sleep = 2
    case train = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .recovery: return "Recovery"
        case .sleep: return "Sleep"
        case .train: return "Train"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "circle.inset.filled"
        case .recovery: return Pillar.recovery.systemImage
        case .sleep: return Pillar.sleep.systemImage
        case .train: return Pillar.load.systemImage
        }
    }

    init(_ pillar: Pillar) {
        switch pillar {
        case .recovery: self = .recovery
        case .sleep: self = .sleep
        case .load: self = .train
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
    private static let utcParser: DateFormatter = {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        return parser
    }()

    static func parse(_ iso: String, timeZone: TimeZone = .current) -> Date? {
        guard let utc = utcParser.date(from: String(iso.prefix(10))) else { return nil }
        return rebase(utc, from: TimeZone(secondsFromGMT: 0)!, to: timeZone)
    }

    /// Keep the selected calendar day, not its old midnight instant, after travel.
    static func rebase(_ date: Date?, from oldZone: TimeZone, to newZone: TimeZone) -> Date? {
        guard let date else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = oldZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        calendar.timeZone = newZone
        return calendar.date(from: components)
    }

    /// Resolve the time zone on each call, including after a device-zone change.
    static func day(_ iso: String, timeZone: TimeZone = .current) -> Date {
        parse(iso, timeZone: timeZone) ?? Date()
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
