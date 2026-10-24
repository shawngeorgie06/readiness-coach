import XCTest
@testable import ReadinessCoach

private struct Boom: Error {}

/// A latch a fake awaits until the test opens it.
@MainActor
private final class Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@MainActor
private final class FakeHealth: HealthSource {
    var canRead = true
    var samples = 2
    /// The user each read was for, in order.
    private(set) var reads: [String] = []
    private var nextGate: Gate?

    /// Holds the next read until the returned gate opens.
    func holdNextRead() -> Gate {
        let gate = Gate()
        nextGate = gate
        return gate
    }

    func fetchSamples(since: Date?, userId: String) async throws -> SyncPayload {
        reads.append(userId)
        let gate = nextGate
        nextGate = nil
        await gate?.wait()
        let samples = (0..<samples).map { index in
            SyncSample(
                hkUuid: "\(userId)-\(index)", type: "heartRate",
                startAt: "2026-10-23T0\(index):00:00.000Z", endAt: "2026-10-23T0\(index):00:30.000Z",
                value: 60, unit: "count/min", metadata: nil
            )
        }
        return SyncPayload(userId: userId, samples: samples, workouts: [])
    }
}

/// Every client the service connects shares this server, which records who asked for what.
private final class FakeServer: @unchecked Sendable {
    private let lock = NSLock()
    private var _uploads: [SyncPayload] = []
    private var _todayUsers: [String] = []
    private var _holdUploads = false
    private var _todayFails: (Int) -> Bool = { _ in false }

    var uploads: [SyncPayload] { lock.withLock { _uploads } }
    /// The user each Today fetch was for, in order.
    var todayUsers: [String] { lock.withLock { _todayUsers } }
    var holdUploads: Bool {
        get { lock.withLock { _holdUploads } }
        set { lock.withLock { _holdUploads = newValue } }
    }
    /// Whether the Today fetch at a call index (from 0) fails.
    var todayFails: (Int) -> Bool {
        get { lock.withLock { _todayFails } }
        set { lock.withLock { _todayFails = newValue } }
    }

    func client(for userId: String) -> SyncAPI { Client(server: self, userId: userId) }

    fileprivate func today(for userId: String) throws -> Fetch<TodayDTO> {
        let fails = lock.withLock { () -> Bool in
            _todayUsers.append(userId)
            return _todayFails(_todayUsers.count - 1)
        }
        if fails { throw Boom() }
        return .fresh(makeToday(), etag: nil)
    }

    fileprivate func upload(_ payload: SyncPayload) async -> SyncResult {
        lock.withLock { _uploads.append(payload) }
        // Bounded, so a regression fails its assertions instead of hanging the suite.
        for _ in 0..<1500 where holdUploads {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return SyncResult(ok: true, samples: payload.samples.count, workouts: payload.workouts.count)
    }

    private struct Client: SyncAPI {
        let server: FakeServer
        let userId: String

        func today(on day: LocalDay, etag: String?) async throws -> Fetch<TodayDTO> { try server.today(for: userId) }
        func body(days: Int, on day: LocalDay, etag: String?) async throws -> Fetch<BodyResponse> {
            .fresh(BodyResponse(days: days, daily: []), etag: nil)
        }
        func sleep(days: Int, on day: LocalDay, etag: String?) async throws -> Fetch<SleepDetailResponse> {
            .fresh(SleepDetailResponse(days: days, data: []), etag: nil)
        }
        func train(days: Int, on day: LocalDay, etag: String?) async throws -> Fetch<TrainResponse> {
            .fresh(TrainResponse(days: days, data: []), etag: nil)
        }
        func history(days: Int, on day: LocalDay, etag: String?) async throws -> Fetch<ReadinessHistoryResponse> {
            .fresh(ReadinessHistoryResponse(days: days, data: []), etag: nil)
        }
        /// One chunk per sample, so a test can act between chunks.
        func syncChunks(_ payload: SyncPayload) -> [SyncPayload] {
            payload.samples.map { SyncPayload(userId: payload.userId, samples: [$0], workouts: []) }
        }
        func syncChunk(_ payload: SyncPayload) async throws -> SyncResult { await server.upload(payload) }
    }
}

private func makeToday() -> TodayDTO {
    let pillar = PillarScore(score: 70, drivers: [])
    return TodayDTO(
        date: "2026-10-23", readiness: 72, decision: .maintain, calibrating: false,
        pillars: Pillars(sleep: pillar, recovery: pillar, load: pillar),
        overridesApplied: [], confidence: "high", missing: [], sleepPending: nil,
        advisor: AdvisorNote(decision: .maintain, why: [], prescription: "", ifIgnored: "", source: "template")
    )
}

@MainActor
final class SyncServiceTests: XCTestCase {
    /// AppSettings keeps credentials in the Keychain; these tests put back whatever was there.
    private static let credentialKeys = ["apiToken", "sessionToken"]
    private var savedCredentials: [String: String] = [:]
    private var suiteName = ""
    private var directory: URL!
    private var cache: ResourceDiskCache!
    private var day = "2026-10-23"
    private var offset = -240
    private var settings: AppSettings!
    private var store: AppStore!
    private var health: FakeHealth!
    private var server: FakeServer!
    private var sync: SyncService!

