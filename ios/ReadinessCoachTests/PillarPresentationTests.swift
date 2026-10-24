import XCTest
@testable import ReadinessCoach

/// Presentation models behind the Recovery, Sleep and Train tabs. Fixtures are
/// decoded from JSON so they keep compiling as server DTOs gain optional fields.
final class PillarPresentationTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func today(date: String = "2026-10-24", calibrating: Bool = false, confidence: String = "high") throws -> TodayDTO {
        try decode(TodayDTO.self, """
        {"date":"\(date)","readiness":72,"decision":"maintain","calibrating":\(calibrating),
         "pillars":{"sleep":{"score":64,"drivers":[{"text":"Short night","detail":"6h 10m"}]},
                    "recovery":{"score":81,"drivers":[{"text":"HRV above normal","detail":null}]},
                    "load":{"score":48,"drivers":[]}},
         "overridesApplied":[],"confidence":"\(confidence)","missing":[],
         "advisor":{"decision":"maintain","why":[],"prescription":"","ifIgnored":"","source":"template"}}
        """)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: Score head

    func testHeadWithoutTodayShowsADashAndTheRealWeight() {
        let model = PillarHeadModel(pillar: .sleep, today: nil, currentDay: "2026-10-24")
        XCTAssertNil(model.score)
        XCTAssertTrue(model.drivers.isEmpty)
        XCTAssertEqual(model.note, "35% of readiness · No score yet")
        XCTAssertFalse(model.hasCaveat)
        XCTAssertTrue(model.accessibilityLabel.contains("Sleep score unavailable"))
    }

    func testHeadUsesTheServerPillarScoreAndDrivers() throws {
        let model = PillarHeadModel(pillar: .recovery, today: try today(), currentDay: "2026-10-24", detail: "HRV and RHR")
        XCTAssertEqual(model.score, 81)
        XCTAssertEqual(model.drivers, [Driver(text: "HRV above normal", detail: nil)])
        XCTAssertEqual(model.note, "40% of readiness")
        XCTAssertEqual(model.meaning, "HRV and RHR")
        XCTAssertFalse(model.hasCaveat)
        XCTAssertTrue(model.accessibilityLabel.hasPrefix("Recovery score 81 out of 100"))
    }

    func testHeadFlagsAnOldCalibratingLowConfidenceScore() throws {
        let model = PillarHeadModel(
            pillar: .load,
            today: try today(date: "2026-10-22", calibrating: true, confidence: "low"),
            currentDay: "2026-10-24"
        )
        XCTAssertEqual(model.score, 48)
        XCTAssertTrue(model.hasCaveat)
        XCTAssertTrue(model.note.hasPrefix("25% of readiness · Score from "))
        XCTAssertTrue(model.note.contains("Calibrating to your baseline"))
        XCTAssertTrue(model.note.contains("Low confidence: some data is missing"))
    }

    // MARK: Recovery

    private func bodySeries() throws -> BodySeries {
        let rows: [(String, String, Double)] = [
            ("hrv_sdnn", "2026-10-10", 40),
            ("hrv_sdnn", "2026-10-20", 48),
            ("hrv_sdnn", "2026-10-22", 52),
            ("hrv_sdnn", "2026-10-24", 55),
            ("resting_heart_rate", "2026-10-23", 54),
            ("resting_heart_rate", "2026-10-24", 52),
        ]
        let json = "[" + rows.map { type, date, avg in
            #"{"type":"\#(type)","date":"\#(date)","min":\#(avg - 5),"avg":\#(avg),"max":\#(avg + 5),"count":3}"#
        }.joined(separator: ",") + "]"
        return BodySeries(try decode([BodyDaily].self, json))
    }

