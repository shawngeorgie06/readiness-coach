import XCTest
@testable import ReadinessCoach

@MainActor
final class CoachLogicTests: XCTestCase {
    // MARK: Fixtures

    private func baseline(today: Double?, normal: Double?, good: String = "up") -> MetricBaselineDTO {
        MetricBaselineDTO(
            today: today, baseline30d: normal, neutralBand: nil,
            recent14d: (1...14).map { Double($0) }, goodDirection: good,
            position: today == nil ? nil : .below
        )
    }

    private func today(
        recovery: Double = 70, sleep: Double = 72, load: Double = 75,
        decision: Decision = .maintain, withBaselines: Bool = true
    ) -> TodayDTO {
        func pillar(_ score: Double) -> PillarScore {
            PillarScore(score: score, drivers: [Driver(text: "Driver \(Int(score))", detail: nil)])
        }
        let baselines = TodayBaselinesDTO(
            hrv: baseline(today: 40, normal: 55),
            restingHr: baseline(today: nil, normal: nil, good: "down"),
            sleepHours: baseline(today: 6, normal: 7.5),
            load7d: baseline(today: 12, normal: 10, good: "none")
        )
        return TodayDTO(
            date: "2026-11-09", readiness: 70, decision: decision, calibrating: false,
            pillars: Pillars(sleep: pillar(sleep), recovery: pillar(recovery), load: pillar(load)),
            overridesApplied: [], confidence: "high", missing: [], sleepPending: nil,
            advisor: AdvisorNote(decision: decision, why: [], prescription: "", ifIgnored: "", source: "template"),
            baselines: withBaselines ? baselines : nil
        )
    }

    private struct Boom: Error {}

    private final class Recorder {
        var calls: [(question: String, date: String, history: [CoachTurnDTO])] = []
        var results: [Result<String, Error>] = []
        func next(_ q: String, _ d: String, _ h: [CoachTurnDTO]) async throws -> String {
            calls.append((q, d, h))
            if results.isEmpty { return "answer to \(q)" }
            return try results.removeFirst().get()
        }
    }

    private func conversation(_ rec: Recorder, focus: CoachFocus = .readiness) -> CoachConversation {
        CoachConversation(today: today(), focus: focus) { try await rec.next($0, $1, $2) }
    }

    // MARK: Prompts

    func testOpeningLineNamesNotablyLowPillar() {
        let line = CoachPrompts.openingLine(today(recovery: 9, sleep: 81, load: 91))
        XCTAssertTrue(line.lowercased().contains("recovery"))
        XCTAssertTrue(line.contains("9"))
    }

    func testOpeningLineSpeaksToDecisionWhenNoPillarIsNotablyLow() {
        let lines = Decision.allCases.map { CoachPrompts.openingLine(today(recovery: 70, sleep: 72, load: 75, decision: $0)) }
        XCTAssertEqual(Set(lines).count, 3)
    }

    func testLowPillarCloseToNextLowestIsNotNotable() {
        XCTAssertNil(CoachPrompts.notablyLowPillar(today(recovery: 40, sleep: 50, load: 80)))
    }

    func testSuggestionsAreTwo() {
        for decision in Decision.allCases {
            XCTAssertEqual(CoachPrompts.suggestions(today(decision: decision)).count, 2)
        }
        XCTAssertEqual(CoachPrompts.suggestions(today(recovery: 9, sleep: 81, load: 91)).count, 2)
    }

    func testFollowUpsAreTwoOrThree() {
        for decision in Decision.allCases {
            for focus in [CoachFocus.readiness, .pillar(.sleep)] {
                let count = CoachPrompts.followUps(for: focus, decision: decision).count
                XCTAssertTrue((2...3).contains(count))
            }
        }
    }

    // MARK: Focus model

    func testRecoveryFocusFactorsAreHRVAndRestingHR() {
        // Resting HR has no value today, so only HRV survives the filter.
        let model = CoachFocusModel(focus: .pillar(.recovery), today: today())
        XCTAssertEqual(model.factors.map(\.metric), [.hrv])
        XCTAssertEqual(model.trend.count, 7)
        XCTAssertEqual(model.trend.last ?? nil, 14)
    }

