import XCTest
@testable import ReadinessCoach

final class ChartDateTests: XCTestCase {
    func testDayKeepsTheServerCalendarDateInDeviceTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: ChartDate.day("2026-10-03"))
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 10)
        XCTAssertEqual(components.day, 3)
    }

    func testParsingFollowsTheCurrentTimeZoneAfterAChange() {
        for offset in [12 * 3600, -10 * 3600] {
            let zone = TimeZone(secondsFromGMT: offset)!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let components = calendar.dateComponents([.year, .month, .day], from: ChartDate.day("2026-10-03", timeZone: zone))
            XCTAssertEqual(components.year, 2026)
            XCTAssertEqual(components.month, 10)
            XCTAssertEqual(components.day, 3)
        }
    }

    func testServerDayFormattingUsesGregorianParsingWithABuddhistDisplayCalendar() {
        let formatted = StatusLineModel.formattedDay("2026-10-03", locale: Locale(identifier: "en_US@calendar=buddhist"))
        XCTAssertTrue(formatted.contains("2569"), formatted)
        XCTAssertTrue(formatted.contains("Oct 3"), formatted)
    }

    func testSelectedServerDayRebasesAcrossTimeZones() {
        let east = TimeZone(secondsFromGMT: 12 * 3600)!
        let west = TimeZone(secondsFromGMT: -10 * 3600)!
        let selected = ChartDate.day("2026-10-03", timeZone: east)
        XCTAssertEqual(ChartDate.rebase(selected, from: east, to: west), ChartDate.day("2026-10-03", timeZone: west))
        XCTAssertNil(ChartDate.rebase(nil, from: east, to: west))
    }

    func testParentSelectionSurvivesChartRemovalAndRecreationAfterTravel() {
        let east = TimeZone(secondsFromGMT: 12 * 3600)!
        let west = TimeZone(secondsFromGMT: -10 * 3600)!
        let selected = ChartDate.day("2026-10-03", timeZone: east)
        let parentSelection = ChartDaySelection(date: selected, timeZone: east)

        // An empty response removes the overlay, but the parent keeps its selection.
        let emptyDates: [Date] = []
        XCTAssertNil(nearestDate(parentSelection.resolved(timeZone: east), in: emptyDates))

        // No overlay observes travel. Recreated chart data must still match the readout.
        let restoredDates = ["2026-10-02", "2026-10-03"].map { ChartDate.day($0, timeZone: west) }
        let restoredSelection = parentSelection.resolved(timeZone: west)
        XCTAssertEqual(restoredSelection, restoredDates.last)
        XCTAssertTrue(restoredDates.contains { $0 == restoredSelection })
        XCTAssertEqual(parentSelection.resolved(timeZone: east), selected)
    }

    func testParentSelectionSupportsBindingUpdatesAndClearing() {
        var selection = ChartDaySelection()
        XCTAssertNil(selection.date)
        selection.date = ChartDate.day("2026-10-03")
        XCTAssertEqual(selection.date, ChartDate.day("2026-10-03"))
        selection.date = nil
        XCTAssertNil(selection.resolved(timeZone: TimeZone(secondsFromGMT: -10 * 3600)!))
    }

    func testFreshnessUsesTheSameGregorianDayAsAPIRequests() {
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        XCTAssertEqual(SyncFreshness.localCalendarDay(now: now), APIClient.deviceLocalDate(now: now))
    }

    func testISOSuffixKeepsTheSameCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let day = calendar.component(.day, from: ChartDate.day("2026-10-03T00:00:00Z"))
        XCTAssertEqual(day, 3)
    }

    // MARK: - Derived chart series after travel

    private let east = TimeZone(secondsFromGMT: 12 * 3600)!
    private let west = TimeZone(secondsFromGMT: -10 * 3600)!
    private let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func bodyRow(_ date: String, _ avg: Double) -> BodyDaily {
        BodyDaily(type: "hrv_sdnn", date: date, min: avg, avg: avg, max: avg, latest: avg, count: 1)
    }

    func testBodySeriesRebuildsAfterTravelAndMatchesTheRebasedSelection() {
        let derived = Derived<SeriesStamp, BodySeries>()
        let daily = [bodyRow("2026-10-02", 40), bodyRow("2026-10-03", 55)]
        let before = derived.series(fetchedAt: fetchedAt, timeZone: east) { BodySeries(daily, timeZone: $0) }
        let selection = ChartDaySelection(date: before.hrv.dates.last, timeZone: east)
        XCTAssertEqual(before.hrv.row(on: selection.resolved(timeZone: east))?.avg, 55)

        let after = derived.series(fetchedAt: fetchedAt, timeZone: west) { BodySeries(daily, timeZone: $0) }
        let rebased = selection.resolved(timeZone: west)
        XCTAssertEqual(after.hrv.dates, daily.map { ChartDate.day($0.date, timeZone: west) })
        XCTAssertEqual(after.hrv.row(on: rebased)?.date, "2026-10-03")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = west
        XCTAssertEqual(calendar.component(.day, from: rebased!), 3)
    }

    func testSeriesIsReusedWhileZoneAndFetchAreUnchanged() {
        let derived = Derived<SeriesStamp, Int>()
        var builds = 0
        for _ in 0..<3 { _ = derived.series(days: 30, fetchedAt: fetchedAt, timeZone: east) { _ in builds += 1; return builds } }
        XCTAssertEqual(builds, 1)
        _ = derived.series(days: 30, fetchedAt: fetchedAt, timeZone: west) { _ in builds += 1; return builds }
        _ = derived.series(days: 7, fetchedAt: fetchedAt, timeZone: west) { _ in builds += 1; return builds }
        _ = derived.series(days: 7, fetchedAt: fetchedAt.addingTimeInterval(1), timeZone: west) { _ in builds += 1; return builds }
        XCTAssertEqual(builds, 4)
    }

    func testSleepAndTrendSeriesUseTheZoneTheyAreBuiltIn() {
        let night = SleepDetailResponse(days: 7, data: [])
        let sleep = Derived<SeriesStamp, SleepSeries>()
        _ = sleep.series(days: 7, fetchedAt: fetchedAt, timeZone: east) { SleepSeries(night, timeZone: $0) }
        var zones: [TimeZone] = []
        _ = sleep.series(days: 7, fetchedAt: fetchedAt, timeZone: west) { zones.append($0); return SleepSeries(night, timeZone: $0) }
        XCTAssertEqual(zones, [west])

        let trend = Derived<SeriesStamp, TrendSeries?>()
        _ = trend.series(days: 30, fetchedAt: fetchedAt, timeZone: east) { _ in nil }
        let rebuilt = trend.series(days: 30, fetchedAt: fetchedAt, timeZone: west) { TrendSeries([], timeZone: $0) }
        XCTAssertNotNil(rebuilt)
    }
}
