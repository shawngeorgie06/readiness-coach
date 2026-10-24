import XCTest
@testable import ReadinessCoach

final class HistoryDaySummaryTests: XCTestCase {
    private func point(_ date: String, _ readiness: Double, _ decision: Decision,
                       sleep: Double = 70, recovery: Double = 78, load: Double = 64,
                       calibrating: Bool = false) -> ReadinessPoint {
        ReadinessPoint(date: date, readiness: readiness, decision: decision,
                       sleepScore: sleep, recoveryScore: recovery, loadScore: load, calibrating: calibrating)
    }

    // MARK: Day summary

    func testDaySummaryCopiesTheSavedPointVerbatim() {
        let summary = DaySummary(point("2026-10-03", 72.4, .maintain, sleep: 61, recovery: 83, load: 55, calibrating: true))
        XCTAssertEqual(summary.date, "2026-10-03")
        XCTAssertEqual(summary.readiness, 72.4)
        XCTAssertEqual(summary.decision, .maintain)
        XCTAssertEqual(summary.score(.recovery), 83)
        XCTAssertEqual(summary.score(.sleep), 61)
        XCTAssertEqual(summary.score(.load), 55)
        XCTAssertTrue(summary.calibrating)
        XCTAssertEqual(summary.id, "2026-10-03")
    }

    /// An override can lower the call below the score's band; the summary
    /// must show the saved call, not a greener one recomputed from the score.
    func testVerdictFollowsTheSavedDecisionNotTheScore() {
        let summary = DaySummary(point("2026-10-03", 80, .maintain))
        XCTAssertEqual(summary.verdictBand, .mid)
        XCTAssertEqual(DaySummary(point("2026-10-03", 80, .recover)).verdictBand, .low)
    }

    func testDaySummarySpeaksScoreDecisionAndRealWeights() {
        let summary = DaySummary(point("2026-10-03", 72, .maintain, calibrating: true))
        XCTAssertTrue(summary.accessibilityLabel.contains("Readiness 72 of 100. Decision: Maintain."))
        XCTAssertTrue(summary.accessibilityLabel.contains("Calibrating"))
        XCTAssertEqual(summary.pillarAccessibilityLabel(.recovery), "Recovery 78 of 100, 40 percent of readiness")
        XCTAssertEqual(summary.pillarAccessibilityLabel(.sleep), "Sleep 70 of 100, 35 percent of readiness")
        XCTAssertEqual(summary.pillarAccessibilityLabel(.load), "Load 64 of 100, 25 percent of readiness")
    }

    /// The summary is read-only by construction: it can't reach the network,
    /// the store or the coach.
    func testDaySummaryViewHasNoNetworkStoreOrCoachAccess() throws {
        let source = try String(contentsOf: viewsDirectory.appendingPathComponent("DaySummaryView.swift"), encoding: .utf8)
        for forbidden in ["makeClient", "APIClient", "AppStore", "SyncService", "AppSettings",
                          "EnvironmentObject", "@Environment(", ".ask(", "today(", "refresh(", "URLSession"] {
            XCTAssertFalse(source.contains(forbidden), "DaySummaryView.swift references \(forbidden)")
        }
    }

    /// History reads the store's cached range and refreshes through it; it
    /// never builds its own client or asks the coach.
    func testHistoryReadsOnlyThroughTheStore() throws {
        let source = try String(contentsOf: viewsDirectory.appendingPathComponent("TrendsView.swift"), encoding: .utf8)
        for forbidden in ["makeClient", "APIClient", "URLSession", ".ask(", "AdvisorNote"] {
            XCTAssertFalse(source.contains(forbidden), "TrendsView.swift references \(forbidden)")
        }
        XCTAssertTrue(source.contains("store.history[days]"))
    }

    // MARK: History model

    func testSelectionFallsBackToTheLatestDay() {
        let points = [point("2026-10-01", 60, .maintain), point("2026-10-02", 80, .push)]
        XCTAssertEqual(HistoryModel.selected(nil, in: points)?.date, "2026-10-02")
        XCTAssertEqual(HistoryModel.selected("2026-10-01", in: points)?.date, "2026-10-01")
        // A day from another range is not shown in this one.
        XCTAssertEqual(HistoryModel.selected("2026-07-01", in: points)?.date, "2026-10-02")
        XCTAssertNil(HistoryModel.selected(nil, in: []))
    }

