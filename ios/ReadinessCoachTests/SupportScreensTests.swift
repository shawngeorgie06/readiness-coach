import XCTest
@testable import ReadinessCoach

final class SupportScreensTests: XCTestCase {
    func testAccountInitialsComeFromTheDisplayNameOnly() {
        XCTAssertEqual(SettingsView.initials("Shawn George"), "SG")
        XCTAssertEqual(SettingsView.initials("ada"), "A")
        XCTAssertEqual(SettingsView.initials("Mary Ann Smith"), "MA")
        XCTAssertNil(SettingsView.initials("   "))
        XCTAssertNil(SettingsView.initials(nil))
    }

    /// Both destructive actions only raise a confirmation; the work runs from
    /// the dialog's destructive button.
    func testDestructiveSettingsStayBehindConfirmations() throws {
        let source = try viewSource("SettingsView.swift")
        XCTAssertEqual(source.components(separatedBy: ".confirmationDialog(").count - 1, 2)
        XCTAssertEqual(source.components(separatedBy: "await deleteAccount()").count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: "settings.clearLocalSettings()").count - 1, 2)
        let dialog = try XCTUnwrap(source.range(of: "isPresented: $showDeleteAccountConfirm"))
        let call = try XCTUnwrap(source.range(of: "await deleteAccount()"))
        XCTAssertLessThan(dialog.lowerBound, call.lowerBound, "Account deletion must run from its confirmation")
    }

    /// Questions are asked about the frozen snapshot day, and the answer is
    /// labelled as AI output.
    func testAskUsesTheFrozenSnapshotAndLabelsTheAnswer() throws {
        let source = try viewSource("AskCoachView.swift")
        XCTAssertTrue(source.contains("client.ask(question: text, date: context.date)"))
        XCTAssertTrue(source.contains("AI-generated"))
        XCTAssertTrue(source.contains("answerDecision ?? context.decision"))
    }

    func testPillarSheetKeepsTheTodayCallSiteAPI() {
        let info = PillarInfo(name: "Sleep", weight: "35%", description: Pillar.sleep.summary,
                              pillar: PillarScore(score: 72, drivers: [Driver(text: "7h 40m asleep", detail: nil)]))
        XCTAssertEqual(info.name, "Sleep")
        XCTAssertEqual(info.pillar.drivers.count, 1)
        _ = PillarDetailSheet(info: info)
    }

    private func viewSource(_ file: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ReadinessCoach/Views/\(file)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
