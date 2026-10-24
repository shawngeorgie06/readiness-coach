import XCTest
@testable import ReadinessCoach

final class ResourceCacheTests: XCTestCase {
    private var directory: URL!
    private var cache: ResourceDiskCache!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rc-cache-\(UUID().uuidString)")
        cache = ResourceDiskCache(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent().appendingPathComponent("legacy-\(directory.lastPathComponent).json"))
    }

    private func envelope(user: String = "a", value: [String] = ["x"]) -> CachedEnvelope<[String]> {
        CachedEnvelope(userId: user, day: "2026-10-23", fetchedAt: Date(timeIntervalSince1970: 1_700_000_000), etag: "W/\"1\"", value: value)
    }

    func testRoundTripKeepsValueEtagAndDay() {
        cache.save(.sleep(days: 30), envelope(value: ["a", "b"]))
        let loaded = cache.load(.sleep(days: 30), userId: "a", as: [String].self)
        XCTAssertEqual(loaded?.value, ["a", "b"])
        XCTAssertEqual(loaded?.etag, "W/\"1\"")
        XCTAssertEqual(loaded?.day, "2026-10-23")
        XCTAssertEqual(loaded?.fetchedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testCacheFromAnotherUserIsIgnored() {
        cache.save(.body, envelope(user: "a"))
        XCTAssertNil(cache.load(.body, userId: "b", as: [String].self))
        XCTAssertNotNil(cache.load(.body, userId: "a", as: [String].self))
    }

    func testCorruptFileLoadsAsNil() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("train.json"))
        XCTAssertNil(cache.load(.train, userId: "a", as: [String].self))
    }

    func testSavedFileIsExcludedFromBackupAndProtected() throws {
        cache.save(.train, envelope())
        let file = directory.appendingPathComponent("train.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(protection, .complete)
        }
    }

    func testNeedsRevalidationWhenMissingOrOld() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var resource = Resource<Int>()
        XCTAssertTrue(resource.needsRevalidation(now: now, today: "2026-10-23", currentDataVersion: 0))
        resource.value = 1
        resource.day = "2026-10-23"
        resource.fetchedAt = now.addingTimeInterval(-299)
        XCTAssertFalse(resource.needsRevalidation(now: now, today: "2026-10-23", currentDataVersion: 0))
        resource.fetchedAt = now.addingTimeInterval(-301)
        XCTAssertTrue(resource.needsRevalidation(now: now, today: "2026-10-23", currentDataVersion: 0))
    }

    func testDifferentLocalDayNeedsRevalidation() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resource = Resource(value: 1, day: "2026-10-22", fetchedAt: now.addingTimeInterval(-10))
        XCTAssertTrue(resource.needsRevalidation(now: now, today: "2026-10-23", currentDataVersion: 0))
    }

    func testUploadNewerThanFetchNeedsRevalidation() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resource = Resource(value: 1, day: "2026-10-23", fetchedAt: now.addingTimeInterval(-10), dataVersion: 1)
        XCTAssertTrue(resource.needsRevalidation(now: now, today: "2026-10-23", currentDataVersion: 2))
        XCTAssertFalse(resource.needsRevalidation(now: now, today: "2026-10-23", currentDataVersion: 1))
    }

    func testRemoveAllDeletesEverything() {
        cache.save(.today, envelope())
        cache.save(.history(days: 90), envelope(user: "b"))
        cache.removeAll()
        XCTAssertNil(cache.load(.today, userId: "a", as: [String].self))
        XCTAssertNil(cache.load(.history(days: 90), userId: "b", as: [String].self))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testLegacyTodayMigratesOnce() throws {
        let legacy = directory.deletingLastPathComponent().appendingPathComponent("legacy-\(directory.lastPathComponent).json")
        let json = """
        {"date":"2026-10-23","readiness":81,"decision":"push","calibrating":false,
         "pillars":{"sleep":{"score":80,"drivers":[]},"recovery":{"score":80,"drivers":[]},"load":{"score":80,"drivers":[]}},
         "overridesApplied":[],"confidence":"high","missing":[],
         "advisor":{"decision":"push","why":["w"],"prescription":"p","ifIgnored":"i","source":"template"}}
        """
        try Data(json.utf8).write(to: legacy)
        cache.migrateLegacyToday(from: legacy, userId: "a", day: "2026-10-23")
        let loaded = cache.load(.today, userId: "a", as: TodayDTO.self)
        XCTAssertEqual(loaded?.value.readiness, 81)
        XCTAssertEqual(loaded?.day, "2026-10-23")
        XCTAssertNil(cache.load(.today, userId: "b", as: TodayDTO.self))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))

        // A second call with the legacy file gone changes nothing.
        cache.migrateLegacyToday(from: legacy, userId: "b", day: "2026-10-24")
        XCTAssertNil(cache.load(.today, userId: "b", as: TodayDTO.self))
        XCTAssertEqual(cache.load(.today, userId: "a", as: TodayDTO.self)?.value.readiness, 81)
    }
}