    func testPriorDayAndSteppingStayInsideTheRange() {
        let points = [point("2026-10-01", 60, .maintain), point("2026-10-02", 80, .push), point("2026-10-03", 45, .recover)]
        XCTAssertNil(HistoryModel.prior(of: points[0], in: points))
        XCTAssertEqual(HistoryModel.prior(of: points[2], in: points)?.date, "2026-10-02")
        XCTAssertEqual(HistoryModel.step(from: "2026-10-02", by: 1, in: points), "2026-10-03")
        XCTAssertEqual(HistoryModel.step(from: "2026-10-03", by: 1, in: points), "2026-10-03")
        XCTAssertEqual(HistoryModel.step(from: "2026-10-01", by: -1, in: points), "2026-10-01")
        XCTAssertEqual(HistoryModel.step(from: "missing", by: -1, in: points), "2026-10-03")
    }

    func testPillarChangesRankByBiggestMove() {
        let before = point("2026-10-01", 60, .maintain, sleep: 70, recovery: 70, load: 70)
        let after = point("2026-10-02", 64, .maintain, sleep: 62, recovery: 82, load: 71)
        let changes = HistoryModel.pillarChanges(after, prior: before)
        XCTAssertEqual(changes.map(\.pillar), [.recovery, .sleep, .load])
        XCTAssertEqual(changes.map(\.delta), [12, -8, 1])
        XCTAssertEqual(changes.first?.score, 82)
        XCTAssertEqual(HistoryModel.driverLine(changes[0]), "Biggest lift: Recovery (+12).")
        XCTAssertEqual(HistoryModel.driverLine(changes[1]), "Biggest drag: Sleep (-8).")
        XCTAssertNil(HistoryModel.driverLine(.init(pillar: .load, delta: 0.2, score: 70)))
    }

    func testDeltaExplanationAndReadoutLabels() {
        XCTAssertEqual(HistoryModel.deltaExplanation(6), "+6 pts vs the previous day — overall readiness improved.")
        XCTAssertEqual(HistoryModel.deltaExplanation(-3.6), "-4 pts vs the previous day — overall readiness softened.")
        XCTAssertEqual(HistoryModel.deltaExplanation(0.3), "0 pts vs the previous day — readiness held steady.")
        XCTAssertEqual(HistoryModel.pillarReadoutLabel(.sleep, score: 70, delta: -4),
                       "Sleep 70 of 100, down 4 from the previous day")
        XCTAssertEqual(HistoryModel.pillarReadoutLabel(.load, score: 64, delta: nil), "Load 64 of 100")
        XCTAssertEqual(HistoryModel.weakest(point("2026-10-01", 60, .maintain, sleep: 50, recovery: 70, load: 64)).pillar, .sleep)
    }

    /// Each range option is spoken by its own day count, not one shared name.
    func testRangeOptionsHaveDistinctSpokenLabels() throws {
        XCTAssertEqual([7, 30, 90].map(HistoryModel.rangeLabel), ["7 days", "30 days", "90 days"])
        let source = try String(contentsOf: viewsDirectory.appendingPathComponent("TrendsView.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains(".accessibilityLabel(\"History range\")"))
    }

    func testChartPositionPicksTheDayItFallsIn() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let zone = calendar.timeZone
        let dates = ["2026-10-01", "2026-10-02", "2026-10-03"].map { ChartDate.day($0, timeZone: zone) }
        // 9pm on Oct 2 is nearer midnight Oct 3 but still belongs to Oct 2's bar.
        let lateOnTheSecond = dates[1].addingTimeInterval(21 * 3600)
        XCTAssertEqual(HistoryModel.dayIndex(for: lateOnTheSecond, in: dates, calendar: calendar), 1)
        // Past the last bar falls back to the nearest day.
        XCTAssertEqual(HistoryModel.dayIndex(for: dates[2].addingTimeInterval(3 * 86_400), in: dates, calendar: calendar), 2)
        XCTAssertNil(HistoryModel.dayIndex(for: dates[0], in: [], calendar: calendar))
    }

    private var viewsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ReadinessCoach/Views")
    }
}
