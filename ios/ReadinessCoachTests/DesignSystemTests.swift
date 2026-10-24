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
        let c = MetricComparison(metric: .hrv, baseline: baseline(today: 62, normal: 56, band: (53.2, 58.8), good: "up"))
        XCTAssertEqual(c.position, .above)
        XCTAssertEqual(c.tone, .good)
        XCTAssertEqual(c.arrowSymbol, "arrowtriangle.up.fill")
        XCTAssertEqual(c.deltaText, "+6 ms")
        XCTAssertEqual(c.compactText, "+6 ms")
    }

    func testLowerIsGoodMetricAboveItsBandIsBad() {
        let up = MetricComparison(metric: .restingHr, baseline: baseline(today: 58, normal: 52, band: (50.44, 53.56), good: "down"))
        XCTAssertEqual(up.position, .above)
        XCTAssertEqual(up.tone, .bad)
        XCTAssertEqual(up.arrowSymbol, "arrowtriangle.up.fill")

        let down = MetricComparison(metric: .restingHr, baseline: baseline(today: 48, normal: 52, band: (50.44, 53.56), good: "down"))
        XCTAssertEqual(down.position, .below)
        XCTAssertEqual(down.tone, .good)
        XCTAssertEqual(down.arrowSymbol, "arrowtriangle.down.fill")
        XCTAssertEqual(down.deltaText, "\u{2212}4 bpm")
    }

    func testInsideTheBandIsNeutralWithNoArrow() {
        let c = MetricComparison(metric: .hrv, baseline: baseline(today: 57, normal: 56, band: (53.2, 58.8), good: "up"))
        XCTAssertEqual(c.position, .within)
        XCTAssertEqual(c.tone, .neutral)
        XCTAssertNil(c.arrowSymbol)
        XCTAssertEqual(c.summary, "Normal")
    }

    func testLoadOutsideItsBandIsNotableNotGoodOrBad() {
        let c = MetricComparison(metric: .load7d, baseline: baseline(today: 14, normal: 9, band: (6.3, 11.7), good: "none"))
        XCTAssertEqual(c.position, .above)
        XCTAssertEqual(c.tone, .notable)
        XCTAssertEqual(c.deltaText, "+5.0")
    }

    func testNoDataTodayShowsADashAndNoArrow() {
        let c = MetricComparison(metric: .hrv, baseline: baseline(today: nil, normal: 56, band: (53.2, 58.8), good: "up"))
        XCTAssertNil(c.position)
        XCTAssertNil(c.arrowSymbol)
        XCTAssertEqual(c.todayText, "—")
        XCTAssertEqual(c.summary, "No data today")
        XCTAssertNil(c.deltaText)
        XCTAssertEqual(c.accessibilityText, "Heart rate variability: no data today.")
    }

    func testNoNormalYetShowsNotEnoughDataAndNoArrowEvenWithABand() {
        // The sleep band follows the target, so it exists before any history.
        let c = MetricComparison(metric: .sleepHours, baseline: baseline(today: 6, normal: nil, band: (6.75, 8.25), good: "up"))
        XCTAssertNil(c.position)
        XCTAssertNil(c.arrowSymbol)
        XCTAssertEqual(c.tone, .neutral)
        XCTAssertEqual(c.summary, "Not enough data yet")
        XCTAssertEqual(c.compactText, "Not enough data yet")
    }

    func testNoBandMeansNoArrow() {
        let c = MetricComparison(metric: .hrv, baseline: baseline(today: 62, normal: 56, band: nil, good: "up"))
        XCTAssertNil(c.position)
        XCTAssertNil(c.arrowSymbol)
        XCTAssertEqual(c.tone, .neutral)
        XCTAssertEqual(c.deltaText, "+6 ms")
    }

    func testSleepBeatingTheAverageButShortOfTargetSaysBelowTarget() {
        let c = MetricComparison(metric: .sleepHours, baseline: baseline(today: 6, normal: 5, band: (7.2, 8.8), good: "up"))
        XCTAssertEqual(c.position, .below)
        XCTAssertEqual(c.tone, .bad)
        XCTAssertEqual(c.arrowSymbol, "arrowtriangle.down.fill")
        XCTAssertEqual(c.deltaText, "+1h")
        XCTAssertEqual(c.compactText, "Below target", "a down arrow is never paired with a plus sign")
    }

    func testOlderServersWithoutBaselinesProduceNoComparisons() {
        XCTAssertNil(MetricComparison.all(from: nil))
        let all = MetricComparison.all(from: TodayBaselinesDTO(
            hrv: baseline(today: 1, normal: 1, band: nil, good: "up"),
            restingHr: baseline(today: 1, normal: 1, band: nil, good: "down"),
            sleepHours: baseline(today: 1, normal: 1, band: nil, good: "up"),
            load7d: baseline(today: 1, normal: 1, band: nil, good: "none")
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

    // MARK: Band endpoints

    func testHRVBandEndpointsCountAsOutsideLikeTheRecoveryDriver() {
        // recovery.ts: hrvDelta >= 0.05 is "above your normal", <= -0.05 "below".
        let band = (95.0, 105.0)
        let atHigh = MetricComparison(metric: .hrv, baseline: baseline(today: 105, normal: 100, band: band, good: "up"))
        XCTAssertEqual(atHigh.position, .above)
        XCTAssertEqual(atHigh.tone, .good)
        XCTAssertEqual(atHigh.summary, "Above normal")

        let atLow = MetricComparison(metric: .hrv, baseline: baseline(today: 95, normal: 100, band: band, good: "up"))
        XCTAssertEqual(atLow.position, .below)
        XCTAssertEqual(atLow.tone, .bad)
        XCTAssertEqual(atLow.summary, "Below normal")

        for inside in [95.01, 100, 104.99] {
            let c = MetricComparison(metric: .hrv, baseline: baseline(today: inside, normal: 100, band: band, good: "up"))
            XCTAssertEqual(c.position, .within, "\(inside)")
        }
    }

    func testOtherMetricsKeepTheirEndpointsInsideTheBand() {
        // recovery.ts flags resting HR only when rhrDelta > 0.03, strictly.
        let rhrHigh = MetricComparison(metric: .restingHr, baseline: baseline(today: 103, normal: 100, band: (97, 103), good: "down"))
        XCTAssertEqual(rhrHigh.position, .within)
        let rhrLow = MetricComparison(metric: .restingHr, baseline: baseline(today: 97, normal: 100, band: (97, 103), good: "down"))
        XCTAssertEqual(rhrLow.position, .within)
        let rhrOver = MetricComparison(metric: .restingHr, baseline: baseline(today: 103.01, normal: 100, band: (97, 103), good: "down"))
        XCTAssertEqual(rhrOver.position, .above)

        let sleep = MetricComparison(metric: .sleepHours, baseline: baseline(today: 7.2, normal: 7, band: (7.2, 8.8), good: "up"))
        XCTAssertEqual(sleep.position, .within)
        let load = MetricComparison(metric: .load7d, baseline: baseline(today: 11.7, normal: 9, band: (6.3, 11.7), good: "none"))
        XCTAssertEqual(load.position, .within)
    }

    // MARK: Full comparison row

    func testFullRowSeparatesSleepTargetStatusFromChangeVersusAverage() {
        // Beat the 30-day average by an hour, still short of the 8h target.
        let c = MetricComparison(metric: .sleepHours, baseline: baseline(today: 6, normal: 5, band: (7.2, 8.8), good: "up"))
        XCTAssertEqual(c.summary, "Below target", "the arrowed status line names the target")
        XCTAssertEqual(c.changeText, "+1h vs avg", "the change is labelled as against the average")
        XCTAssertEqual(c.normalCaption, "avg 5h", "the reference column doesn't call the average the band")
        XCTAssertEqual(
            c.accessibilityText,
            "Sleep 6 hours. Below target. Up 1 hour versus 30-day average of 5 hours."
        )
    }

    func testFullRowStatesStatusAndChangeForBaselineMetrics() {
        let c = MetricComparison(metric: .hrv, baseline: baseline(today: 62, normal: 56, band: (53.2, 58.8), good: "up"))
        XCTAssertEqual(c.summary, "Above normal")
        XCTAssertEqual(c.changeText, "+6 ms vs normal")
        XCTAssertEqual(c.normalCaption, "normal 56")
        XCTAssertEqual(
            c.accessibilityText,
            "Heart rate variability 62 milliseconds. Above normal. Up 6 milliseconds versus 30-day normal of 56 milliseconds."
        )
    }

    func testFullRowWithoutANormalHasNoChangeLine() {
        let c = MetricComparison(metric: .sleepHours, baseline: baseline(today: 6, normal: nil, band: (6.75, 8.25), good: "up"))
        XCTAssertNil(c.changeText)
        XCTAssertNil(c.normalCaption)
        XCTAssertEqual(c.accessibilityText, "Sleep 6 hours. Not enough data yet.")
    }

    func testUnchangedValueSaysNoChange() {
        let c = MetricComparison(metric: .restingHr, baseline: baseline(today: 52, normal: 52, band: (50.44, 53.56), good: "down"))
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

    private func baseline(today: Double?, normal: Double?, band: (Double, Double)?, good: String) -> MetricBaselineDTO {
        MetricBaselineDTO(
            today: today,
            baseline30d: normal,
            neutralBand: band.map { NeutralBandDTO(low: $0.0, high: $0.1) },
            recent14d: Array(repeating: nil, count: 13) + [today],
            goodDirection: good
        )
    }
}
