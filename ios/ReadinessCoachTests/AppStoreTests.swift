import XCTest
@testable import ReadinessCoach

private final class FakeReadAPI: ReadAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _etags: [String: String?] = [:]
    private var _hold = false
    var todayResult: () throws -> Fetch<TodayDTO> = { .fresh(makeToday(), etag: "t1") }
    var bodyResult: () throws -> Fetch<BodyResponse> = { .fresh(BodyResponse(days: 30, daily: []), etag: "b1") }
    var sleepResult: () throws -> Fetch<SleepDetailResponse> = { .fresh(SleepDetailResponse(days: 30, data: []), etag: "s1") }
    var trainResult: () throws -> Fetch<TrainResponse> = { .fresh(TrainResponse(days: 28, data: []), etag: "r1") }

    var calls: [String] { lock.withLock { _calls } }
    func etag(for name: String) -> String?? { lock.withLock { _etags[name] } }
    func setHold(_ value: Bool) { lock.withLock { _hold = value } }

    private func record(_ name: String, _ etag: String?) async {
        lock.withLock { _calls.append(name); _etags[name] = etag }
        while lock.withLock({ _hold }) { try? await Task.sleep(nanoseconds: 2_000_000) }
    }

    func today(etag: String?) async throws -> Fetch<TodayDTO> { await record("today", etag); return try todayResult() }
    func body(days: Int, etag: String?) async throws -> Fetch<BodyResponse> { await record("body", etag); return try bodyResult() }
    func sleep(days: Int, etag: String?) async throws -> Fetch<SleepDetailResponse> { await record("sleep(\(days))", etag); return try sleepResult() }
    func train(days: Int, etag: String?) async throws -> Fetch<TrainResponse> { await record("train", etag); return try trainResult() }
    func history(days: Int, etag: String?) async throws -> Fetch<ReadinessHistoryResponse> {
        await record("history(\(days))", etag)
        return .fresh(ReadinessHistoryResponse(days: days, data: []), etag: nil)
    }
}

private func makeToday(readiness: Double = 72) -> TodayDTO {
    let pillar = PillarScore(score: 70, drivers: [])
    return TodayDTO(
        date: "2026-10-23", readiness: readiness, decision: .maintain, calibrating: false,
        pillars: Pillars(sleep: pillar, recovery: pillar, load: pillar),
        overridesApplied: [], confidence: "high", missing: [], sleepPending: nil,
        advisor: AdvisorNote(decision: .maintain, why: [], prescription: "", ifIgnored: "", source: "template")
    )
}

private struct Boom: Error {}

@MainActor
final class AppStoreTests: XCTestCase {
    private var directory: URL!
    private var cache: ResourceDiskCache!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var day = "2026-10-23"
    private var api: FakeReadAPI!
    private var store: AppStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("rc-store-\(UUID().uuidString)")
        cache = ResourceDiskCache(directory: directory)
        api = FakeReadAPI()
        store = AppStore(cache: cache, now: { [unowned self] in self.clock }, localDay: { [unowned self] in self.day })
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func seed<V: Codable>(_ key: ResourceKey, _ value: V, user: String = "u1", ageSeconds: TimeInterval = 10, etag: String? = "old") {
        cache.save(key, CachedEnvelope(userId: user, day: day, fetchedAt: clock.addingTimeInterval(-ageSeconds), etag: etag, value: value))
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }

    func testActivateShowsCachedValuesWithoutNetwork() {
        seed(.today, makeToday(readiness: 61))
        store.activate(userId: "u1", api: api)
        XCTAssertEqual(store.today.value?.readiness, 61)
        XCTAssertEqual(api.calls, [])
    }

    func testFreshResourceIsNotRefetched() async {
        seed(.body, BodyResponse(days: 30, daily: []))
        store.activate(userId: "u1", api: api)
        let ok = await store.refresh(.body)
        XCTAssertTrue(ok)
        XCTAssertEqual(api.calls, [])
    }

    func testStaleResourceIsRefetched() async {
        seed(.body, BodyResponse(days: 30, daily: []), ageSeconds: 301)
        store.activate(userId: "u1", api: api)
        await store.refresh(.body)
        XCTAssertEqual(api.calls, ["body"])
        XCTAssertEqual(store.body.etag, "b1")
    }

    func testForceRefetchesFreshResource() async {
        seed(.body, BodyResponse(days: 30, daily: []))
        store.activate(userId: "u1", api: api)
        await store.refresh(.body, force: true)
        XCTAssertEqual(api.calls, ["body"])
    }

    func testConcurrentRefreshesShareOneRequest() async {
        store.activate(userId: "u1", api: api)
        api.setHold(true)
        async let first = store.refresh(.body, force: true)
        async let second = store.refresh(.body, force: true)
        await waitUntil { !self.api.calls.isEmpty }
        api.setHold(false)
        let results = await [first, second]
        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(api.calls, ["body"])
    }

