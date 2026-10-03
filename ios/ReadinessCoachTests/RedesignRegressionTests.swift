import XCTest
@testable import ReadinessCoach

final class RedesignRegressionTests: XCTestCase {
    func testUnitTestHostDoesNotStartTheLiveApp() {
        XCTAssertTrue(AppLaunch.isUnitTestHost)
        XCTAssertTrue(AppLaunch.isUnitTestHost(environment: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"], hasXCTest: false))
        XCTAssertTrue(AppLaunch.isUnitTestHost(environment: [:], hasXCTest: true))
        XCTAssertFalse(AppLaunch.isUnitTestHost(environment: [:], hasXCTest: false))
    }

    func testAskContextKeepsTheDisplayedSnapshotDayAndDecision() {
        let pillar = PillarScore(score: 70, drivers: [])
        let yesterday = TodayDTO(
            date: "2026-10-02", readiness: 80, decision: .push, calibrating: false,
            pillars: Pillars(sleep: pillar, recovery: pillar, load: pillar),
            overridesApplied: [], confidence: "high", missing: [], sleepPending: nil,
            advisor: AdvisorNote(decision: .push, why: [], prescription: "", ifIgnored: "", source: "template")
        )
        let context = AskContext(yesterday)
        XCTAssertEqual(context.date, "2026-10-02")
        XCTAssertEqual(context.decision, .push)
    }

    func testHistoryDoesNotShowAnotherRangesPoints() {
        let point = ReadinessPoint(date: "2026-10-03", readiness: 72, decision: .maintain,
                                   sleepScore: 70, recoveryScore: 78, loadScore: 64, calibrating: false)
        let response = ReadinessHistoryResponse(days: 90, data: [point])
        XCTAssertNil(TrendsView.points(in: response, requestedDays: 7))
        XCTAssertEqual(TrendsView.points(in: response, requestedDays: 90)?.count, 1)
        XCTAssertNil(TrendsView.points(in: nil, requestedDays: 7))
    }
}