    override func setUp() async throws {
        savedCredentials = [:]
        for key in Self.credentialKeys {
            savedCredentials[key] = KeychainStore.get(key)
            KeychainStore.remove(key)
        }
        suiteName = "SyncServiceTests-\(UUID().uuidString)"
        settings = AppSettings(defaults: UserDefaults(suiteName: suiteName)!)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("rc-sync-\(UUID().uuidString)")
        cache = ResourceDiskCache(directory: directory)
        store = AppStore(
            cache: cache,
            localDay: { [unowned self] in LocalDay(date: self.day, utcOffsetMinutes: self.offset) },
            notifications: NotificationCenter()
        )
        health = FakeHealth()
        server = FakeServer()
        sync = SyncService(store: store, health: health, connect: { [server] in server!.client(for: $0.userId) })
    }

    override func tearDown() async throws {
        for key in Self.credentialKeys {
            if let value = savedCredentials[key] { KeychainStore.set(value, for: key) } else { KeychainStore.remove(key) }
        }
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private var legacyURL: URL { directory.appendingPathComponent("cached-today.json") }

    private func signIn(_ userId: String, token: String) {
        settings.apiBaseURL = "https://example.test"
        settings.apiToken = ""
        settings.userId = userId
        settings.sessionToken = token
    }

    /// What the app does when the user ID changes under it: activate the store for the new user.
    private func switchUser(to userId: String, token: String) {
        signIn(userId, token: token)
        StoreActivation.activate(store, userId: userId, api: server.client(for: userId), legacyURL: legacyURL)
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }

    // MARK: - Today warning

    func testFinalTodayFailureAfterUploadWarnsBesideSavedScore() async {
        signIn("a", token: "sA")
        server.todayFails = { $0 >= 1 }
        await sync.syncNow(settings)

        XCTAssertEqual(server.uploads.count, 2)
        XCTAssertEqual(server.todayUsers, ["a", "a"])
        XCTAssertNotNil(sync.today, "the saved score stays on screen")
        XCTAssertNotNil(sync.todayError)
        XCTAssertEqual(sync.freshness(using: settings), .offline)
    }

    func testDayChangeRefreshFailureWarnsBesideSavedScore() async {
        health.canRead = false
        signIn("a", token: "sA")
        await sync.syncNow(settings)
        XCTAssertNil(sync.todayError)

        server.todayFails = { _ in true }
        day = "2026-10-24"
        store.noteDayMayHaveChanged()
        await waitUntil { self.store.today.error != nil }

        XCTAssertNotNil(sync.today)
        XCTAssertNotNil(sync.todayError)
        XCTAssertEqual(sync.freshness(using: settings), .offline)
    }

    func testOffsetChangeRefreshFailureWarnsBesideSavedScore() async {
        health.canRead = false
        signIn("a", token: "sA")
        await sync.syncNow(settings)

        server.todayFails = { _ in true }
        offset = -300
        store.noteDayMayHaveChanged()
        await waitUntil { self.store.today.error != nil }

        XCTAssertNotNil(sync.today)
        XCTAssertEqual(sync.freshness(using: settings), .offline)
    }
}
