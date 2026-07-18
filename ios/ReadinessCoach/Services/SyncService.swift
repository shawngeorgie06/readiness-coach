import Foundation

/// Coordinates HealthKit sync and Today refresh, and holds the observable state
/// the views render. One instance is shared through the environment.
@MainActor
final class SyncService: ObservableObject {
    @Published var today: TodayDTO?
    @Published var isSyncing = false
    @Published var isLoadingToday = false
    @Published var errorMessage: String?
    @Published var lastSyncSummary: String?
    @Published var uploadingCount: Int?

    private let health = HealthKitService()
    private var lastAutoSyncAt: Date?
    private var lastBackgroundSyncAt: Date?

    /// Today includes health-derived information. Keep it in a file with iOS
    /// complete file protection rather than in UserDefaults, and do not include
    /// it in device backups.
    private static let legacyCacheKey = "cachedTodayJSON"
    private static let cacheURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("cached-today.json")

    /// Show the last-known Today immediately on launch (stale-while-revalidate),
    /// so a cold Render server (30–60s wake) doesn't leave the UI blank. The
    /// network refresh then replaces it in the background.
    init() {
        // Remove the pre-v1.3.4 UserDefaults cache after upgrading.
        UserDefaults.standard.removeObject(forKey: Self.legacyCacheKey)
        if let data = try? Data(contentsOf: Self.cacheURL),
           let cached = try? JSONDecoder().decode(TodayDTO.self, from: data) {
            today = cached
        }
    }

    /// Records a successful server refresh: cache it and stamp the display time.
    private func didRefresh(_ dto: TodayDTO, _ settings: AppSettings) {
        today = dto
        settings.lastRefreshAt = Date()
        if let data = try? JSONEncoder().encode(dto) {
            do {
                let directory = Self.cacheURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                try data.write(to: Self.cacheURL, options: [.atomic, .completeFileProtection])
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var cacheURL = Self.cacheURL
                try cacheURL.setResourceValues(values)
            } catch {
                // Caching is an optimization; a fresh response remains usable.
            }
        }
    }

    /// Foreground-triggered sync, debounced so rapid app switches don't re-sync.
    func autoSync(_ settings: AppSettings) async {
        if let last = lastAutoSyncAt, Date().timeIntervalSince(last) < 30 { return }
        lastAutoSyncAt = Date()
        await syncNow(settings)
    }

    /// HealthKit background delivery — debounced harder than foreground sync.
    func backgroundSync(_ settings: AppSettings) async {
        if let last = lastBackgroundSyncAt, Date().timeIntervalSince(last) < 300 { return }
        lastBackgroundSyncAt = Date()
        await syncNow(settings)
    }

    func freshness(using settings: AppSettings) -> DataFreshness {
        SyncFreshness.evaluate(today: today, settings: settings, errorMessage: errorMessage)
    }

    var healthSyncFailed: Bool {
        lastSyncSummary?.hasPrefix("Couldn't read Health") == true
    }

    /// Reads new HealthKit samples, uploads them, then refreshes Today so the
    /// locked decision reflects the just-synced data.
    func syncNow(_ settings: AppSettings) async {
        guard let client = settings.makeClient() else {
            errorMessage = APIError.notConfigured.localizedDescription
            return
        }
        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false; uploadingCount = nil }

        do {
            if HealthKitService.isAvailable {
                // A Health read/upload failure (no entitlement on Simulator, or
                // partial permission) must not blank the server-computed score.
                do {
                    let payload = try await health.fetchSamples(
                        since: settings.lastSyncAt,
                        userId: settings.userId
                    )
                    if !payload.isEmpty {
                        uploadingCount = payload.samples.count
                        let result = try await client.sync(payload)
                        lastSyncSummary = "Synced \(result.samples) samples, \(result.workouts) workouts."
                    } else {
                        lastSyncSummary = "No new HealthKit samples since last sync."
                    }
                    settings.lastSyncAt = Date()
                } catch {
                    lastSyncSummary = "Couldn't read Health data: \(readable(error))"
                }
            } else {
                lastSyncSummary = "HealthKit unavailable — showing server data only."
            }
            didRefresh(try await client.getToday(), settings)
        } catch {
            signOutIfUnauthorized(error, settings: settings)
            errorMessage = readable(error)
        }
    }

    /// Fetches Today without pushing new samples (e.g. on tab appear).
    func refreshToday(_ settings: AppSettings) async {
        guard let client = settings.makeClient() else {
            errorMessage = APIError.notConfigured.localizedDescription
            return
        }
        isLoadingToday = true
        errorMessage = nil
        defer { isLoadingToday = false }
        do {
            didRefresh(try await client.getToday(), settings)
        } catch {
            signOutIfUnauthorized(error, settings: settings)
            errorMessage = readable(error)
        }
    }

    private func signOutIfUnauthorized(_ error: Error, settings: AppSettings) {
        if case APIError.http(status: 401, _) = error, settings.isSignedIn {
            settings.signOut()
        }
    }

    private func readable(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
