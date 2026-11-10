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

    private final class Recorder: @unchecked Sendable {
        var calls: [(question: String, date: String, history: [CoachTurnDTO])] = []
        var results: [Result<String, Error>] = []
        var decision: Decision = .maintain
        func next(_ q: String, _ d: String, _ h: [CoachTurnDTO]) async throws -> AskResponse {
            calls.append((q, d, h))
            if results.isEmpty { return AskResponse(decision: decision, answer: "answer to \(q)") }
            return AskResponse(decision: decision, answer: try results.removeFirst().get())
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

    func testOpeningLineWithoutLowPillarStillHasRealNumbers() {
        let t = today(recovery: 70, sleep: 58, load: 75, decision: .maintain)
        let line = CoachPrompts.openingLine(t)
        XCTAssertTrue(line.contains("70"), line)  // readiness
        XCTAssertTrue(line.contains("Sleep"), line)
        XCTAssertTrue(line.contains("58"), line)
        for decision in Decision.allCases {
            XCTAssertTrue(CoachPrompts.openingLine(today(decision: decision)).contains("Readiness 70"))
        }
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

    func testRestingHRIsIncludedWhenItHasATodayValue() {
        var t = today()
        t.baselines = TodayBaselinesDTO(
            hrv: baseline(today: 40, normal: 55),
            restingHr: baseline(today: 60, normal: 55, good: "down"),
            sleepHours: baseline(today: 6, normal: 7.5),
            load7d: baseline(today: 12, normal: 10, good: "none")
        )
        XCTAssertEqual(CoachFocusModel(focus: .pillar(.recovery), today: t).factors.map(\.metric), [.hrv, .restingHr])
    }

    func testSleepAndLoadFocusFactors() {
        XCTAssertEqual(CoachFocusModel(focus: .pillar(.sleep), today: today()).factors.map(\.metric), [.sleepHours])
        XCTAssertEqual(CoachFocusModel(focus: .pillar(.load), today: today()).factors.map(\.metric), [.load7d])
    }

    func testOpeningLineBoundaries() {
        // Lowest exactly 50: not below 50.
        XCTAssertNil(CoachPrompts.notablyLowPillar(today(recovery: 50, sleep: 80, load: 90)))
        // Gap of exactly 15 with lowest under 50: named.
        XCTAssertEqual(CoachPrompts.notablyLowPillar(today(recovery: 40, sleep: 55, load: 90))?.pillar, .recovery)
        // Tie for lowest: not named.
        XCTAssertNil(CoachPrompts.notablyLowPillar(today(recovery: 30, sleep: 30, load: 90)))
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

    func testFailedLastPairDoesNotBlockAskAtCap() async {
        let rec = Recorder()
        rec.results = Array(repeating: .success("ok"), count: 9) + [.failure(URLError(.timedOut))]
        let convo = conversation(rec)
        for i in 0..<10 { await convo.ask("q\(i)") }
        XCTAssertEqual(convo.messages.count, 20)
        XCTAssertFalse(convo.isAtCap)
        await convo.ask("after failure")
        XCTAssertEqual(rec.calls.count, 11)
        XCTAssertEqual(rec.calls[10].history.count, 18)
        XCTAssertEqual(convo.messages.count, 20)
        XCTAssertTrue(convo.isAtCap)
    }

    func testLongCoachAnswerIsCappedInHistory() async {
        let rec = Recorder()
        rec.results = [.success(String(repeating: "a", count: 4500))]
        let convo = conversation(rec)
        await convo.ask("one")
        await convo.ask("two")
        let entries = rec.calls[1].history
        XCTAssertEqual(entries.count, 2)
        XCTAssertLessThanOrEqual(entries[1].content.count, 4000)
    }

    func testEmojiAnswerIsCappedInUTF16Units() async {
        let rec = Recorder()
        rec.results = [.success(String(repeating: "💪", count: 3000))]
        let convo = conversation(rec)
        await convo.ask("one")
        await convo.ask("two")
        let content = rec.calls[1].history[1].content
        XCTAssertEqual(content.utf16.count, 4000)
        XCTAssertEqual(content, String(repeating: "💪", count: 2000))
    }

    func testEmptyAnswerIsDroppedFromHistory() async {
        let rec = Recorder()
        rec.results = [.success("   ")]
        let convo = conversation(rec)
        await convo.ask("one")
        await convo.ask("two")
        XCTAssertEqual(rec.calls[1].history.map(\.content), ["one"])
    }

    func testOverlongQuestionIsIgnored() async {
        let rec = Recorder()
        let convo = conversation(rec)
        await convo.ask(String(repeating: "q", count: CoachConversation.maxQuestionLength + 1))
        XCTAssertTrue(rec.calls.isEmpty)
        await convo.ask(String(repeating: "q", count: CoachConversation.maxQuestionLength))
        XCTAssertEqual(rec.calls.count, 1)
    }

    func testNewAskRemovesOldFailedPair() async {
        let rec = Recorder()
        rec.results = [.failure(Boom())]
        let convo = conversation(rec)
        await convo.ask("one")
        XCTAssertEqual(convo.messages.count, 2)
        XCTAssertEqual(convo.messages.last?.state, .failed)
        await convo.ask("two")
        XCTAssertEqual(convo.messages.map(\.text), ["two", "answer to two"])
        XCTAssertFalse(convo.messages.contains { $0.state == .failed })
        await convo.retry()
        XCTAssertEqual(rec.calls.count, 2)
    }

    func testFailureKindsMapToCopy() async {
        let cases: [(Error, CoachMessage.Failure, String)] = [
            (URLError(.notConnectedToInternet), .network, "Couldn't reach the coach. Check your connection."),
            (APIError.transport(URLError(.timedOut)), .network, "Couldn't reach the coach. Check your connection."),
            (APIError.http(status: 503, code: "coach_unavailable"), .unavailable, "The coach is unavailable right now."),
            (APIError.http(status: 500, code: nil), .other, "Something went wrong."),
            (Boom(), .other, "Something went wrong."),
        ]
        for (error, kind, copy) in cases {
            let rec = Recorder()
            rec.results = [.failure(error)]
            let convo = conversation(rec)
            await convo.ask("q")
            XCTAssertEqual(convo.messages.last?.failure, kind)
            XCTAssertEqual(convo.messages.last?.failure?.message, copy)
        }
    }

    func testRetryClearsFailureKind() async {
        let rec = Recorder()
        rec.results = [.failure(URLError(.timedOut))]
        let convo = conversation(rec)
        await convo.ask("q")
        await convo.retry()
        XCTAssertNil(convo.messages.last?.failure)
        XCTAssertEqual(convo.messages.last?.state, .done)
    }

    func testChangedDecisionSetsNumbersChanged() async {
        let rec = Recorder()
        rec.decision = .recover  // today() is .maintain
        let convo = conversation(rec)
        XCTAssertFalse(convo.numbersChanged)
        await convo.ask("q")
        XCTAssertTrue(convo.numbersChanged)
        convo.reset()
        XCTAssertFalse(convo.numbersChanged)
    }

    func testSameDecisionLeavesNumbersUnchanged() async {
        let rec = Recorder()
        let convo = conversation(rec)
        await convo.ask("q")
        XCTAssertFalse(convo.numbersChanged)
    }

    func testHistoryIsTrimmedToServerBudgetDroppingOldestPairs() async {
        let rec = Recorder()
        rec.results = (0..<6).map { _ in .success(String(repeating: "a", count: 3900)) }
        let convo = conversation(rec)
        for i in 0..<6 { await convo.ask("q\(i)") }
        let history = rec.calls[5].history
        XCTAssertLessThanOrEqual(history.reduce(0) { $0 + $1.content.utf16.count }, CoachConversation.maxHistoryTotalLength)
        XCTAssertEqual(history.count, 8)  // five pairs would be 19,5xx units; the oldest pair went
        XCTAssertEqual(history.first?.role, "user")
        XCTAssertEqual(history.first?.content, "q1")
        XCTAssertEqual(history.last?.role, "assistant")
    }

    func testMidAnswerLockedDecisionIsNotSplit() async {
        let rec = Recorder()
        let answer = "Intro.\n\nLocked decision: RECOVER. Do not train hard today; walk, mobility, or full rest only.\n\nMore prose after it."
        rec.results = [.success(answer)]
        let convo = conversation(rec)
        await convo.ask("q")
        XCTAssertNil(convo.messages[1].lockNote)
        XCTAssertEqual(convo.messages[1].text, answer)
    }

    func testInlineDirectiveWithoutParagraphBreakIsNotSplit() {
        let text = "Stay easy. Locked decision: MAINTAIN. No PRs or maximal work; cap intensity at RPE 7."
        XCTAssertNil(CoachConversation.splitLockNote(text).lockNote)
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
        rec.results = [.success("Take it easy.\n\nLocked decision: RECOVER. Do not train hard today; walk, mobility, or full rest only.")]
        let convo = conversation(rec)
        await convo.ask("can I run?")
        let coach = convo.messages[1]
        XCTAssertEqual(coach.text, "Take it easy.")
        XCTAssertEqual(coach.lockNote, "Locked decision: RECOVER. Do not train hard today; walk, mobility, or full rest only.")

        await convo.ask("and tomorrow?")
        XCTAssertEqual(
            rec.calls[1].history.last?.content,
            "Take it easy.\n\nLocked decision: RECOVER. Do not train hard today; walk, mobility, or full rest only."
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
