import XCTest
import SwiftUI
@testable import ReadinessCoach

final class SupportScreensTests: XCTestCase {
    func testAccountInitialsComeFromTheDisplayNameOnly() {
        XCTAssertEqual(SettingsView.initials("Shawn George"), "SG")
        XCTAssertEqual(SettingsView.initials("ada"), "A")
        XCTAssertEqual(SettingsView.initials("Mary Ann Smith"), "MA")
        XCTAssertNil(SettingsView.initials("   "))
        XCTAssertNil(SettingsView.initials(nil))
    }

    func testDestructiveConfirmationExecutesExactlyOnce() {
        var confirmation = SheetConfirmation()
        var deletions = 0

        XCTAssertTrue(confirmation.confirm { deletions += 1 })
        XCTAssertFalse(confirmation.confirm { deletions += 1 })
        confirmation.cancel()
        XCTAssertFalse(confirmation.confirm { deletions += 1 })
        XCTAssertEqual(deletions, 1)
    }

    func testCancellationOrDismissalDoesNotExecuteDestructiveAction() {
        var confirmation = SheetConfirmation()
        var deletions = 0

        confirmation.cancel()
        confirmation.cancel()
        XCTAssertFalse(confirmation.confirm { deletions += 1 })
        XCTAssertEqual(deletions, 0)
    }

    func testNewPresentationRequiresItsOwnConfirmation() {
        var cancelled = SheetConfirmation()
        var nextPresentation = SheetConfirmation()
        var deletions = 0

        cancelled.cancel()
        XCTAssertEqual(deletions, 0)
        XCTAssertTrue(nextPresentation.confirm { deletions += 1 })
        XCTAssertFalse(cancelled.confirm { deletions += 1 })
        XCTAssertEqual(deletions, 1)
    }

    func testAskKeepsOriginalDayAndConservativeDecisionAfterRefresh() {
        var displayed = today(date: "2026-10-23", decision: .recover)
        let frozen = AskContext(displayed)

        displayed = today(date: "2026-10-24", decision: .push)

        XCTAssertEqual(frozen.date, "2026-10-23")
        XCTAssertEqual(frozen.decision, .recover)
        XCTAssertEqual(displayed.decision, .push)
    }

    @MainActor
    func testKeyboardSendSubmitsTheCurrentDraftFromAnyCursorPosition() {
        var draft = "Old draft"
        var focused = true
        var sent: [String] = []
        let field = CoachQuestionField(text: Binding(get: { draft }, set: { draft = $0 }),
                                       isFocused: Binding(get: { focused }, set: { focused = $0 }),
                                       onSubmit: { sent.append(draft) })
        let coordinator = field.makeCoordinator()
        let native = UITextView()
        native.text = "The autocorrected question"

        XCTAssertFalse(coordinator.textView(native, shouldChangeTextIn: NSRange(location: 4, length: 0), replacementText: "\n"))
        XCTAssertEqual(sent, ["The autocorrected question"])
        XCTAssertFalse(focused)
    }

    @MainActor
    func testPastedParagraphsRemainEditableWithoutSending() {
        var sent = 0
        let field = CoachQuestionField(text: .constant("Draft"), isFocused: .constant(true), onSubmit: { sent += 1 })
        let native = UITextView()
        native.text = "Draft"
        XCTAssertTrue(field.makeCoordinator().textView(native, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: "First question\nMore context\n"))
        XCTAssertEqual(sent, 0)
    }

    func testPillarSheetKeepsTheTodayCallSiteAPI() {
        let info = PillarInfo(name: "Sleep", weight: "35%", description: Pillar.sleep.summary,
                              pillar: PillarScore(score: 72, drivers: [Driver(text: "7h 40m asleep", detail: nil)]))
        XCTAssertEqual(info.name, "Sleep")
        XCTAssertEqual(info.pillar.drivers.count, 1)
        _ = PillarDetailSheet(info: info)
    }

    private func today(date: String, decision: Decision) -> TodayDTO {
        let pillar = PillarScore(score: 70, drivers: [])
        return TodayDTO(
            date: date, readiness: 70, decision: decision, calibrating: false,
            pillars: Pillars(sleep: pillar, recovery: pillar, load: pillar),
            overridesApplied: [], confidence: "high", missing: [], sleepPending: nil,
            advisor: AdvisorNote(decision: decision, why: [], prescription: "", ifIgnored: "", source: "template")
        )
    }
}
