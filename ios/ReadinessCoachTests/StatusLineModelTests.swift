import XCTest
@testable import ReadinessCoach

final class StatusLineModelTests: XCTestCase {
    private func today(confidence: String = "high", missing: [String] = [], calibrating: Bool = false) -> TodayDTO {
        let pillar = PillarScore(score: 70, drivers: [])
        return TodayDTO(
            date: "2026-10-02", readiness: 72, decision: .maintain, calibrating: calibrating,
            pillars: Pillars(sleep: pillar, recovery: pillar, load: pillar),
            overridesApplied: [], confidence: confidence, missing: missing, sleepPending: nil,
            advisor: AdvisorNote(decision: .maintain, why: [], prescription: "", ifIgnored: "", source: "template")
        )
    }

    private func items(freshness: DataFreshness = .fresh,
                       today: TodayDTO? = nil,
                       health: HealthKitService.AccessStatus? = .connected,
                       syncFailed: Bool = false,
                       syncSucceeded: Bool = false,
                       uploadFailed: Bool = false) -> [StatusItem] {
        StatusLineModel.items(.init(
            freshness: freshness, today: today, healthStatus: health,
            healthSyncFailed: syncFailed, healthSyncSucceeded: syncSucceeded, uploadFailed: uploadFailed
        ))
    }

    func testNothingToSayWhenFreshAndConnected() {
        XCTAssertEqual(items(today: today()), [])
    }

    func testHealthAccessOutranksEverything() {
        let result = items(freshness: .offline, today: today(confidence: "low", calibrating: true),
                           health: .needsPermission, uploadFailed: true)
        XCTAssertEqual(result.first, .healthAccess(needsPermission: true))
        XCTAssertEqual(result.count, 5)
    }

    func testOrderingIsStable() {
        let result = items(freshness: .stale(scoreDay: "2026-10-01"),
                           today: today(confidence: "low", missing: ["hrv"], calibrating: true))
        XCTAssertEqual(result, [
            .stale(scoreDay: "2026-10-01"),
            .lowConfidence(missing: ["hrv"]),
            .calibrating,
            .healthCheck,
        ])
    }

    func testAgingIsLast() {
        let result = items(freshness: .aging(relative: "3 hours ago"), today: today(calibrating: true))
        XCTAssertEqual(result, [.calibrating, .aging(relative: "3 hours ago")])
    }

    func testHealthBannerIsHiddenWhileStatusIsLoading() {
        XCTAssertEqual(items(today: today(), health: nil), [])
    }

    func testUnavailableHealthOnlyPromptsAfterAFailedSyncWithNoSuccess() {
        XCTAssertFalse(StatusLineModel.needsHealthAccess(status: .unavailable, syncFailed: false, syncSucceeded: false))
        XCTAssertFalse(StatusLineModel.needsHealthAccess(status: .unavailable, syncFailed: true, syncSucceeded: true))
        XCTAssertTrue(StatusLineModel.needsHealthAccess(status: .unavailable, syncFailed: true, syncSucceeded: false))
        XCTAssertFalse(StatusLineModel.needsHealthAccess(status: .connected, syncFailed: true, syncSucceeded: false))
    }

    func testEmptySuccessfulSyncDoesNotReplaceThePermissionRequestState() {
        let result = items(today: today(confidence: "low", missing: ["sleep"]),
                           health: .needsPermission, syncSucceeded: true)
        XCTAssertEqual(result.first, .healthAccess(needsPermission: true))
        XCTAssertFalse(result.contains(.healthCheck))
    }

    func testMissingSignalsOfferHealthSettingsWithoutClaimingPermissionDenial() {
        let result = items(today: today(confidence: "low", missing: ["sleep"]),
                           health: .connected, syncSucceeded: true)
        XCTAssertTrue(result.contains(.healthCheck))
        XCTAssertFalse(result.contains(.healthAccess(needsPermission: false)))
        XCTAssertEqual(StatusItem.healthCheck.actionTitle, "Open Health settings")
        XCTAssertEqual(items(today: today(), health: .connected, syncFailed: true), [])
    }

    func testFriendlyMissingNamesKnownKeysAndKeepsUnknownOnes() {
        XCTAssertEqual(StatusLineModel.friendlyMissing([]), "")
        XCTAssertEqual(StatusLineModel.friendlyMissing(["hrv", "resting_heart_rate", "sleep", "steps"]),
                       " (heart-rate variability, resting pulse, sleep, steps)")
    }

    func testLowConfidenceMessageEmbedsMissingMetrics() {
        let message = StatusItem.lowConfidence(missing: ["sleep"]).message
        XCTAssertTrue(message.contains("(sleep)"), message)
    }

    func testCollapsedSummaryKeepsConfidenceAndCalibrationVisible() {
        XCTAssertEqual(StatusLineModel.summary([
            .healthAccess(needsPermission: true), .offline, .uploadPending,
            .lowConfidence(missing: ["sleep"]), .calibrating,
        ]), "Health access needed · Low confidence · Calibrating +2")
        XCTAssertEqual(StatusLineModel.summary([.lowConfidence(missing: []), .calibrating]),
                       "Low confidence · Calibrating")
        XCTAssertEqual(StatusLineModel.summary([.offline, .uploadPending]), "Offline +1")
        XCTAssertEqual(StatusLineModel.summary([]), "")
    }

    func testOnlyHealthStatesHaveAnAction() {
        XCTAssertEqual(StatusItem.healthAccess(needsPermission: true).actionTitle, "Allow Health access")
        XCTAssertEqual(StatusItem.healthAccess(needsPermission: false).actionTitle, "Open Health settings")
        for item in [StatusItem.offline, .uploadPending, .stale(scoreDay: "x"), .lowConfidence(missing: []), .calibrating, .aging(relative: "x")] {
            XCTAssertNil(item.actionTitle, "\(item)")
        }
    }
}
