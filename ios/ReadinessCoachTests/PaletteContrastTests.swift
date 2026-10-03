import XCTest
import SwiftUI
import UIKit
@testable import ReadinessCoach

final class PaletteContrastTests: XCTestCase {
    private func luminance(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a))
        let linear = [r, g, b].map { value -> Double in
            let component = Double(value)
            return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }

    private func contrast(_ first: Color, _ second: Color) -> Double {
        let values = [luminance(first), luminance(second)].sorted()
        return (values[1] + 0.05) / (values[0] + 0.05)
    }

    func testTextMeetsAAOnEveryDarkSurface() {
        for surface in [Palette.canvas, Palette.surface, Palette.surfaceHi] {
            for text in [Palette.textPrimary, Palette.textSecondary, Palette.textTertiary] {
                XCTAssertGreaterThanOrEqual(contrast(text, surface), 4.5)
            }
        }
    }

    func testProminentActionLabelHasContrast() {
        XCTAssertGreaterThanOrEqual(contrast(Palette.canvas, Palette.accent), 4.5)
    }

    func testPillarMarksHaveContrastAgainstSurface() {
        for pillar in Pillar.allCases {
            XCTAssertGreaterThanOrEqual(contrast(pillar.color, Palette.surface), 3)
        }
    }

    func testSleepPillTextHasAAContrastAgainstItsTintedFill() {
        // .sleep fill is 14% of the mark hue over Palette.surface.
        let fill = Color(hex: 0x262637)
        XCTAssertGreaterThanOrEqual(contrast(Pill("Sleep", tone: .sleep).textColor, fill), 4.5)
    }

    func testPillarNavigationMatchesItsDestination() {
        XCTAssertEqual(AppTab(.recovery), .recovery)
        XCTAssertEqual(AppTab(.sleep), .sleep)
        XCTAssertEqual(AppTab(.load), .train)
    }
}
