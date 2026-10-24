import XCTest
@testable import ReadinessCoach

final class DesignSystemTests: XCTestCase {
    // MARK: Score bands

    func testScoreBandsUseTheBackendCutoffsOnTheShownNumber() {
        XCTAssertEqual(ScoreBand(score: 100), .high)
        XCTAssertEqual(ScoreBand(score: 75), .high)
        XCTAssertEqual(ScoreBand(score: 74.6), .high, "a numeral that reads 75 is not coloured as below 75")
        XCTAssertEqual(ScoreBand(score: 74.4), .mid)
        XCTAssertEqual(ScoreBand(score: 50), .mid)
        XCTAssertEqual(ScoreBand(score: 49.4), .low)
        XCTAssertEqual(ScoreBand(score: 0), .low)
    }

    func testHealthyGaugeNumeralsAreWhiteNotGreen() {
        XCTAssertEqual(ScoreBand.high.numeralColor, Palette.textPrimary)
        XCTAssertNotEqual(ScoreBand.high.numeralColor, Palette.success)
        XCTAssertEqual(ScoreBand.mid.numeralColor, Palette.warn)
        XCTAssertEqual(ScoreBand.low.numeralColor, Palette.danger)
    }

    func testGaugeArcCoversThreeQuartersAndClamps() {
        XCTAssertEqual(GaugeArc.trim(for: 0), 0)
        XCTAssertEqual(GaugeArc.trim(for: 50), 0.375, accuracy: 1e-9)
        XCTAssertEqual(GaugeArc.trim(for: 100), 0.75, accuracy: 1e-9)
        XCTAssertEqual(GaugeArc.trim(for: -5), 0)
        XCTAssertEqual(GaugeArc.trim(for: 130), 0.75, accuracy: 1e-9)
    }

    // MARK: Today head

    func testTodayVerdictFollowsTheLockedDecisionNotTheScore() {
        // An override (short sleep) made a high score's call conservative.
        let overridden = today(readiness: 88, decision: .recover)
        XCTAssertEqual(TodayHeadModel.verdictBand(overridden), .low)
        XCTAssertEqual(TodayHeadModel.verdictBand(today(readiness: 62, decision: .maintain)), .mid)
        XCTAssertEqual(TodayHeadModel.verdictBand(today(readiness: 80, decision: .push)), .high)
    }

    func testTodayHeadSpeaksTheVerbatimScoreAndDecision() {
        let label = TodayHeadModel.accessibilityLabel(today(readiness: 88, decision: .recover))
        XCTAssertTrue(label.hasPrefix("Readiness 88 of 100. Decision: Recover."), label)
    }

    func testPillarGaugeSpeaksTheRealWeightAndDriver() {
        let score = PillarScore(score: 71.6, drivers: [Driver(text: "HRV above baseline", detail: nil)])
        XCTAssertEqual(
            Pillar.recovery.gaugeAccessibilityLabel(score),
            "Recovery 72 of 100, 40 percent of readiness. HRV above baseline"
        )
        XCTAssertEqual(
            Pillar.load.gaugeAccessibilityLabel(PillarScore(score: 40, drivers: [])),
            "Load 40 of 100, 25 percent of readiness"
        )
    }

    // MARK: Comparisons

    func testHigherIsGoodMetricAboveItsBandIsGoodWithAnUpArrow() {
        let c = MetricComparison(metric: .hrv, baseline: baseline(today: 62, normal: 56, band: (53.2, 58.8), good: "up", position: .above))
        XCTAssertEqual(c.position, .above)
        XCTAssertEqual(c.tone, .good)
        XCTAssertEqual(c.arrowSymbol, "arrowtriangle.up.fill")
        XCTAssertEqual(c.deltaText, "+6 ms")
        XCTAssertEqual(c.compactText, "+6 ms")
    }

