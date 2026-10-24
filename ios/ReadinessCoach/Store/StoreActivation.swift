import Foundation

/// Live wiring for `AppStore`: the on-disk cache location, removal of the
/// pre-store Today cache, and activation from the current settings.
@MainActor
enum StoreActivation {
    nonisolated private static let applicationSupport = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    static let cache = ResourceDiskCache(
        directory: applicationSupport.appendingPathComponent("resource-cache", isDirectory: true)
    )

    /// Where `SyncService` kept Today before the store existed. The file is a
    /// bare `TodayDTO` with no record of whose data it is, so it is never read:
    /// activation and reset delete it.
    nonisolated static let legacyTodayURL = applicationSupport.appendingPathComponent("cached-today.json")

    /// Activates `store` for the signed-in user, with a client only when the
    /// settings are complete. Safe to call repeatedly; does nothing without a user.
    static func activate(_ store: AppStore, settings: AppSettings) {
        activate(store, userId: settings.userId, api: settings.makeClient())
    }

    /// Deletes the unowned legacy Today, even when signed in, then activates
    /// `store` for `userId` if there is one.
    static func activate(_ store: AppStore, userId: String, api: ReadAPI?, legacyURL: URL = legacyTodayURL) {
        try? FileManager.default.removeItem(at: legacyURL)
        let userId = userId.trimmingCharacters(in: .whitespaces)
        guard !userId.isEmpty else { return }
        store.activate(userId: userId, api: api)
    }

    /// Clears every cached resource, in memory and on disk, including the
    /// legacy Today. Used by every sign-out path.
    static func reset(_ store: AppStore, legacyURL: URL = legacyTodayURL) {
        store.reset()
        try? FileManager.default.removeItem(at: legacyURL)
    }
}