    func testRecoveryWindowKeepsOnlyTheTrailingDays() throws {
        let series = try bodySeries()
        let end = ChartDate.day("2026-10-24")
        XCTAssertEqual(RecoveryWindow.points(series.hrv, days: 7, endingOn: end).map(\.avg), [48, 52, 55])
        XCTAssertEqual(RecoveryWindow.points(series.hrv, days: 30, endingOn: end).count, 4)
        XCTAssertTrue(RecoveryWindow.points(series.hrv, days: 0, endingOn: end).isEmpty)
    }

    func testRecoveryDomainFitsTheServerNormalWithoutInventingOne() {
        let withNormal = RecoveryWindow.domain([48, 52], normal: 60)
        XCTAssertNotNil(withNormal)
        XCTAssertLessThan(withNormal!.lowerBound, 48)
        XCTAssertGreaterThan(withNormal!.upperBound, 60)
        XCTAssertEqual(RecoveryWindow.domain([1], normal: nil)?.lowerBound, 0, "never below zero")
        XCTAssertNil(RecoveryWindow.domain([], normal: nil))
    }

    func testLastWeekListsSevenDaysNewestFirstWithGaps() throws {
        let rows = RecoveryDayRow.lastWeek(try bodySeries(), endingOn: ChartDate.day("2026-10-24"))
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows.first?.date, ChartDate.day("2026-10-24"))
        XCTAssertEqual(rows.last?.date, ChartDate.day("2026-10-18"))
        XCTAssertEqual(rows[0].hrv, 55)
        XCTAssertEqual(rows[0].restingHr, 52)
        XCTAssertNil(rows[1].hrv, "Oct 23 has resting HR but no HRV")
        XCTAssertEqual(rows[1].restingHr, 54)
        XCTAssertNil(rows[3].hrv)
        XCTAssertNil(rows[3].restingHr)
    }

    // MARK: Sleep

    private func night(_ date: String, hours: Double, stages: (Double, Double, Double, Double) = (1, 1.5, 4, 0.5), timeline: String = "null") throws -> SleepDay {
        try decode(SleepDay.self, """
        {"date":"\(date)","durationHours":\(hours),"restorativeHours":\(stages.0 + stages.1),
         "sleepStart":"2026-10-23T23:48:00.000Z","sleepEnd":"2026-10-24T07:20:00Z",
         "stages":{"deep":\(stages.0),"rem":\(stages.1),"core":\(stages.2),"awake":\(stages.3)},
         "timeline":\(timeline)}
        """)
    }

    func testStageSharesAreInDepthOrderAndEmptyWithoutStages() throws {
        let shares = SleepStageShare.shares(try night("2026-10-24", hours: 7).stages)
        XCTAssertEqual(shares.map(\.stage), [.deep, .rem, .core, .awake])
        XCTAssertEqual(shares.map(\.fraction).reduce(0, +), 1, accuracy: 0.0001)
        XCTAssertEqual(shares[0].fraction, 1.0 / 7.0, accuracy: 0.0001)
        XCTAssertTrue(SleepStageShare.shares(try night("2026-10-24", hours: 7, stages: (0, 0, 0, 0)).stages).isEmpty)
    }

    func testHypnogramParsesBothTimestampFormsAndDropsBadBlocks() throws {
        let timeline = """
        [{"stage":"rem","startAt":"2026-10-24T02:00:00Z","endAt":"2026-10-24T02:30:00Z","hours":0.5},
         {"stage":"Deep","startAt":"2026-10-24T00:00:00.000Z","endAt":"2026-10-24T01:00:00.000Z","hours":1},
         {"stage":"nap","startAt":"2026-10-24T03:00:00Z","endAt":"2026-10-24T03:30:00Z","hours":0.5},
         {"stage":"core","startAt":"2026-10-24T04:00:00Z","endAt":"2026-10-24T04:00:00Z","hours":0},
         {"stage":"awake","startAt":"not a time","endAt":"2026-10-24T05:00:00Z","hours":0.1}]
        """
        let segments = HypnogramSegment.segments(try night("2026-10-24", hours: 7, timeline: timeline).timeline)
        XCTAssertEqual(segments.map(\.stage), [.deep, .rem], "sorted by start; unknown, empty and unparseable blocks dropped")
        XCTAssertEqual(segments[0].end.timeIntervalSince(segments[0].start), 3600)
        XCTAssertTrue(HypnogramSegment.segments(nil).isEmpty)
    }

    func testNightSelectionFallsBackKeepsAndSteps() throws {
        let nights = try ["2026-10-21", "2026-10-22", "2026-10-24"].map { try night($0, hours: 7) }
        XCTAssertEqual(NightSelection.night(nil, in: nights)?.id, "2026-10-24")
        XCTAssertEqual(NightSelection.night("2026-10-22", in: nights)?.id, "2026-10-22")
        XCTAssertEqual(NightSelection.night("2026-09-01", in: nights)?.id, "2026-10-24", "out of range falls back to latest")
        XCTAssertNil(NightSelection.night(nil, in: []))

        XCTAssertEqual(NightSelection.keep("2026-10-22", in: nights), "2026-10-22")
        XCTAssertNil(NightSelection.keep("2026-09-01", in: nights))
        XCTAssertNil(NightSelection.keep(nil, in: nights))

        XCTAssertEqual(NightSelection.step(from: nil, by: -1, in: nights), "2026-10-22")
        XCTAssertEqual(NightSelection.step(from: "2026-10-21", by: -1, in: nights), "2026-10-21", "clamped at the oldest")
        XCTAssertEqual(NightSelection.step(from: "2026-10-22", by: 5, in: nights), "2026-10-24", "clamped at the latest")
        XCTAssertNil(NightSelection.step(from: nil, by: 1, in: []))
    }

    func testRangeAverageIsTheMeanOfTheNightsShown() throws {
        let nights = try [6.0, 7.0, 8.5].enumerated().map { try night("2026-10-2\($0.offset)", hours: $0.element) }
        XCTAssertEqual(NightSelection.averageHours(nights)!, 7.1667, accuracy: 0.001)
        XCTAssertNil(NightSelection.averageHours([SleepDay]()))
    }

    // MARK: Train

    private func workouts(_ items: [(sport: String, start: String, strain: Double, minutes: Double)]) throws -> [WorkoutDTO] {
        let json = "[" + items.enumerated().map { index, item in
            """
            {"id":"w\(index)","sport":"\(item.sport)","startAt":"\(item.start)","endAt":"\(item.start)",
             "durationMin":\(item.minutes),"avgHrBpm":140,"maxHrBpm":170,"calories":300,"strain":\(item.strain),"hrZonesMin":null}
            """
        }.joined(separator: ",") + "]"
        return try decode([WorkoutDTO].self, json)
    }

    func testTrainWeekHasSevenDaysWithRestDaysAndComparesThePriorWeek() throws {
        let calendar = utcCalendar()
        let now = try XCTUnwrap(PillarTime.parse("2026-10-24T18:00:00Z"))
        let list = try workouts([
            ("running", "2026-10-24T07:00:00Z", 10, 40),
            ("traditional_strength", "2026-10-24T17:00:00.000Z", 6, 50),
            ("yoga", "2026-10-20T07:00:00Z", 2.5, 30),
            ("cycling", "2026-10-18T07:00:00Z", 12, 90),  // first day of the week
            ("running", "2026-10-17T07:00:00Z", 9, 45),   // prior week
            ("running", "2026-10-11T07:00:00Z", 4, 30),   // prior week, first day
            ("running", "2026-10-10T07:00:00Z", 20, 120), // outside both
        ])
        let series = TrainSeries(list, now: now, calendar: calendar)

        XCTAssertEqual(series.days.count, 7)
        XCTAssertEqual(series.days.first?.date, PillarTime.parse("2026-10-18T00:00:00Z"))
        XCTAssertEqual(series.days.last?.date, PillarTime.parse("2026-10-24T00:00:00Z"))
        XCTAssertEqual(series.days.map(\.sessions), [1, 0, 1, 0, 0, 0, 2])
        XCTAssertEqual(series.days.map(\.isRest), [false, true, false, true, true, true, false])
        XCTAssertEqual(series.days.last?.strain, 16)
        XCTAssertEqual(series.days.last?.minutes, 90)

        XCTAssertEqual(series.week.count, 4)
        XCTAssertEqual(series.weekStrain, 30.5)
        XCTAssertEqual(series.weekMinutes, 210)
        XCTAssertEqual(series.weekHardest?.sport, "cycling")
        XCTAssertEqual(series.priorWeekStrain, 13)
        XCTAssertEqual(series.sorted.map(\.id), ["w1", "w0", "w2", "w3", "w4", "w5", "w6"])
    }

    func testWorkoutsGroupByLocalDayNewestFirstWithTodayAndYesterday() throws {
        let calendar = utcCalendar()
        let now = try XCTUnwrap(PillarTime.parse("2026-10-24T18:00:00Z"))
        let list = try workouts([
            ("running", "2026-10-24T17:00:00Z", 6, 50),
            ("running", "2026-10-24T07:00:00Z", 10, 40),
            ("yoga", "2026-10-23T07:00:00Z", 2, 30),
            ("cycling", "2026-10-20T07:00:00Z", 12, 90),
            ("swimming", "garbage", 3, 20),
        ])
        let groups = WorkoutDayGroup.groups(TrainSeries(list, now: now, calendar: calendar).sorted, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.title).prefix(2), ["Today", "Yesterday"])
        XCTAssertEqual(groups.count, 4)
        XCTAssertEqual(groups[0].workouts.map(\.id), ["w0", "w1"], "newest first within a day")
        XCTAssertEqual(groups[2].day, PillarTime.parse("2026-10-20T00:00:00Z"))
        XCTAssertEqual(groups.last?.title, "Date unknown")
        XCTAssertNil(groups.last?.day)

        let recovery = WorkoutDayGroup.filter(groups) { WorkoutSport.filterCategory(forKey: $0.sport) == "Recovery" }
        XCTAssertEqual(recovery.map(\.title), ["Yesterday"])
        XCTAssertEqual(recovery.first?.workouts.map(\.id), ["w2"])
    }

    func testHeartRateZonesKeepOnlyRecordedTime() {
        XCTAssertTrue(HRZoneSegment.segments(nil).isEmpty)
        XCTAssertTrue(HRZoneSegment.segments([0, 0, 0, 0, 0]).isEmpty)
        let zones = HRZoneSegment.segments([10, 0, 20, 10, 0])
        XCTAssertEqual(zones.map(\.index), [0, 2, 3])
        XCTAssertEqual(zones.map(\.label), ["Z1 Easy", "Z3 Moderate", "Z4 Hard"])
        XCTAssertEqual(zones.map(\.fraction), [0.25, 0.5, 0.25])
    }

    // MARK: Source guards

    private func viewSource(_ file: String) throws -> String {
        let views = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ReadinessCoach/Views")
        return try String(contentsOf: views.appendingPathComponent(file), encoding: .utf8)
    }

    /// The old 8-hour "target" wasn't the user's goal; nothing on Sleep may
    /// present a hardcoded goal.
    func testSleepHasNoHardcodedTarget() throws {
        let source = try viewSource("SleepView.swift")
        XCTAssertFalse(source.contains("needHours"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("target"))
    }

    /// Pillar helpers render inside the pillar tabs, so they inherit the rule
    /// that upload ticks must not re-render them.
    func testPillarHelpersDoNotObserveSettingsOrSync() throws {
        let observed = try NSRegularExpression(
            pattern: #"@(EnvironmentObject|ObservedObject|StateObject)\b[^\n]*:\s*(AppSettings|SyncService)\b"#
        )
        for file in ["PillarCommon.swift", "PillarPresentation.swift"] {
            let source = try viewSource(file)
            XCTAssertNil(observed.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)), file)
        }
    }
}
