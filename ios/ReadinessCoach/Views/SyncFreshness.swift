import SwiftUI

/// How trustworthy the score on screen is right now.
enum DataFreshness: Equatable {
    case noData
    case fresh
    case aging(relative: String)
    case stale(scoreDay: String)
    case offline
}

enum SyncFreshness {
    static func localCalendarDay() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }

    static func evaluate(today: TodayDTO?, settings: AppSettings, errorMessage: String?) -> DataFreshness {
        guard let today else { return .noData }
        if errorMessage != nil { return .offline }

        let scoreDay = String(today.date.prefix(10))
        if scoreDay != localCalendarDay() {
            return .stale(scoreDay: scoreDay)
        }

        if let refreshed = settings.lastRefreshAt {
            let age = Date().timeIntervalSince(refreshed)
            if age > 2 * 3600, let relative = settings.lastRefreshRelativeText {
                return .aging(relative: relative)
            }
        }
        return .fresh
    }

    static func statusLabel(_ freshness: DataFreshness, syncing: Bool) -> (text: String, tone: Pill.Tone) {
        if syncing { return ("Syncing…", .neutral) }
        switch freshness {
        case .noData: return ("Not synced", .warn)
        case .fresh: return ("Up to date", .good)
        case .aging(let relative): return ("Updated \(relative)", .warn)
        case .stale: return ("Score may be outdated", .warn)
        case .offline: return ("Offline — cached score", .accent)
        }
    }

    static func detailLine(_ freshness: DataFreshness, settings: AppSettings, summary: String?) -> String? {
        switch freshness {
        case .noData:
            return "Sync Health data to compute today's readiness."
        case .fresh:
            if let summary, !summary.isEmpty { return summary }
            if let relative = settings.lastRefreshRelativeText {
                return "Last refreshed \(relative)."
            }
            return nil
        case .aging:
            if let summary, !summary.isEmpty { return summary }
            return "Open the app or pull to refresh for the latest score."
        case .stale(let scoreDay):
            return "Showing score for \(formattedDay(scoreDay)). Pull to refresh for today."
        case .offline:
            return "Couldn't reach the server — showing your last saved score."
        }
    }

    private static func formattedDay(_ isoDay: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = .current
        guard let date = parser.date(from: isoDay) else { return isoDay }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct FreshnessBanner: View {
    let title: String
    let message: String
    let color: Color
    let icon: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.caption.weight(.semibold))
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color.opacity(0.22), lineWidth: 1)
        )
    }
}
