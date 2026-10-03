import SwiftUI

/// One thing the user should know about the score on screen. Ordered by how
/// much it should change what they do about it.
enum StatusItem: Equatable, Identifiable {
    case healthAccess(needsPermission: Bool)
    case healthCheck
    case offline
    case uploadPending
    case stale(scoreDay: String)
    case lowConfidence(missing: [String])
    case calibrating
    case aging(relative: String)

    var id: String {
        switch self {
        case .healthAccess: return "healthAccess"
        case .healthCheck: return "healthCheck"
        case .offline: return "offline"
        case .uploadPending: return "uploadPending"
        case .stale: return "stale"
        case .lowConfidence: return "lowConfidence"
        case .calibrating: return "calibrating"
        case .aging: return "aging"
        }
    }

    var title: String {
        switch self {
        case .healthAccess: return "Health access needed"
        case .healthCheck: return "Check Health data"
        case .offline: return "Offline"
        case .uploadPending: return "Health upload pending"
        case .stale: return "Score may be outdated"
        case .lowConfidence: return "Low confidence"
        case .calibrating: return "Calibrating"
        case .aging: return "Not refreshed recently"
        }
    }

    var message: String {
        switch self {
        case .healthAccess:
            return "Readiness needs heart rate, HRV, sleep, and workouts from Apple Health."
        case .healthCheck:
            return "Some Health signals are missing. If your Watch has recorded them, check Readiness Coach’s read access in Health settings. iOS does not tell apps whether read access was granted or denied."
        case .offline:
            return "Couldn’t reach the server. Any score shown is your last saved one; reconnect to refresh today."
        case .uploadPending:
            return "New Watch data didn’t reach the server. Any score shown may not include it. Pull down to retry."
        case .stale(let scoreDay):
            return "Showing the score for \(StatusLineModel.formattedDay(scoreDay)). Pull down to refresh for today."
        case .lowConfidence(let missing):
            return "Some data is missing today\(StatusLineModel.friendlyMissing(missing)), so the call stays cautious."
        case .calibrating:
            return "Baselines are still forming from your recent history. Scores are provisional until about 14 days of data exist."
        case .aging(let relative):
            return "Last refreshed \(relative). Background sync runs when Health gets new data; pull down to refresh now."
        }
    }

    var systemImage: String {
        switch self {
        case .healthAccess, .healthCheck: return "heart.text.square"
        case .offline: return "wifi.slash"
        case .uploadPending: return "arrow.up.circle.trianglebadge.exclamationmark"
        case .stale: return "clock.arrow.circlepath"
        case .lowConfidence: return "exclamationmark.triangle.fill"
        case .calibrating: return "gauge.with.dots.needle.33percent"
        case .aging: return "arrow.triangle.2.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .healthAccess, .healthCheck: return Palette.accent
        case .aging: return Palette.textSecondary
        default: return Palette.warn
        }
    }

    var actionTitle: String? {
        switch self {
        case .healthAccess(let needsPermission):
            return needsPermission ? "Allow Health access" : "Open Health settings"
        case .healthCheck:
            return "Open Health settings"
        default:
            return nil
        }
    }
}

/// Pure resolution of which status items apply. Kept free of views so it can be
/// unit-tested.
enum StatusLineModel {
    struct Input {
        var freshness: DataFreshness
        var today: TodayDTO?
        var healthStatus: HealthKitService.AccessStatus?
        var healthSyncFailed: Bool
        var healthSyncSucceeded: Bool
        var uploadFailed: Bool
    }

    static func items(_ input: Input) -> [StatusItem] {
        var items: [StatusItem] = []
        if let status = input.healthStatus,
           needsHealthAccess(status: status,
                             syncFailed: input.healthSyncFailed,
                             syncSucceeded: input.healthSyncSucceeded) {
            items.append(.healthAccess(needsPermission: status == .needsPermission))
        }
        if input.freshness == .offline { items.append(.offline) }
        if input.uploadFailed { items.append(.uploadPending) }
        if case .stale(let scoreDay) = input.freshness { items.append(.stale(scoreDay: scoreDay)) }
        if let today = input.today {
            if today.isLowConfidence { items.append(.lowConfidence(missing: today.missing)) }
            if today.calibrating { items.append(.calibrating) }
            // Request completion is not proof of read access. Offer a check,
            // without diagnosing missing signals as a permission denial.
            if input.healthStatus == .connected, !today.missing.isEmpty {
                items.append(.healthCheck)
            }
        }
        if case .aging(let relative) = input.freshness { items.append(.aging(relative: relative)) }
        return items
    }

    /// Keep score uncertainty visible even when a connection issue has priority.
    static func summary(_ items: [StatusItem]) -> String {
        guard let first = items.first else { return "" }
        let visible = items.filter { item in
            if item == first { return true }
            switch item {
            case .lowConfidence, .calibrating: return true
            default: return false
            }
        }
        let titles = visible.map(\.title).joined(separator: " · ")
        let remaining = items.count - visible.count
        return remaining == 0 ? titles : "\(titles) +\(remaining)"
    }

    /// Only prompt when Health access is genuinely missing — not while access is
    /// granted but a stale read error is still around.
    static func needsHealthAccess(status: HealthKitService.AccessStatus,
                                  syncFailed: Bool,
                                  syncSucceeded: Bool) -> Bool {
        switch status {
        case .connected: return false
        case .needsPermission: return true
        case .unavailable: return syncFailed && !syncSucceeded
        }
    }

    /// Maps raw missing-metric keys to human names for the message.
    static func friendlyMissing(_ keys: [String]) -> String {
        let names = keys.map { key -> String in
            switch key {
            case "hrv": return "heart-rate variability"
            case "resting_heart_rate": return "resting pulse"
            case "sleep": return "sleep"
            default: return key
            }
        }
        return names.isEmpty ? "" : " (\(names.joined(separator: ", ")))"
    }

    static func formattedDay(_ isoDay: String, locale: Locale = .current) -> String {
        guard let date = ChartDate.parse(isoDay) else { return isoDay }
        let display = DateFormatter()
        display.locale = locale
        display.timeZone = .current
        display.dateStyle = .medium
        display.timeStyle = .none
        return display.string(from: date)
    }
}

/// Collapsed: the priority item plus score uncertainty and a remaining count.
/// Expanded: every message and action. Hidden when there is nothing to say.
struct StatusLine: View {
    let items: [StatusItem]
    let onHealthAction: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expanded = false

    var body: some View {
        if let first = items.first {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                        : AnyLayout(HStackLayout(spacing: 10))
                    layout {
                        HStack {
                            Image(systemName: first.systemImage)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(first.color)
                            if typeSize.isAccessibilitySize {
                                Spacer()
                                disclosureIcon
                            }
                        }
                        Text(StatusLineModel.summary(items))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !typeSize.isAccessibilitySize {
                            Spacer(minLength: 8)
                            disclosureIcon
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilitySummary)
                .accessibilityHint(expanded ? "Collapses details" : "Shows details")

                if expanded {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(items) { item in
                            detail(item)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var disclosureIcon: some View {
        Image(systemName: "chevron.down")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.textTertiary)
            .rotationEffect(.degrees(expanded ? 180 : 0))
    }

    private var accessibilitySummary: String {
        items.map(\.title).joined(separator: ", ")
    }

    private func detail(_ item: StatusItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(item.color)
            Text(item.message)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let action = item.actionTitle {
                Button(action, action: onHealthAction)
                    .font(.footnote.weight(.semibold))
                    .padding(.top, 2)
            }
        }
    }
}
