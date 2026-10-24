import Foundation

/// Where Health samples come from: `HealthKitService` in the app.
@MainActor
protocol HealthSource {
    var canRead: Bool { get }
    func fetchSamples(since: Date?, userId: String) async throws -> SyncPayload
}

extension HealthKitService: HealthSource {
    var canRead: Bool { Self.isAvailable }
}

/// The server a sync talks to: Today reads plus the chunked Health upload.
/// `APIClient` in the app.
protocol SyncAPI: ReadAPI {
    func syncChunks(_ payload: SyncPayload) -> [SyncPayload]
    func syncChunk(_ payload: SyncPayload) async throws -> SyncResult
}

extension APIClient: SyncAPI {}

/// Coordinates HealthKit sync and Today refresh, and holds the observable state
/// the views render. One instance is shared through the environment.
@MainActor
final class SyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var errorMessage: String?
    @Published var lastSyncSummary: String?
    @Published var lastUploadError: String?
    @Published var uploadingCount: Int?

    private let store: AppStore
    private let health: HealthSource
    private let connect: (APIClient) -> SyncAPI
    private var lastAutoSyncAt: Date?
    private var lastBackgroundSyncAt: Date?

    private static let legacyCacheKey = "cachedTodayJSON"

    /// The last-known Today, served from the store (cached on disk, so it shows
    /// immediately on launch while a refresh runs).
    var today: TodayDTO? { store.today.value }

    /// Why Today couldn't refresh, if it couldn't: a sync failure, or the last
    /// Today fetch failing however it was started (a sync's final refresh, a day
    /// or time zone change). The saved score stays on screen beside it.
    var todayError: String? { errorMessage ?? store.today.error }

    init(
        store: AppStore,
        health: HealthSource? = nil,
        connect: @escaping (APIClient) -> SyncAPI = { $0 }
    ) {
        self.store = store
        self.health = health ?? HealthKitService()
        self.connect = connect
        // Remove the pre-v1.3.4 UserDefaults cache after upgrading.
        UserDefaults.standard.removeObject(forKey: Self.legacyCacheKey)
        store.onSessionEnd { [weak self] in self?.sessionEnded() }
    }

    /// Sign-out, clear, or user switch: stop the sync so it sends no further chunk
    /// or retry, and drop the old account's progress and messages. A request
    /// already on the wire can't be recalled; its run writes nothing when it lands.
    private func sessionEnded() {
        syncRun?.task.cancel()
        syncRun = nil
        isSyncing = false
        uploadingCount = nil
        errorMessage = nil
        lastSyncSummary = nil
        lastUploadError = nil
    }

    /// Records a successful server refresh: stamp the display time.
    private func didRefresh(_ settings: AppSettings) {
        settings.lastRefreshAt = Date()
        errorMessage = nil
    }

    /// Foreground-triggered sync, debounced so rapid app switches don't re-sync.
    func autoSync(_ settings: AppSettings) async {
        guard settings.isReady else { return }
        if let last = lastAutoSyncAt, Date().timeIntervalSince(last) < 30 { return }
        lastAutoSyncAt = Date()
        await syncNow(settings)
    }

    /// HealthKit background delivery — debounced harder than foreground sync.
    /// Skipped once signed out: the HealthKit observer outlives the signed-in UI and
    /// must not repopulate the cache that sign-out just cleared.
    func backgroundSync(_ settings: AppSettings) async {
        guard settings.isReady else { return }
        if let last = lastBackgroundSyncAt, Date().timeIntervalSince(last) < 300 { return }
        lastBackgroundSyncAt = Date()
        await syncNow(settings)
    }

    func freshness(using settings: AppSettings) -> DataFreshness {
        SyncFreshness.evaluate(today: today, settings: settings, errorMessage: todayError)
    }

    /// Who a sync is for: the store session plus the client's server, user, and
    /// credential. A sign-out, clear, user switch, or credential change ends it.
    private struct Owner: Equatable {
        let session: Int
        let identity: APIClient.Identity
    }

    /// The sync currently in flight, if any. Owned here rather than by a view.
    private var syncRun: (id: Int, owner: Owner, task: Task<Void, Never>)?
    private var syncRunCount = 0

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
    /// take the upload down with them. A second caller for the same session
    /// joins the run already in flight instead of starting a competing one; a
    /// caller for another session or credentials starts its own.
    func syncNow(_ settings: AppSettings) async {
        guard let client = settings.makeClient() else {
            errorMessage = APIError.notConfigured.localizedDescription
            return
        }
        let api = connect(client)
        StoreActivation.activate(store, userId: client.userId, api: api)
        let owner = Owner(session: store.session, identity: client.identity)
        if let run = syncRun, run.owner == owner {
            await run.task.value
            return
        }
        syncRun?.task.cancel()
        syncRunCount += 1
        let id = syncRunCount
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performSync(settings, api: api, run: id)
        }
        syncRun = (id, owner, task)
        await task.value
        if syncRun?.id == id { syncRun = nil }
    }

    /// Whether run `id` still owns the sync: no other run replaced it, and the
    /// session and credentials it started under are still the current ones.
    /// Checked after every wait, before anything else is sent or recorded.
    private func owns(_ id: Int, _ settings: AppSettings) -> Bool {
        guard let run = syncRun, run.id == id else { return false }
        return run.owner.session == store.session && settings.makeClient()?.identity == run.owner.identity
    }

    private func performSync(_ settings: AppSettings, api: SyncAPI, run: Int) async {
        isSyncing = true
        errorMessage = nil
        lastUploadError = nil
        defer {
            if syncRun?.id == run { isSyncing = false; uploadingCount = nil }
        }

        async let healthPayloadTask = loadHealthPayload(settings)
        async let preliminaryTodayTask = store.refresh(.today, force: true)

        let healthPayload = await healthPayloadTask
        let preliminaryTodayLoaded = await preliminaryTodayTask
        guard owns(run, settings) else { return }

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
                    uploadedNewSamples = await uploadHealth(payload, api: api, settings: settings, run: run)
                    guard owns(run, settings) else { return }
                }
            case .readFailed(let error):
                applyHealthReadFailure(error)
            case .unavailable:
                lastSyncSummary = "HealthKit unavailable — showing server data only."
            }
        }

        if uploadedNewSamples {
            store.noteUploadedSamples()
            await refreshTodayFromServer(settings, keepPreliminaryOnFailure: true, run: run)
        } else if !preliminaryTodayLoaded {
            await refreshTodayFromServer(settings, keepPreliminaryOnFailure: false, run: run)
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
    /// Returns whether anything new reached the server. Stops, sending and
    /// recording nothing more, once `run` no longer owns the sync.
    private func uploadHealth(
        _ payload: SyncPayload,
        api: SyncAPI,
        settings: AppSettings,
        run: Int
    ) async -> Bool {
        let chunks = api.syncChunks(payload)
        let total = payload.samples.count
        var uploadedSamples = 0
        var uploadedWorkouts = 0
        uploadingCount = total

        for chunk in chunks {
            guard owns(run, settings) else { return false }
            let outcome: Result<SyncResult, Error>
            do {
                outcome = .success(try await api.syncChunk(chunk))
            } catch {
                outcome = .failure(error)
            }
            // A chunk already sent can't be recalled, but after the session ends
            // its result belongs to nobody: no watermark, no summary.
            guard owns(run, settings) else { return false }
            do {
                let result = try outcome.get()
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

    private enum HealthPayloadResult {
        case samples(SyncPayload)
        case readFailed(Error)
        case unavailable
    }

    private func loadHealthPayload(_ settings: AppSettings) async -> HealthPayloadResult? {
        guard health.canRead else { return .unavailable }
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
        keepPreliminaryOnFailure: Bool,
        run: Int
    ) async {
        let loaded = await store.refresh(.today, force: true)
        guard owns(run, settings) else { return }
        if loaded {
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
