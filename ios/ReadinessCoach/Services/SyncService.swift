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

    /// Foreground-triggered sync, debounced so rapid app switches don't re-sync.
    func autoSync(_ settings: AppSettings) async {
        if let last = lastAutoSyncAt, Date().timeIntervalSince(last) < 30 { return }
        lastAutoSyncAt = Date()
        await syncNow(settings)
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
            today = try await client.getToday()
        } catch {
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
            today = try await client.getToday()
        } catch {
            errorMessage = readable(error)
        }
    }

    private func readable(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
