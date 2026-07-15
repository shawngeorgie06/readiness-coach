import Foundation
import Combine

/// Persisted API configuration and sync bookkeeping, backed by `UserDefaults`.
/// Observable so views react when the user edits connection details.
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var apiBaseURL: String { didSet { defaults.set(apiBaseURL, forKey: Keys.baseURL) } }
    @Published var apiToken: String { didSet { defaults.set(apiToken, forKey: Keys.token) } }
    @Published var userId: String { didSet { defaults.set(userId, forKey: Keys.userId) } }
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarded) }
    }
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }
    @Published var notificationHour: Int {
        didSet { defaults.set(notificationHour, forKey: Keys.notificationHour) }
    }
    @Published var notificationMinute: Int {
        didSet { defaults.set(notificationMinute, forKey: Keys.notificationMinute) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.apiBaseURL = defaults.string(forKey: Keys.baseURL) ?? ""
        self.apiToken = defaults.string(forKey: Keys.token) ?? ""
        self.userId = defaults.string(forKey: Keys.userId) ?? ""
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)
        self.notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        self.notificationHour = (defaults.object(forKey: Keys.notificationHour) as? Int) ?? 7
        self.notificationMinute = defaults.integer(forKey: Keys.notificationMinute)
    }

    /// Timestamp of the last successful sync; only newer samples are sent next time.
    var lastSyncAt: Date? {
        get {
            let value = defaults.double(forKey: Keys.lastSync)
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        set {
            objectWillChange.send()
            defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Keys.lastSync)
        }
    }

    /// Human-friendly "3m ago" text for the last successful sync, or nil if never.
    var lastSyncRelativeText: String? {
        guard let date = lastSyncAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var isConfigured: Bool {
        guard let url = URL(string: apiBaseURL.trimmingCharacters(in: .whitespaces)),
              url.scheme != nil, url.host != nil else { return false }
        return !apiToken.trimmingCharacters(in: .whitespaces).isEmpty
            && !userId.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isReady: Bool { isConfigured && hasCompletedOnboarding }

    /// Builds a client from the current settings, or nil if incomplete.
    func makeClient() -> APIClient? {
        let trimmedURL = apiBaseURL.trimmingCharacters(in: .whitespaces)
        guard isConfigured, let url = URL(string: trimmedURL) else { return nil }
        return APIClient(
            url: url,
            token: apiToken.trimmingCharacters(in: .whitespaces),
            userId: userId.trimmingCharacters(in: .whitespaces)
        )
    }

    /// Fills a fresh, stable user identifier when none exists yet.
    func ensureUserId() {
        if userId.trimmingCharacters(in: .whitespaces).isEmpty {
            userId = UUID().uuidString.lowercased()
        }
    }

    func clearLocalSettings() {
        apiBaseURL = ""
        apiToken = ""
        userId = ""
        hasCompletedOnboarding = false
        lastSyncAt = nil
    }

    private enum Keys {
        static let baseURL = "apiBaseURL"
        static let token = "apiToken"
        static let userId = "userId"
        static let onboarded = "hasCompletedOnboarding"
        static let lastSync = "lastSyncAt"
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationHour = "notificationHour"
        static let notificationMinute = "notificationMinute"
    }
}

extension APIClient {
    init(url: URL, token: String, userId: String) {
        self.init(baseURL: url, token: token, userId: userId)
    }
}
