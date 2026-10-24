import Foundation

/// Coordinates HealthKit sync and Today refresh, and holds the observable state
/// the views render. One instance is shared through the environment.
@MainActor
final class SyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var isLoadingToday = false
    @Published var errorMessage: String?
    @Published var lastSyncSummary: String?
    @Published var lastUploadError: String?
    @Published var uploadingCount: Int?

    private let store: AppStore
    private let health = HealthKitService()
    private var lastAutoSyncAt: Date?
    private var lastBackgroundSyncAt: Date?

    private static let legacyCacheKey = "cachedTodayJSON"

    /// The last-known Today, served from the store (cached on disk, so it shows
    /// immediately on launch while a refresh runs).
    var today: TodayDTO? { store.today.value }

    init(store: AppStore) {
        self.store = store
        // Remove the pre-v1.3.4 UserDefaults cache after upgrading.
        UserDefaults.standard.removeObject(forKey: Self.legacyCacheKey)
    }

    /// Records a successful server refresh: stamp the display time.
    private func didRefresh(_ settings: AppSettings) {
        settings.lastRefreshAt = Date()
        errorMessage = nil
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

    /// The sync currently in flight, if any. Owned here rather than by a view.
    private var syncTask: Task<Void, Never>?

    var healthSyncFailed: Bool {
        lastSyncSummary?.hasPrefix("Couldn't read Health") == true
    }

    var healthSyncSucceeded: Bool {
        guard let summary = lastSyncSummary else { return false }
        return summary.hasPrefix("Synced ")
            || summary.hasPrefix("No new HealthKit samples")
    }

    var healthUploadFailed: Bool {
        lastUploadError != nil
    }

    /// Reads new HealthKit samples, uploads them, then refreshes Today so the
    /// locked decision reflects the just-synced data.
    ///
    /// HealthKit read and `/v1/today` run in parallel so the score can appear
    /// while samples are still being collected. A second Today fetch runs only
    /// when new samples were uploaded.
    /// Runs the sync in a task this service owns, so it survives the view that
    /// asked for it.
    ///
    /// Pull-to-refresh and `.task` hand SwiftUI a child task and cancel it the
    /// moment the view goes away -- a scroll, a tab switch, backgrounding the
    /// app. A 30-day backfill is many chunks long and was being killed
    /// mid-upload, surfacing as `CancellationError` and "new Health data
    /// didn't upload". Callers still await completion; they just no longer
    /// take the upload down with them. A second caller joins the run already
    /// in flight instead of starting a competing one.
    func syncNow(_ settings: AppSettings) async {
        if let inFlight = syncTask {
            await inFlight.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performSync(settings)
        }
        syncTask = task
        await task.value
        syncTask = nil
    }

    private func performSync(_ settings: AppSettings) async {
        guard let client = settings.makeClient() else {
            errorMessage = APIError.notConfigured.localizedDescription
            return
        }
        StoreActivation.activate(store, settings: settings)
        isSyncing = true
        errorMessage = nil
        lastUploadError = nil
        defer { isSyncing = false; uploadingCount = nil }

        async let healthPayloadTask = loadHealthPayload(settings)
        async let preliminaryTodayTask = store.refresh(.today, force: true)

        let healthPayload = await healthPayloadTask
        let preliminaryTodayLoaded = await preliminaryTodayTask

        if preliminaryTodayLoaded {
            didRefresh(settings)
        }

        var uploadedNewSamples = false
        if let healthPayload {
            switch healthPayload {
            case .samples(let payload):
                if payload.isEmpty {
                    lastSyncSummary = "No new HealthKit samples since last sync."
                    settings.lastSyncAt = Date()
                } else {
                    uploadedNewSamples = await uploadHealth(payload, client: client, settings: settings)
                }
            case .readFailed(let error):
                applyHealthReadFailure(error)
            case .unavailable:
                lastSyncSummary = "HealthKit unavailable — showing server data only."
            }
        }

        if uploadedNewSamples {
            store.noteUploadedSamples()
            await refreshTodayFromServer(settings, keepPreliminaryOnFailure: true)
        } else if !preliminaryTodayLoaded {
            await refreshTodayFromServer(settings, keepPreliminaryOnFailure: false)
        }
    }

    /// Uploads Health samples chunk by chunk, banking the resume point after each
    /// accepted request.
    ///
    /// Failing part-way (rate limit, dropped connection) therefore keeps whatever
    /// already landed: the next sync picks up where this one stopped instead of
    /// re-sending the entire backfill. Re-sending was what wedged a fresh install
    /// permanently — a 30-day backfill outran the `/v1` rate limit, the whole
    /// batch was discarded, and every retry restarted it and hit 429 again.
    ///
    /// Returns whether anything new reached the server.
    private func uploadHealth(
        _ payload: SyncPayload,
        client: APIClient,
        settings: AppSettings
    ) async -> Bool {
        let chunks = client.syncChunks(payload)
        let total = payload.samples.count
        var uploadedSamples = 0
        var uploadedWorkouts = 0
        uploadingCount = total

        for chunk in chunks {
            do {
                let result = try await client.syncChunk(chunk)
                uploadedSamples += result.samples
                uploadedWorkouts += result.workouts
                uploadingCount = max(0, total - uploadedSamples)
                // Chunks are oldest-first, so the server now holds everything up
                // to this timestamp. Persist it before attempting the next one.
                if let watermark = chunk.samples.last?.startAt,
                   let date = DateFormatting.date(fromISO: watermark) {
                    settings.lastSyncAt = date
                }
            } catch is CancellationError {
                // The run was torn down rather than refused. Whatever chunks
                // were accepted are banked in the watermark, so the next sync
                // resumes -- reporting a failure here would be misleading.
                lastSyncSummary = "Upload interrupted — resuming next sync."
                return uploadedSamples > 0 || uploadedWorkouts > 0
            } catch {
                lastUploadError = readable(error)
                lastSyncSummary = uploadedSamples > 0
                    ? "Uploaded \(uploadedSamples) of \(total) samples — the rest syncs next time."
                    : "Couldn't upload new Health data."
                return uploadedSamples > 0 || uploadedWorkouts > 0
            }
        }

        lastSyncSummary = "Synced \(uploadedSamples) samples, \(uploadedWorkouts) workouts."
        lastUploadError = nil
        settings.lastSyncAt = Date()
        return uploadedSamples > 0 || uploadedWorkouts > 0
    }

    /// Fetches Today without pushing new samples (e.g. on tab appear).
    func refreshToday(_ settings: AppSettings) async {
        guard settings.makeClient() != nil else {
            errorMessage = APIError.notConfigured.localizedDescription
            return
        }
        StoreActivation.activate(store, settings: settings)
        isLoadingToday = true
        errorMessage = nil
        defer { isLoadingToday = false }
        await refreshTodayFromServer(settings, keepPreliminaryOnFailure: false)
    }

    private enum HealthPayloadResult {
        case samples(SyncPayload)
        case readFailed(Error)
        case unavailable
    }

    private func loadHealthPayload(_ settings: AppSettings) async -> HealthPayloadResult? {
        guard HealthKitService.isAvailable else { return .unavailable }
        do {
            let payload = try await health.fetchSamples(
                since: settings.lastSyncAt,
                userId: settings.userId
            )
            return .samples(payload)
        } catch {
            return .readFailed(error)
        }
    }

    /// A 401 signs the user out through `.apiUnauthorized` (see `AppSettings`).
    private func refreshTodayFromServer(
        _ settings: AppSettings,
        keepPreliminaryOnFailure: Bool
    ) async {
        if await store.refresh(.today, force: true) {
            didRefresh(settings)
        } else if !keepPreliminaryOnFailure || today == nil {
            errorMessage = store.today.error
        }
    }

    private func applyHealthReadFailure(_ error: Error) {
        if !healthSyncSucceeded {
            lastSyncSummary = "Couldn't read Health data: \(readable(error))"
        }
    }

    private func readable(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