    func testLowerIsGoodMetricAboveItsBandIsBad() {
        let up = MetricComparison(metric: .restingHr, baseline: baseline(today: 58, normal: 52, band: (50.44, 53.56), good: "down", position: .above))
        XCTAssertEqual(up.position, .above)
        XCTAssertEqual(up.tone, .bad)
        XCTAssertEqual(up.arrowSymbol, "arrowtriangle.up.fill")

        let down = MetricComparison(metric: .restingHr, baseline: baseline(today: 48, normal: 52, band: (50.44, 53.56), good: "down", position: .below))
        XCTAssertEqual(down.position, .below)
        XCTAssertEqual(down.tone, .good)
        XCTAssertEqual(down.arrowSymbol, "arrowtriangle.down.fill")
        XCTAssertEqual(down.deltaText, "\u{2212}4 bpm")
    }

    func testInsideTheBandIsNeutralWithNoArrow() {
        let c = MetricComparison(metric: .hrv, baseline: baseline(today: 57, normal: 56, band: (53.2, 58.8), good: "up", position: .within))
        XCTAssertEqual(c.position, .within)
        XCTAssertEqual(c.tone, .neutral)
        XCTAssertNil(c.arrowSymbol)
        XCTAssertEqual(c.summary, "Normal")
    }

    func testLoadOutsideItsBandIsNotableNotGoodOrBad() {
        let c = MetricComparison(metric: .load7d, baseline: baseline(today: 14, normal: 9, band: (6.3, 11.7), good: "none", position: .above))
        XCTAssertEqual(c.position, .above)
        XCTAssertEqual(c.tone, .notable)
        XCTAssertEqual(c.deltaText, "+5.0")
    }

    func testNoDataTodayShowsADashAndNoArrow() {
        let c = MetricComparison(metric: .hrv, baseline: baseline(today: nil, normal: 56, band: (53.2, 58.8), good: "up", position: nil))
        XCTAssertNil(c.position)
        XCTAssertNil(c.arrowSymbol)
        XCTAssertEqual(c.todayText, "—")
        XCTAssertEqual(c.summary, "No data today")
        XCTAssertNil(c.deltaText)
        XCTAssertEqual(c.accessibilityText, "Heart rate variability: no data today.")
    }

    func testAStatusWithoutTodaysValueIsIgnored() {
        let c = MetricComparison(metric: .hrv, baseline: baseline(today: nil, normal: 56, band: (53.2, 58.8), good: "up", position: .above))
        XCTAssertNil(c.position)
        XCTAssertNil(c.arrowSymbol)
        XCTAssertEqual(c.tone, .neutral)
        XCTAssertEqual(c.summary, "No data today")
    }

    func testNoNormalYetShowsNotEnoughDataAndNoArrowEvenWithABand() {
        // The sleep band follows the target, so it exists before any history.
        // The server sends no status until there's a 30-day average.
        let c = MetricComparison(metric: .sleepHours, baseline: baseline(today: 6, normal: nil, band: (6.75, 8.25), good: "up", position: nil))
        XCTAssertNil(c.position)
        XCTAssertNil(c.arrowSymbol)
        XCTAssertEqual(c.tone, .neutral)
        XCTAssertEqual(c.summary, "Not enough data yet")
        XCTAssertEqual(c.compactText, "Not enough data yet")
    }

    func testSleepBeatingTheAverageButShortOfTargetSaysBelowTarget() {
        let c = MetricComparison(metric: .sleepHours, baseline: baseline(today: 6, normal: 5, band: (7.2, 8.8), good: "up", position: .below))
        XCTAssertEqual(c.position, .below)
        XCTAssertEqual(c.tone, .bad)
        XCTAssertEqual(c.arrowSymbol, "arrowtriangle.down.fill")
        XCTAssertEqual(c.deltaText, "+1h")
        XCTAssertEqual(c.compactText, "Below target", "a down arrow is never paired with a plus sign")
    }

    func testOlderServersWithoutBaselinesProduceNoComparisons() {
        XCTAssertNil(MetricComparison.all(from: nil))
        let all = MetricComparison.all(from: TodayBaselinesDTO(
            hrv: baseline(today: 1, normal: 1, band: nil, good: "up", position: nil),
            restingHr: baseline(today: 1, normal: 1, band: nil, good: "down", position: nil),
            sleepHours: baseline(today: 1, normal: 1, band: nil, good: "up", position: nil),
            load7d: baseline(today: 1, normal: 1, band: nil, good: "none", position: nil)
        ))
        XCTAssertEqual(all?.map(\.metric), [.hrv, .restingHr, .sleepHours, .load7d])
    }