    func testFocusWithNilBaselinesHasNoFactorsButHasDrivers() {
        let model = CoachFocusModel(focus: .pillar(.recovery), today: today(recovery: 33, withBaselines: false))
        XCTAssertTrue(model.factors.isEmpty)
        XCTAssertTrue(model.trend.isEmpty)
        XCTAssertEqual(model.fallbackDrivers, ["Driver 33"])
    }

    func testWeightLabels() {
        let t = today()
        XCTAssertEqual(CoachFocusModel(focus: .pillar(.recovery), today: t).weightLabel, "40% of readiness")
        XCTAssertEqual(CoachFocusModel(focus: .pillar(.sleep), today: t).weightLabel, "35% of readiness")
        XCTAssertEqual(CoachFocusModel(focus: .pillar(.load), today: t).weightLabel, "25% of readiness")
        let readiness = CoachFocusModel(focus: .readiness, today: t)
        XCTAssertNil(readiness.weightLabel)
        XCTAssertEqual(readiness.pillarScores.count, 3)
        XCTAssertEqual(readiness.score, 70)
    }

    // MARK: Conversation

    func testHistoryExcludesFailedAndPendingMessages() async {
        let rec = Recorder()
        let convo = conversation(rec)
        await convo.ask("one")
        rec.results = [.failure(Boom())]
        await convo.ask("two")
        XCTAssertEqual(convo.messages.last?.state, .failed)
        await convo.ask("three")
        let history = rec.calls.last!.history
        XCTAssertEqual(history.map(\.content), ["one", "answer to one"])
        XCTAssertEqual(history.map(\.role), ["user", "assistant"])
        XCTAssertEqual(rec.calls.last!.date, "2026-11-09")
    }

    func testCapBlocksTwentyFirstRequest() async {
        let rec = Recorder()
        let convo = conversation(rec)
        for i in 0..<10 { await convo.ask("q\(i)") }
        XCTAssertEqual(rec.calls.count, 10)
        XCTAssertTrue(convo.isAtCap)
        await convo.ask("one more")
        XCTAssertEqual(rec.calls.count, 10)
        XCTAssertEqual(convo.messages.count, 20)
    }

    func testBlankQuestionIsIgnored() async {
        let rec = Recorder()
        let convo = conversation(rec)
        await convo.ask("  \n ")
        XCTAssertTrue(rec.calls.isEmpty)
        XCTAssertTrue(convo.messages.isEmpty)
    }

    func testFailureKeepsEarlierMessagesAndRetryResendsSameQuestionAndHistory() async {
        let rec = Recorder()
        let convo = conversation(rec)
        await convo.ask("first")
        rec.results = [.failure(Boom())]
        await convo.ask("second")
        XCTAssertEqual(convo.messages.count, 4)
        XCTAssertEqual(convo.messages[0].state, .done)
        XCTAssertEqual(convo.messages[1].text, "answer to first")
        XCTAssertEqual(convo.messages[3].state, .failed)

        await convo.retry()
        XCTAssertEqual(rec.calls.count, 3)
        XCTAssertEqual(rec.calls[2].question, "second")
        XCTAssertEqual(rec.calls[2].history, rec.calls[1].history)
        XCTAssertEqual(convo.messages.count, 4)
        XCTAssertEqual(convo.messages[3].state, .done)
        XCTAssertEqual(convo.messages[3].text, "answer to second")
        XCTAssertEqual(convo.messages[2].state, .done)
    }

    func testLockParagraphIsSplitIntoLockNote() async {
        let rec = Recorder()
        rec.results = [.success("Take it easy.\n\nLocked decision: RECOVER. Do not train hard today.")]
        let convo = conversation(rec)
        await convo.ask("can I run?")
        let coach = convo.messages[1]
        XCTAssertEqual(coach.text, "Take it easy.")
        XCTAssertEqual(coach.lockNote, "Locked decision: RECOVER. Do not train hard today.")

        await convo.ask("and tomorrow?")
        XCTAssertEqual(
            rec.calls[1].history.last?.content,
            "Take it easy.\n\nLocked decision: RECOVER. Do not train hard today."
        )
    }

    func testResetClearsMessages() async {
        let rec = Recorder()
        let convo = conversation(rec)
        await convo.ask("hi")
        convo.reset()
        XCTAssertTrue(convo.messages.isEmpty)
        XCTAssertFalse(convo.isAtCap)
    }
}
