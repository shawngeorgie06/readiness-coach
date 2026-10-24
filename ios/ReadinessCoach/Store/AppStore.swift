import Foundation
import Observation

/// In-memory home for every server resource. Views read cached values
/// immediately; `refresh` revalidates in the background, dedupes concurrent
/// calls per key, and persists results through `ResourceDiskCache`.
@MainActor @Observable
final class AppStore {
    var today = Resource<TodayDTO>()
    var body = Resource<BodyResponse>()
    var train = Resource<TrainResponse>()
    var sleep: [Int: Resource<SleepDetailResponse>] = [:]
    var history: [Int: Resource<ReadinessHistoryResponse>] = [:]
    private(set) var dataVersion = 0
    /// The local day and UTC offset last seen. Screens include it in their
    /// `.task(id:)`, so a day or time zone change while open re-runs their refresh
    /// and redraws their date-keyed charts.
    private(set) var currentDay: LocalDay

    @ObservationIgnored private let cache: ResourceDiskCache
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let localDay: () -> LocalDay
    @ObservationIgnored private let notifications: NotificationCenter
    @ObservationIgnored private var dayObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var userId: String?
    @ObservationIgnored private var api: ReadAPI?
    /// Running fetches per key, with the data version and local day each one started under.
    @ObservationIgnored private var inFlight: [ResourceKey: (task: Task<Bool, Never>, version: Int, day: LocalDay)] = [:]
    /// Bumped whenever memory is cleared; a fetch that started under an older
    /// session never writes its result.
    @ObservationIgnored private var session = 0

    private static let rangeDays = [7, 30, 90]
    private static let bodyDays = 30
    private static let trainDays = 28