    func testDeltaFormatting() {
        XCTAssertEqual(VitalMetric.sleepHours.formatDelta(-65.0 / 60), "\u{2212}1h 5m")
        XCTAssertEqual(VitalMetric.sleepHours.formatDelta(0.7), "+42m")
        XCTAssertEqual(VitalMetric.hrv.formatDelta(-0.4), "0 ms")
        XCTAssertEqual(VitalMetric.load7d.formatDelta(0.04), "0.0")
        XCTAssertEqual(VitalMetric.load7d.formatDelta(-1.26), "\u{2212}1.3")
    }

    // MARK: Server status

    func testTheServerStatusDecidesWhenRoundedNumbersCannot() {
        // Raw HRV 58.8314 and 58.8316 against a 56.03 normal both serialize as
        // 58.83 with a 53.23–58.83 band, yet the recovery driver calls the
        // first normal and the second above. Same numbers in, the status wins.
        let normal = MetricComparison(metric: .hrv, baseline: baseline(today: 58.83, normal: 56.03, band: (53.23, 58.83), good: "up", position: .within))
        XCTAssertEqual(normal.position, .within)
        XCTAssertEqual(normal.tone, .neutral)
        XCTAssertNil(normal.arrowSymbol)
        XCTAssertEqual(normal.summary, "Normal")

        let above = MetricComparison(metric: .hrv, baseline: baseline(today: 58.83, normal: 56.03, band: (53.23, 58.83), good: "up", position: .above))
        XCTAssertEqual(above.position, .above)
        XCTAssertEqual(above.tone, .good)
        XCTAssertEqual(above.arrowSymbol, "arrowtriangle.up.fill")
        XCTAssertEqual(above.summary, "Above normal")
    }

    func testTheServerStatusIsTakenEvenAgainstTheShownBand() {
        let hrv = MetricComparison(metric: .hrv, baseline: baseline(today: 62, normal: 56, band: (53.2, 58.8), good: "up", position: .within))
        XCTAssertEqual(hrv.position, .within)
        XCTAssertNil(hrv.arrowSymbol)

        let rhr = MetricComparison(metric: .restingHr, baseline: baseline(today: 52, normal: 52, band: (50.44, 53.56), good: "down", position: .above))
        XCTAssertEqual(rhr.position, .above)
        XCTAssertEqual(rhr.tone, .bad)
        XCTAssertEqual(rhr.summary, "Above normal")
    }

    func testLoadFollowsTheStatusWithoutCallingItGoodOrBad() {
        for (position, tone) in [(MetricPosition.above, MetricComparison.Tone.notable), (.below, .notable), (.within, .neutral)] {
            let c = MetricComparison(metric: .load7d, baseline: baseline(today: 9, normal: 9, band: (6.3, 11.7), good: "none", position: position))
            XCTAssertEqual(c.position, position)
            XCTAssertEqual(c.tone, tone, "\(position)")
        }
    }

    func testAResponseWithoutAStatusShowsTheNumbersAndMakesNoCall() {
        // An older server: values, normal and band, but no `position`.
        let c = MetricComparison(metric: .hrv, baseline: baseline(today: 62, normal: 56, band: (53.2, 58.8), good: "up", position: nil))
        XCTAssertNil(c.position)
        XCTAssertNil(c.arrowSymbol)
        XCTAssertEqual(c.tone, .neutral)
        XCTAssertEqual(c.summary, "Compared with average")
        XCTAssertEqual(c.compactText, "+6 ms", "the change shows without an arrow")
        XCTAssertEqual(c.changeText, "+6 ms vs normal")
        XCTAssertEqual(
            c.accessibilityText,
            "Heart rate variability 62 milliseconds. Compared with average. Up 6 milliseconds versus 30-day normal of 56 milliseconds."
        )

        let sleep = MetricComparison(metric: .sleepHours, baseline: baseline(today: 6, normal: 5, band: (7.2, 8.8), good: "up", position: nil))
        XCTAssertNil(sleep.arrowSymbol)
        XCTAssertEqual(sleep.tone, .neutral)
        XCTAssertEqual(sleep.compactText, "+1h")
        XCTAssertFalse(sleep.summary.contains("target"), "no target claim without the server's call")
    }