    func testNotModifiedKeepsValueAndBumpsFetchedAt() async {
        seed(.body, BodyResponse(days: 7, daily: []), ageSeconds: 400, etag: "W/1")
        store.activate(userId: "u1", api: api)
        api.bodyResult = { .notModified }
        let ok = await store.refresh(.body)
        XCTAssertTrue(ok)
        XCTAssertEqual(api.etag(for: "body"), "W/1")
        XCTAssertEqual(store.body.value?.days, 7)
        XCTAssertEqual(store.body.fetchedAt, clock)
        XCTAssertEqual(store.body.etag, "W/1")
        XCTAssertEqual(cache.load(.body, userId: "u1", as: BodyResponse.self)?.fetchedAt, clock)
    }

    func testErrorKeepsCachedValue() async {
        seed(.body, BodyResponse(days: 7, daily: []), ageSeconds: 400)
        store.activate(userId: "u1", api: api)
        api.bodyResult = { throw Boom() }
        let ok = await store.refresh(.body)
        XCTAssertFalse(ok)
        XCTAssertEqual(store.body.value?.days, 7)
        XCTAssertNotNil(store.body.error)
        XCTAssertFalse(store.body.isRefreshing)
        // A second call proves the in-flight entry was cleared after the error.
        await store.refresh(.body)
        XCTAssertEqual(api.calls, ["body", "body"])
    }

    func testSuccessfulTodayRefreshPrefetchesPillars() async {
        store.activate(userId: "u1", api: api)
        await store.refresh(.today, force: true)
        await waitUntil { Set(self.api.calls).isSuperset(of: ["body", "sleep(30)", "train"]) }
        XCTAssertTrue(Set(api.calls).isSuperset(of: ["today", "body", "sleep(30)", "train"]))
    }

    func testFailedTodayRefreshDoesNotPrefetch() async {
        store.activate(userId: "u1", api: api)
        api.todayResult = { throw Boom() }
        await store.refresh(.today, force: true)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(api.calls, ["today"])
    }

    func testUploadMakesResourcesStale() async {
        seed(.body, BodyResponse(days: 30, daily: []))
        store.activate(userId: "u1", api: api)
        await store.refresh(.body)
        XCTAssertEqual(api.calls, [])
        store.noteUploadedSamples()
        await store.refresh(.body)
        XCTAssertEqual(api.calls, ["body"])
        await store.refresh(.body)
        XCTAssertEqual(api.calls, ["body"])
    }

    func testIfNoneMatchOnlyWithCachedValue() async {
        store.activate(userId: "u1", api: api)
        await store.refresh(.body)
        XCTAssertEqual(api.etag(for: "body"), .some(nil))
        await store.refresh(.body, force: true)
        XCTAssertEqual(api.etag(for: "body"), "b1")
    }

    func testResetClearsMemoryAndDisk() async {
        seed(.today, makeToday())
        store.activate(userId: "u1", api: api)
        store.reset()
        XCTAssertNil(store.today.value)
        XCTAssertNil(cache.load(.today, userId: "u1", as: TodayDTO.self))
        XCTAssertEqual(store.dataVersion, 0)
        let ok = await store.refresh(.today)
        XCTAssertFalse(ok)
        XCTAssertNil(store.today.error)
    }

    func testActivateDifferentUserClearsPreviousUsersValues() {
        seed(.today, makeToday(readiness: 61), user: "u1")
        store.activate(userId: "u1", api: api)
        store.noteUploadedSamples()
        store.activate(userId: "u2", api: api)
        XCTAssertNil(store.today.value)
        XCTAssertEqual(store.dataVersion, 0)
    }

    func testRefreshCompletingAfterResetDoesNotWrite() async {
        store.activate(userId: "u1", api: api)
        api.setHold(true)
        let pending = Task { await store.refresh(.body, force: true) }
        await waitUntil { !self.api.calls.isEmpty }
        store.reset()
        api.setHold(false)
        let ok = await pending.value
        XCTAssertFalse(ok)
        XCTAssertNil(store.body.value)
        XCTAssertNil(cache.load(.body, userId: "u1", as: BodyResponse.self))
    }

    func testRefreshCompletingAfterUserSwitchDoesNotWrite() async {
        store.activate(userId: "u1", api: api)
        api.setHold(true)
        let pending = Task { await store.refresh(.body, force: true) }
        await waitUntil { !self.api.calls.isEmpty }
        store.activate(userId: "u2", api: api)
        api.setHold(false)
        _ = await pending.value
        XCTAssertNil(store.body.value)
        XCTAssertNil(cache.load(.body, userId: "u1", as: BodyResponse.self))
    }
}