    init(
        cache: ResourceDiskCache,
        now: @escaping () -> Date = Date.init,
        localDay: @escaping () -> LocalDay = { .current() },
        notifications: NotificationCenter = .default
    ) {
        self.cache = cache
        self.now = now
        self.localDay = localDay
        self.notifications = notifications
        currentDay = localDay()
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
            dayObservers.append(notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.noteDayMayHaveChanged() }
            })
        }
    }

    deinit {
        dayObservers.forEach(notifications.removeObserver)
    }

    /// Loads every cached resource for `userId` from disk; sets the API used by refreshes.
    func activate(userId: String, api: ReadAPI?) {
        if self.userId != userId { clearMemory() }
        self.userId = userId
        self.api = api
        load(.today, into: \.today)
        load(.body, into: \.body)
        load(.train, into: \.train)
        for days in Self.rangeDays {
            if sleep[days]?.value == nil, let loaded = Self.resource(
                cache.load(.sleep(days: days), userId: userId, as: SleepDetailResponse.self)
            ) { sleep[days] = loaded }
            if history[days]?.value == nil, let loaded = Self.resource(
                cache.load(.history(days: days), userId: userId, as: ReadinessHistoryResponse.self)
            ) { history[days] = loaded }
        }
    }

    /// Fetches `key` unless fresh (or `force`), deduping concurrent calls per key. Returns success.
    @discardableResult
    func refresh(_ key: ResourceKey, force: Bool = false) async -> Bool {
        guard let api, let userId else { return false }
        if let running = inFlight[key] {
            let token = session
            let ok = await running.task.value
            // Started before the latest upload, or on another local day or UTC offset,
            // so its result is already stale; fetch again, unless the session ended while waiting.
            let stale = running.version < dataVersion || running.day != localDay()
            guard stale, token == session else { return ok }
            return await refresh(key, force: force)
        }
        if !force && !needsRevalidation(key) { return true }

        let request = Request(userId: userId, token: session, version: dataVersion, day: localDay())
        setRefreshing(key, true)
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            let ok = await self.fetch(key, api: api, request)
            if request.token == self.session {
                self.inFlight[key] = nil
                self.setRefreshing(key, false)
                if ok && key == .today { self.prefetchPillars() }
            }
            return ok
        }
        inFlight[key] = (task, request.version, request.day)
        return await task.value
    }

    /// Background, non-awaited: body, sleep(30), train, each only if it needs revalidation.
    func prefetchPillars() {
        for key in [ResourceKey.body, .sleep(days: 30), .train] where needsRevalidation(key) {
            Task { @MainActor [weak self] in await self?.refresh(key) }
        }
    }

    func taskID(_ key: ResourceKey) -> ResourceTaskID {
        ResourceTaskID(key: key, day: currentDay)
    }

    /// Refetches Today, and through it the pillars, when the local day or UTC offset
    /// differs from the last one seen. Runs on the system day and time zone change
    /// notifications and when the app becomes active, so a screen left open across
    /// midnight moves to the new day.
    func noteDayMayHaveChanged() {
        let day = localDay()
        guard day != currentDay else { return }
        currentDay = day
        guard api != nil else { return }
        Task { @MainActor [weak self] in await self?.refresh(.today, force: true) }
    }

    /// Called by SyncService after an upload stored new samples. A refresh that joins a pre-upload request fetches again once it finishes.
    func noteUploadedSamples() {
        dataVersion += 1
    }

    /// Sign-out / account deletion: clears memory and disk.
    func reset() {
        clearMemory()
        userId = nil
        api = nil
        cache.removeAll()
    }

    // MARK: - Internals

    private func clearMemory() {
        session += 1
        inFlight.values.forEach { $0.task.cancel() }
        inFlight = [:]
        today = Resource()
        body = Resource()
        train = Resource()
        sleep = [:]
        history = [:]
        dataVersion = 0
    }

    private func needsRevalidation(_ key: ResourceKey) -> Bool {
        func check<V>(_ resource: Resource<V>) -> Bool {
            resource.needsRevalidation(now: now(), today: localDay().date, currentDataVersion: dataVersion)
        }
        switch key {
        case .today: return check(today)
        case .body: return check(body)
        case .train: return check(train)
        case .sleep(let days): return check(sleep[days] ?? Resource())
        case .history(let days): return check(history[days] ?? Resource())
        }
    }

    /// What a fetch was started under: its session, the data version it will
    /// stamp, and the local day it asks for and stamps.
    private struct Request {
        let userId: String
        let token: Int
        let version: Int
        let day: LocalDay
    }

    private func fetch(_ key: ResourceKey, api: ReadAPI, _ request: Request) async -> Bool {
        let day = request.day
        switch key {
        case .today:
            return await run(key, request, \.today) { try await api.today(on: day, etag: $0) }
        case .body:
            return await run(key, request, \.body) { try await api.body(days: Self.bodyDays, on: day, etag: $0) }
        case .train:
            return await run(key, request, \.train) { try await api.train(days: Self.trainDays, on: day, etag: $0) }
        case .sleep(let days):
            return await run(key, request, slot: { $0.sleep[days] ?? Resource() }, store: { $0.sleep[days] = $1 }) {
                try await api.sleep(days: days, on: day, etag: $0)
            }
        case .history(let days):
            return await run(key, request, slot: { $0.history[days] ?? Resource() }, store: { $0.history[days] = $1 }) {
                try await api.history(days: days, on: day, etag: $0)
            }
        }
    }

    private func run<V: Codable>(
        _ key: ResourceKey, _ request: Request,
        _ path: ReferenceWritableKeyPath<AppStore, Resource<V>>,
        load: @escaping (String?) async throws -> Fetch<V>
    ) async -> Bool {
        await run(key, request, slot: { $0[keyPath: path] }, store: { $0[keyPath: path] = $1 }, load: load)
    }

    private func run<V: Codable>(
        _ key: ResourceKey, _ request: Request,
        slot: (AppStore) -> Resource<V>,
        store: (AppStore, Resource<V>) -> Void,
        load: (String?) async throws -> Fetch<V>
    ) async -> Bool {
        let current = slot(self)
        // Only revalidate against an ETag when there is a value to keep.
        let etag = current.value == nil ? nil : current.etag
        do {
            let result = try await load(etag)
            guard request.token == session else { return false }
            var next = slot(self)
            switch result {
            case .fresh(let value, let newEtag):
                next.value = value
                next.etag = newEtag
            case .notModified:
                guard next.value != nil else { return false }
            }
            // The day the request asked for, so a response landing after midnight still revalidates.
            next.day = request.day.date
            next.fetchedAt = now()
            next.dataVersion = request.version
            next.error = nil
            store(self, next)
            if let value = next.value, let day = next.day, let fetchedAt = next.fetchedAt {
                cache.save(key, CachedEnvelope(userId: request.userId, day: day, fetchedAt: fetchedAt, etag: next.etag, value: value))
            }
            return true
        } catch {
            guard request.token == session else { return false }
            var next = slot(self)
            next.error = error.localizedDescription
            store(self, next)
            return false
        }
    }

    private func setRefreshing(_ key: ResourceKey, _ value: Bool) {
        switch key {
        case .today: today.isRefreshing = value
        case .body: body.isRefreshing = value
        case .train: train.isRefreshing = value
        case .sleep(let days): sleep[days, default: Resource()].isRefreshing = value
        case .history(let days): history[days, default: Resource()].isRefreshing = value
        }
    }

    private func load<V: Codable>(_ key: ResourceKey, into path: ReferenceWritableKeyPath<AppStore, Resource<V>>) {
        guard let userId, self[keyPath: path].value == nil,
              let loaded = Self.resource(cache.load(key, userId: userId, as: V.self))
        else { return }
        self[keyPath: path] = loaded
    }

    private static func resource<V>(_ envelope: CachedEnvelope<V>?) -> Resource<V>? {
        guard let envelope else { return nil }
        return Resource(value: envelope.value, day: envelope.day, fetchedAt: envelope.fetchedAt, etag: envelope.etag)
    }
}
