import XCTest
@testable import ReadinessCoach

final class DurationFormatTests: XCTestCase {
    func testShort() {
        XCTAssertEqual(DurationFormat.short(7.9), "7h 54m")
        XCTAssertEqual(DurationFormat.short(0.75), "45m")
        XCTAssertEqual(DurationFormat.short(8), "8h")
        XCTAssertEqual(DurationFormat.short(-1), "0m")
    }

    func testLong() {
        XCTAssertEqual(DurationFormat.long(7.9), "7 hr 54 min")
        XCTAssertEqual(DurationFormat.long(0.75), "45 min")
        XCTAssertEqual(DurationFormat.long(1), "1 hour")
        XCTAssertEqual(DurationFormat.long(2), "2 hours")
    }

    func testPillarWeightsSumToOneHundred() {
        XCTAssertEqual(Pillar.allCases.map(\.weightPercent).reduce(0, +), 100)
    }
}
