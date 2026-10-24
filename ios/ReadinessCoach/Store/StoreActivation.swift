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
    private static let legacyTodayURL = applicationSupport.appendingPathComponent("cached-today.json")
    private static var migratedLegacyToday = false

    /// Activates `store` for the signed-in user, with a client only when the
    /// settings are complete. Safe to call repeatedly; does nothing without a user.
    static func activate(_ store: AppStore, settings: AppSettings) {
        let userId = settings.userId.trimmingCharacters(in: .whitespaces)
        guard !userId.isEmpty else { return }
        if !migratedLegacyToday {
            migratedLegacyToday = true
            cache.migrateLegacyToday(from: legacyTodayURL, userId: userId, day: APIClient.deviceLocalDate())
        }
        store.activate(userId: userId, api: settings.makeClient())
    }
}