    // MARK: Baseline decoding

    func testBaselineWithoutPositionDecodesAsNoStatus() throws {
        let old = try decodeBaseline(#"{"today":62,"baseline30d":56,"neutralBand":{"low":53.2,"high":58.8},"recent14d":[null,62],"goodDirection":"up"}"#)
        XCTAssertNil(old.position)
        XCTAssertEqual(old.today, 62)
        XCTAssertEqual(old.neutralBand, NeutralBandDTO(low: 53.2, high: 58.8))
        XCTAssertEqual(old.recent14d, [nil, 62])
    }

    func testBaselinePositionDecodes() throws {
        let new = try decodeBaseline(#"{"today":58.83,"baseline30d":56.03,"neutralBand":{"low":53.23,"high":58.83},"recent14d":[],"goodDirection":"up","position":"above"}"#)
        XCTAssertEqual(new.position, .above)
        XCTAssertNil(try decodeBaseline(#"{"today":null,"baseline30d":null,"neutralBand":null,"recent14d":[],"goodDirection":"up","position":null}"#).position)
        XCTAssertNil(
            try decodeBaseline(#"{"today":1,"baseline30d":1,"neutralBand":null,"recent14d":[],"goodDirection":"up","position":"sideways"}"#).position,
            "a status this build doesn't know is no status, not a failed Today"
        )
    }

    func testBaselinePositionRoundTrips() throws {
        let value = baseline(today: 5.2, normal: 4, band: (2.8, 5.2), good: "none", position: .above)
        let decoded = try JSONDecoder().decode(MetricBaselineDTO.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded, value)
    }

    // MARK: Full comparison row

    func testFullRowSeparatesSleepTargetStatusFromChangeVersusAverage() {
        // Beat the 30-day average by an hour, still short of the 8h target.
        let c = MetricComparison(metric: .sleepHours, baseline: baseline(today: 6, normal: 5, band: (7.2, 8.8), good: "up", position: .below))
        XCTAssertEqual(c.summary, "Below target", "the arrowed status line names the target")
        XCTAssertEqual(c.changeText, "+1h vs avg", "the change is labelled as against the average")
        XCTAssertEqual(c.normalCaption, "avg 5h", "the reference column doesn't call the average the band")
        XCTAssertEqual(
            c.accessibilityText,
            "Sleep 6 hours. Below target. Up 1 hour versus 30-day average of 5 hours."
        )
    }

    func testFullRowStatesStatusAndChangeForBaselineMetrics() {
        let c = MetricComparison(metric: .hrv, baseline: baseline(today: 62, normal: 56, band: (53.2, 58.8), good: "up", position: .above))
        XCTAssertEqual(c.summary, "Above normal")
        XCTAssertEqual(c.changeText, "+6 ms vs normal")
        XCTAssertEqual(c.normalCaption, "normal 56")
        XCTAssertEqual(
            c.accessibilityText,
            "Heart rate variability 62 milliseconds. Above normal. Up 6 milliseconds versus 30-day normal of 56 milliseconds."
        )
    }

    func testFullRowWithoutANormalHasNoChangeLine() {
        let c = MetricComparison(metric: .sleepHours, baseline: baseline(today: 6, normal: nil, band: (6.75, 8.25), good: "up", position: nil))
        XCTAssertNil(c.changeText)
        XCTAssertNil(c.normalCaption)
        XCTAssertEqual(c.accessibilityText, "Sleep 6 hours. Not enough data yet.")
    }

    func testUnchangedValueSaysNoChange() {
        let c = MetricComparison(metric: .restingHr, baseline: baseline(today: 52, normal: 52, band: (50.44, 53.56), good: "down", position: .within))
        XCTAssertEqual(c.changeText, "0 bpm vs normal")
        XCTAssertEqual(
            c.accessibilityText,
            "Resting heart rate 52 beats per minute. Normal. No change versus 30-day normal of 52 beats per minute."
        )
    }

    // MARK: Notice copy

    func testNotFoundServerErrorBecomesAPlainNextStepWithTheRawTextKept() {
        let raw = APIError.http(status: 404, code: "user_not_found").localizedDescription
        let copy = NoticeCopy(message: raw)
        XCTAssertEqual(copy.text, "No readiness data was found for this account. Sync Health data or check your connection in Settings.")
        XCTAssertEqual(copy.detail, raw)
    }

    func testServerFailuresBecomeTryAgainWithTheRawTextKept() {
        for raw in [
            APIError.http(status: 500, code: "internal").localizedDescription,
            APIError.http(status: 503, code: nil).localizedDescription,
        ] {
            let copy = NoticeCopy(message: raw)
            XCTAssertEqual(copy.text, "The server couldn't load this data. Try again shortly.", raw)
            XCTAssertEqual(copy.detail, raw)
        }
    }

    func testOtherClientErrorsHideTheCodeWithoutBlamingTheNetwork() {
        let raw = APIError.http(status: 400, code: "bad_request").localizedDescription
        let copy = NoticeCopy(message: raw)
        XCTAssertFalse(copy.text.contains("400"))
        XCTAssertFalse(copy.text.localizedCaseInsensitiveContains("connection"))
        XCTAssertEqual(copy.detail, raw)
    }

    func testPlainMessagesPassThroughUnchanged() {
        for message in [
            "Sync Health data to compute today's readiness.",
            APIError.decoding(URLError(.cannotDecodeContentData)).localizedDescription,
            APIError.rateLimited(retryAfter: 120).localizedDescription,
            "Server error budget is fine (not an HTTP status)",
        ] {
            let copy = NoticeCopy(message: message)
            XCTAssertEqual(copy.text, message)
            XCTAssertNil(copy.detail)
        }
    }

    // MARK: Sparklines

    func testSparklineGapsStayGaps() {
        let runs = SparklineGeometry.runs([1, nil, 2, 3, nil, nil, 4, .nan])
        XCTAssertEqual(runs.map { $0.map(\.index) }, [[0], [2, 3], [6]])
        XCTAssertTrue(SparklineGeometry.runs([nil, nil]).isEmpty)
    }

    func testSparklineDomainWidensAFlatSeries() {
        XCTAssertEqual(SparklineGeometry.domain([nil, 5, 5]), 4...6)
        XCTAssertEqual(SparklineGeometry.domain([3, nil, 9]), 3...9)
        XCTAssertNil(SparklineGeometry.domain([nil]))
    }

    // MARK: Fixtures

    private func today(readiness: Double, decision: Decision) -> TodayDTO {
        let pillar = PillarScore(score: 70, drivers: [])
        return TodayDTO(
            date: "2026-10-24", readiness: readiness, decision: decision, calibrating: false,
            pillars: Pillars(sleep: pillar, recovery: pillar, load: pillar),
            overridesApplied: [], confidence: "high", missing: [], sleepPending: nil,
            advisor: AdvisorNote(decision: decision, why: [], prescription: "", ifIgnored: "", source: "template")
        )
    }

    private func baseline(
        today: Double?, normal: Double?, band: (Double, Double)?, good: String, position: MetricPosition?
    ) -> MetricBaselineDTO {
        MetricBaselineDTO(
            today: today,
            baseline30d: normal,
            neutralBand: band.map { NeutralBandDTO(low: $0.0, high: $0.1) },
            recent14d: Array(repeating: nil, count: 13) + [today],
            goodDirection: good,
            position: position
        )
    }

    private func decodeBaseline(_ json: String) throws -> MetricBaselineDTO {
        try JSONDecoder().decode(MetricBaselineDTO.self, from: Data(json.utf8))
    }
}
