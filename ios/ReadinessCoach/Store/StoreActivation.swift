import Foundation

/// Live wiring for `AppStore`: the on-disk cache location, the one-time move of
/// the pre-store Today cache, and activation from the current settings.
@MainActor
enum StoreActivation {
    private static let applicationSupport = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    static let cache = ResourceDiskCache(
        directory: applicationSupport.appendingPathComponent("resource-cache", isDirectory: true)
    )

    /// Where `SyncService` kept Today before the store existed.
    static let legacyTodayURL = applicationSupport.appendingPathComponent("cached-today.json")

    /// Activates `store` for the signed-in user, with a client only when the
    /// settings are complete. Safe to call repeatedly; does nothing without a user.
    static func activate(_ store: AppStore, settings: AppSettings) {
        let userId = settings.userId.trimmingCharacters(in: .whitespaces)
        migrateLegacyToday(cache: cache, legacyURL: legacyTodayURL, userId: userId)
        guard !userId.isEmpty else { return }
        store.activate(userId: userId, api: settings.makeClient())
    }

    /// Moves the legacy Today into the cache for `userId`. With no user (account
    /// deleted or settings cleared) the file belongs to nobody, so it is deleted
    /// rather than kept for whoever onboards next.
    static func migrateLegacyToday(cache: ResourceDiskCache, legacyURL: URL, userId: String) {
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }
        if userId.isEmpty {
            try? FileManager.default.removeItem(at: legacyURL)
        } else {
            cache.migrateLegacyToday(from: legacyURL, userId: userId, day: APIClient.deviceLocalDate())
        }
    }

    /// Clears every cached resource, in memory and on disk, including a legacy
    /// Today that was never migrated. Used by every sign-out path.
    static func reset(_ store: AppStore, legacyURL: URL = legacyTodayURL) {
        store.reset()
        try? FileManager.default.removeItem(at: legacyURL)
    }
}
