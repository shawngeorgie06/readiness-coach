import Foundation
import Combine

/// Persisted API configuration and sync bookkeeping, backed by `UserDefaults`.
/// Observable so views react when the user edits connection details.
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    private let sessionKey = "sessionToken"

    @Published var apiBaseURL: String { didSet { defaults.set(apiBaseURL, forKey: Keys.baseURL) } }
    @Published var apiToken: String { didSet { defaults.set(apiToken, forKey: Keys.token) } }
    @Published var userId: String { didSet { defaults.set(userId, forKey: Keys.userId) } }
    @Published var appleDisplayName: String? {
        didSet { defaults.set(appleDisplayName, forKey: Keys.appleDisplayName) }
    }
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
        self.apiBaseURL = defaults.string(forKey: Keys.baseURL) ?? Self.defaultBaseURL
        self.apiToken = defaults.string(forKey: Keys.token) ?? ""
        self.userId = defaults.string(forKey: Keys.userId) ?? ""
        self.appleDisplayName = defaults.string(forKey: Keys.appleDisplayName)
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)
        self.notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        self.notificationHour = (defaults.object(forKey: Keys.notificationHour) as? Int) ?? 7
        self.notificationMinute = defaults.integer(forKey: Keys.notificationMinute)
    }

    /// The backend session token (Keychain-backed). Nil when signed out.
    var sessionToken: String? {
        get { KeychainStore.get(sessionKey) }
        set {
            if let newValue {
                KeychainStore.set(newValue, for: sessionKey)
            } else {
                KeychainStore.remove(sessionKey)
            }
            objectWillChange.send()
        }
    }

    var isSignedIn: Bool { sessionToken != nil }

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
        relativeText(lastSyncAt)
    }

    /// Timestamp of the last successful Today refresh from the server — set on
    /// ANY successful load, not only a HealthKit upload pass. This is what the
    /// user-facing "last synced" label reads, so "Synced" and the timestamp
    /// agree instead of showing "Synced" next to "Never synced".
    var lastRefreshAt: Date? {
        get {
            let value = defaults.double(forKey: Keys.lastRefresh)
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        set {
            objectWillChange.send()
            defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Keys.lastRefresh)
        }
    }

    var lastRefreshRelativeText: String? {
        relativeText(lastRefreshAt)
    }

    private func relativeText(_ date: Date?) -> String? {
        guard let date else { return nil }
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

    var isReady: Bool { (isConfigured || isSignedIn) && hasCompletedOnboarding }

    /// Builds a client from the current settings, or nil if incomplete.
    func makeClient() -> APIClient? {
        let trimmedURL = apiBaseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmedURL), !userId.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let bearer = (sessionToken ?? apiToken).trimmingCharacters(in: .whitespaces)
        guard !bearer.isEmpty else { return nil }
        return APIClient(
            url: url,
            token: bearer,
            userId: userId.trimmingCharacters(in: .whitespaces)
        )
    }

    /// Persist a successful Apple sign-in: session token, user ID, and name.
    func applyAuth(_ response: AuthResponse, displayName: String?) {
        userId = response.userId
        if let displayName, !displayName.isEmpty {
            appleDisplayName = displayName
        }
        sessionToken = response.sessionToken
    }

    /// Clear the session and return the app to the sign-in screen.
    func signOut() {
        sessionToken = nil
        appleDisplayName = nil
        hasCompletedOnboarding = false
    }

    /// Fills a fresh, stable user identifier when none exists yet.
    func ensureUserId() {
        if userId.trimmingCharacters(in: .whitespaces).isEmpty {
            userId = UUID().uuidString.lowercased()
        }
    }

    func clearLocalSettings() {
        sessionToken = nil
        apiBaseURL = Self.defaultBaseURL
        apiToken = ""
        userId = ""
        appleDisplayName = nil
        hasCompletedOnboarding = false
        lastSyncAt = nil
        lastRefreshAt = nil
    }

    /// This is a single-user personal deployment, so the backend URL is stable.
    /// Pre-filling it removes the need to type/paste the URL during onboarding.
    static let defaultBaseURL = "https://readiness-coach.onrender.com"

    private enum Keys {
        static let baseURL = "apiBaseURL"
        static let token = "apiToken"
        static let userId = "userId"
        static let appleDisplayName = "appleDisplayName"
        static let onboarded = "hasCompletedOnboarding"
        static let lastSync = "lastSyncAt"
        static let lastRefresh = "lastRefreshAt"
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
