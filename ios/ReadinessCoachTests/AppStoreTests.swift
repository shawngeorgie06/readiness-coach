import XCTest
@testable import ReadinessCoach

private final class FakeReadAPI: ReadAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _etags: [String: String?] = [:]
    private var _days: [LocalDay] = []
    private var _hold = false
    var todayResult: () throws -> Fetch<TodayDTO> = { .fresh(makeToday(), etag: "t1") }
    var bodyResult: () throws -> Fetch<BodyResponse> = { .fresh(BodyResponse(days: 30, daily: []), etag: "b1") }
    var sleepResult: () throws -> Fetch<SleepDetailResponse> = { .fresh(SleepDetailResponse(days: 30, data: []), etag: "s1") }
    var trainResult: () throws -> Fetch<TrainResponse> = { .fresh(TrainResponse(days: 28, data: []), etag: "r1") }

    var calls: [String] { lock.withLock { _calls } }
    func etag(for name: String) -> String?? { lock.withLock { _etags[name] } }
    /// The local day each call asked for, in call order.
    var days: [LocalDay] { lock.withLock { _days } }
    func days(for name: String) -> [LocalDay] { lock.withLock { zip(_calls, _days).filter { $0.0 == name }.map(\.1) } }
    func setHold(_ value: Bool) { lock.withLock { _hold = value } }

    private func record(_ name: String, _ day: LocalDay, _ etag: String?) async {
        lock.withLock { _calls.append(name); _days.append(day); _etags[name] = etag }
        while lock.withLock({ _hold }) { try? await Task.sleep(nanoseconds: 2_000_000) }
    }

    func today(on day: LocalDay, etag: String?) async throws -> Fetch<TodayDTO> { await record("today", day, etag); return try todayResult() }
    func body(days: Int, on day: LocalDay, etag: String?) async throws -> Fetch<BodyResponse> { await record("body", day, etag); return try bodyResult() }
    func sleep(days: Int, on day: LocalDay, etag: String?) async throws -> Fetch<SleepDetailResponse> {
        await record("sleep(\(days))", day, etag)
        return try sleepResult()
    }
    func train(days: Int, on day: LocalDay, etag: String?) async throws -> Fetch<TrainResponse> { await record("train", day, etag); return try trainResult() }
    func history(days: Int, on day: LocalDay, etag: String?) async throws -> Fetch<ReadinessHistoryResponse> {
        await record("history(\(days))", day, etag)
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
    private var offset = -240
    private var notifications: NotificationCenter!
    private var api: FakeReadAPI!
    private var store: AppStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("rc-store-\(UUID().uuidString)")
        cache = ResourceDiskCache(directory: directory)
        api = FakeReadAPI()
        notifications = NotificationCenter()
        store = AppStore(
            cache: cache, now: { [unowned self] in self.clock },
            localDay: { [unowned self] in LocalDay(date: self.day, utcOffsetMinutes: self.offset) },
            notifications: notifications
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func seed<V: Codable>(_ key: ResourceKey, _ value: V, user: String = "u1", ageSeconds: TimeInterval = 10, etag: String? = "old") {
        cache.save(key, CachedEnvelope(userId: user, day: day, utcOffsetMinutes: offset, fetchedAt: clock.addingTimeInterval(-ageSeconds), etag: etag, value: value))
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

    // MARK: - Generation and request day

    func testRefreshAfterUploadDoesNotJoinPreUploadFetch() async {
        store.activate(userId: "u1", api: api)
        api.setHold(true)
        let preUpload = Task { await store.refresh(.body, force: true) }
        await waitUntil { self.api.calls == ["body"] }
        store.noteUploadedSamples()
        let postUpload = Task { await store.refresh(.body) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        api.setHold(false)
        _ = await preUpload.value
        let ok = await postUpload.value
        XCTAssertTrue(ok)
        XCTAssertEqual(api.calls, ["body", "body"])
        XCTAssertEqual(store.body.dataVersion, store.dataVersion)
        XCTAssertFalse(store.body.needsRevalidation(now: clock, today: LocalDay(date: day, utcOffsetMinutes: offset), currentDataVersion: store.dataVersion))
    }

    func testForcedTodayAfterUploadDoesNotReturnPreUploadFetch() async {
        store.activate(userId: "u1", api: api)
        api.setHold(true)
        let preUpload = Task { await store.refresh(.today, force: true) }
        await waitUntil { self.api.calls == ["today"] }
        store.noteUploadedSamples()
        let postUpload = Task { await store.refresh(.today, force: true) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        api.todayResult = { .fresh(makeToday(readiness: 80), etag: "t2") }
        api.setHold(false)
        _ = await preUpload.value
        let ok = await postUpload.value
        XCTAssertTrue(ok)
        XCTAssertEqual(api.calls.filter { $0 == "today" }.count, 2)
        XCTAssertEqual(store.today.value?.readiness, 80)
        XCTAssertEqual(store.today.dataVersion, 1)
    }

    func testRefreshesOfOneGenerationStillShareARequestAfterUpload() async {
        store.activate(userId: "u1", api: api)
        store.noteUploadedSamples()
        api.setHold(true)
        async let first = store.refresh(.body, force: true)
        async let second = store.refresh(.body)
        await waitUntil { !self.api.calls.isEmpty }
        api.setHold(false)
        let results = await [first, second]
        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(api.calls, ["body"])
    }

    func testRefreshWaitingOnStaleFetchStopsWhenSignedOut() async {
        store.activate(userId: "u1", api: api)
        api.setHold(true)
        let preUpload = Task { await store.refresh(.body, force: true) }
        await waitUntil { self.api.calls == ["body"] }
        store.noteUploadedSamples()
        let waiting = Task { await store.refresh(.body) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        store.reset()
        api.setHold(false)
        _ = await preUpload.value
        let ok = await waiting.value
        XCTAssertFalse(ok)
        XCTAssertEqual(api.calls, ["body"])
        XCTAssertNil(store.body.value)
    }

    func testRefreshWaitingOnStaleFetchDoesNotFetchForNextUser() async {
        store.activate(userId: "u1", api: api)
        api.setHold(true)
        let preUpload = Task { await store.refresh(.body, force: true) }
        await waitUntil { self.api.calls == ["body"] }
        store.noteUploadedSamples()
        let waiting = Task { await store.refresh(.body) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        store.activate(userId: "u2", api: api)
        api.setHold(false)
        _ = await preUpload.value
        let ok = await waiting.value
        XCTAssertFalse(ok)
        XCTAssertEqual(api.calls, ["body"])
        XCTAssertNil(store.body.value)
    }

    func testFreshFetchCrossingMidnightKeepsItsRequestDay() async {
        store.activate(userId: "u1", api: api)
        api.setHold(true)
        let pending = Task { await store.refresh(.body, force: true) }
        await waitUntil { self.api.calls == ["body"] }
        day = "2026-10-24"
        api.setHold(false)
        _ = await pending.value
        XCTAssertEqual(store.body.day, "2026-10-23")
        XCTAssertEqual(cache.load(.body, userId: "u1", as: BodyResponse.self)?.day, "2026-10-23")
        await store.refresh(.body)
        XCTAssertEqual(api.calls, ["body", "body"])
        XCTAssertEqual(api.days, [LocalDay(date: "2026-10-23", utcOffsetMinutes: -240), LocalDay(date: "2026-10-24", utcOffsetMinutes: -240)])
        XCTAssertEqual(store.body.day, "2026-10-24")
    }

    func testNotModifiedCrossingMidnightKeepsItsRequestDay() async {
        seed(.body, BodyResponse(days: 7, daily: []), ageSeconds: 400, etag: "W/1")
        store.activate(userId: "u1", api: api)
        api.bodyResult = { .notModified }
        api.setHold(true)
        let pending = Task { await store.refresh(.body) }
        await waitUntil { self.api.calls == ["body"] }
        day = "2026-10-24"
        api.setHold(false)
        _ = await pending.value
        XCTAssertEqual(store.body.day, "2026-10-23")
        XCTAssertEqual(cache.load(.body, userId: "u1", as: BodyResponse.self)?.day, "2026-10-23")
        await store.refresh(.body)
        XCTAssertEqual(api.calls, ["body", "body"])
        XCTAssertEqual(api.days, [LocalDay(date: "2026-10-23", utcOffsetMinutes: -240), LocalDay(date: "2026-10-24", utcOffsetMinutes: -240)])
        XCTAssertEqual(store.body.day, "2026-10-24")
    }

    func testFetchAsksForTheDayAndOffsetItStartedUnder() async {
        store.activate(userId: "u1", api: api)
        api.setHold(true)
        let pending = Task { await store.refresh(.today, force: true) }
        await waitUntil { self.api.calls == ["today"] }
        day = "2026-10-24"
        offset = -300
        api.setHold(false)
        _ = await pending.value
        XCTAssertEqual(api.days(for: "today"), [LocalDay(date: "2026-10-23", utcOffsetMinutes: -240)])
        XCTAssertEqual(store.today.day, "2026-10-23")
    }

    func testRefreshAfterOffsetChangeDoesNotJoinFetchFromThePreviousOffset() async {
        store.activate(userId: "u1", api: api)
        api.setHold(true)
        let before = Task { await store.refresh(.today, force: true) }
        await waitUntil { self.api.calls == ["today"] }
        offset = -300
        let after = Task { await store.refresh(.today, force: true) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        api.setHold(false)
        _ = await before.value
        _ = await after.value
        XCTAssertEqual(api.days(for: "today"), [
            LocalDay(date: "2026-10-23", utcOffsetMinutes: -240), LocalDay(date: "2026-10-23", utcOffsetMinutes: -300),
        ])
    }

    func testFreshResourceRefetchesAfterOffsetChangeOnTheSameDay() async {
        store.activate(userId: "u1", api: api)
        await store.refresh(.body, force: true)
        offset = -300
        await store.refresh(.body)
        XCTAssertEqual(api.days(for: "body"), [
            LocalDay(date: "2026-10-23", utcOffsetMinutes: -240), LocalDay(date: "2026-10-23", utcOffsetMinutes: -300),
        ])
        XCTAssertEqual(store.body.utcOffsetMinutes, -300)
        XCTAssertEqual(cache.load(.body, userId: "u1", as: BodyResponse.self)?.utcOffsetMinutes, -300)
    }

    func testCachedResourceFromAnotherOffsetRevalidatesAfterReload() async {
        store.activate(userId: "u1", api: api)
        await store.refresh(.body, force: true)
        offset = -300
        let reloaded = AppStore(
            cache: cache, now: { [unowned self] in self.clock },
            localDay: { [unowned self] in LocalDay(date: self.day, utcOffsetMinutes: self.offset) },
            notifications: notifications
        )
        reloaded.activate(userId: "u1", api: api)
        XCTAssertNotNil(reloaded.body.value)
        await reloaded.refresh(.body)
        XCTAssertEqual(api.days(for: "body").last, LocalDay(date: "2026-10-23", utcOffsetMinutes: -300))
        XCTAssertEqual(api.calls, ["body", "body"])
    }

    /// A cache written before offsets were stored still shows, but revalidates.
    func testCachedResourceWithoutOffsetShowsAndRevalidates() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fetchedAt = ISO8601DateFormatter().string(from: clock.addingTimeInterval(-10))
        let json = """
        {"userId":"u1","day":"2026-10-23","fetchedAt":"\(fetchedAt)","etag":"old","value":{"days":30,"daily":[]}}
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent("body.json"))
        store.activate(userId: "u1", api: api)
        XCTAssertNotNil(store.body.value)
        await store.refresh(.body)
        XCTAssertEqual(api.calls, ["body"])
    }

    func testNonForcedRefreshJoiningFetchFromThePreviousOffsetFetchesAgain() async {
        store.activate(userId: "u1", api: api)
        api.setHold(true)
        let before = Task { await store.refresh(.body, force: true) }
        await waitUntil { self.api.calls == ["body"] }
        offset = -300
        let after = Task { await store.refresh(.body) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        api.setHold(false)
        _ = await before.value
        let ok = await after.value
        XCTAssertTrue(ok)
        XCTAssertEqual(api.days(for: "body"), [
            LocalDay(date: "2026-10-23", utcOffsetMinutes: -240), LocalDay(date: "2026-10-23", utcOffsetMinutes: -300),
        ])
    }

    func testRefreshAfterMidnightDoesNotJoinFetchFromThePreviousDay() async {
        store.activate(userId: "u1", api: api)
        api.setHold(true)
        let before = Task { await store.refresh(.body, force: true) }
        await waitUntil { self.api.calls == ["body"] }
        day = "2026-10-24"
        let after = Task { await store.refresh(.body) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        api.setHold(false)
        _ = await before.value
        let ok = await after.value
        XCTAssertTrue(ok)
        XCTAssertEqual(api.calls, ["body", "body"])
        XCTAssertEqual(store.body.day, "2026-10-24")
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

    // MARK: - Day and time zone changes

    private func todayCalls() -> Int { api.calls.filter { $0 == "today" }.count }

    func testDayChangeNotificationRefetchesTodayForTheNewDay() async {
        seed(.today, makeToday())
        store.activate(userId: "u1", api: api)
        let before = store.taskID(.body)
        day = "2026-10-24"
        notifications.post(name: .NSCalendarDayChanged, object: nil)
        await waitUntil { self.todayCalls() == 1 }
        XCTAssertEqual(api.days(for: "today"), [LocalDay(date: "2026-10-24", utcOffsetMinutes: -240)])
        XCTAssertEqual(store.currentDay, LocalDay(date: "2026-10-24", utcOffsetMinutes: -240))
        XCTAssertNotEqual(store.taskID(.body), before)
        await waitUntil { self.store.today.day == "2026-10-24" }
    }

    func testTimeZoneChangeNotificationRefetchesTodayForTheNewOffset() async {
        seed(.today, makeToday())
        store.activate(userId: "u1", api: api)
        offset = -420
        notifications.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await waitUntil { self.todayCalls() == 1 }
        XCTAssertEqual(api.days(for: "today"), [LocalDay(date: "2026-10-23", utcOffsetMinutes: -420)])
        XCTAssertEqual(store.currentDay.utcOffsetMinutes, -420)
    }

    func testForegroundDayCheckRefetchesTodayOnce() async {
        seed(.today, makeToday())
        store.activate(userId: "u1", api: api)
        day = "2026-10-24"
        store.noteDayMayHaveChanged()
        store.noteDayMayHaveChanged()
        notifications.post(name: .NSCalendarDayChanged, object: nil)
        await waitUntil { self.todayCalls() == 1 }
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(todayCalls(), 1)
    }

    func testDayCheckWithoutAChangeDoesNotFetch() async {
        seed(.today, makeToday())
        store.activate(userId: "u1", api: api)
        let before = store.taskID(.today)
        store.noteDayMayHaveChanged()
        notifications.post(name: .NSCalendarDayChanged, object: nil)
        notifications.post(name: .NSSystemTimeZoneDidChange, object: nil)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(api.calls, [])
        XCTAssertEqual(store.taskID(.today), before)
    }

    func testDayChangeAfterSignOutDoesNotFetch() async {
        store.activate(userId: "u1", api: api)
        store.reset()
        day = "2026-10-24"
        notifications.post(name: .NSCalendarDayChanged, object: nil)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(api.calls, [])
        XCTAssertEqual(store.currentDay.date, "2026-10-24")
        XCTAssertNil(store.today.value)
    }

    func testDayChangeRefreshInFlightAtSignOutDoesNotWrite() async {
        store.activate(userId: "u1", api: api)
        api.setHold(true)
        day = "2026-10-24"
        store.noteDayMayHaveChanged()
        await waitUntil { self.api.calls == ["today"] }
        store.reset()
        api.setHold(false)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNil(store.today.value)
        XCTAssertNil(cache.load(.today, userId: "u1", as: TodayDTO.self))
    }

    func testStoreStopsObservingDayChangesWhenReleased() async {
        weak var released: AppStore?
        do {
            let other = AppStore(cache: cache, localDay: { LocalDay(date: "2026-10-23", utcOffsetMinutes: 0) }, notifications: notifications)
            released = other
        }
        XCTAssertNil(released)
        notifications.post(name: .NSCalendarDayChanged, object: nil)
    }
}
