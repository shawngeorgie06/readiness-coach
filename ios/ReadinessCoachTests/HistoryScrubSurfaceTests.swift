import XCTest
import UIKit
import UIKit.UIGestureRecognizerSubclass
@testable import ReadinessCoach

/// The History charts' touch surface: taps, holds and sideways drags pick a day,
/// and a vertical drag is left to the page's scroll view.
@MainActor
final class HistoryScrubSurfaceTests: XCTestCase {
    private var selected: [CGFloat] = []
    private var tapped: [CGFloat] = []
    private var scroll: UIScrollView!
    private var view: UIView!

    override func setUp() async throws {
        selected = []
        tapped = []
        scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        view = UIView(frame: CGRect(x: 0, y: 40, width: 320, height: 160))
        scroll.addSubview(view)
    }

    private func surface(opensOnTap: Bool) -> HistoryScrubSurface.Coordinator {
        let coordinator = HistoryScrubSurface.Coordinator(
            onSelect: { [unowned self] in selected.append($0) },
            onTap: opensOnTap ? { [unowned self] in tapped.append($0) } : nil
        )
        coordinator.install(on: view)
        return coordinator
    }

    private func fire(_ recognizer: UIGestureRecognizer, _ state: UIGestureRecognizer.State, on coordinator: HistoryScrubSurface.Coordinator) {
        recognizer.state = state
        coordinator.handle(recognizer)
    }

    func testTapOpensTheDayWhenTheChartOpensDays() {
        let c = surface(opensOnTap: true)
        fire(c.tap, .ended, on: c)

        XCTAssertEqual(tapped.count, 1)
        XCTAssertTrue(selected.isEmpty, "the tap handler selects and opens in one step")
    }

    func testTapSelectsWhenTheChartDoesNotOpenDays() {
        let c = surface(opensOnTap: false)
        fire(c.tap, .ended, on: c)

        XCTAssertEqual(selected.count, 1)
        XCTAssertTrue(tapped.isEmpty)
    }

    func testHoldMarksItsDayOnceAndNeverOpens() {
        let c = surface(opensOnTap: true)
        fire(c.hold, .began, on: c)
        fire(c.hold, .changed, on: c)
        fire(c.hold, .ended, on: c)

        XCTAssertEqual(selected.count, 1)
        XCTAssertTrue(tapped.isEmpty)
    }

    func testSidewaysDragFollowsTheFingerAndNeverOpens() {
        let c = surface(opensOnTap: true)
        // Past the delegate's sideways check, which needs real touches.
        c.pan.delegate = nil
        fire(c.pan, .began, on: c)
        fire(c.pan, .changed, on: c)
        fire(c.pan, .changed, on: c)
        fire(c.pan, .ended, on: c)

        XCTAssertEqual(selected.count, 3)
        XCTAssertTrue(tapped.isEmpty)
    }

    /// UIKit asks the delegate before a pan begins; one that isn't sideways is
    /// refused and left to the page.
    func testAPanTheDelegateRefusesNeverScrubs() {
        let c = surface(opensOnTap: true)
        fire(c.pan, .began, on: c)

        XCTAssertNotEqual(c.pan.state, .began)
        XCTAssertTrue(selected.isEmpty)
        XCTAssertTrue(tapped.isEmpty)
    }

    func testCancelledOrFailedTouchesDoNothing() {
        let c = surface(opensOnTap: true)
        fire(c.pan, .cancelled, on: c)
        fire(c.hold, .failed, on: c)

        XCTAssertTrue(selected.isEmpty)
        XCTAssertTrue(tapped.isEmpty)
    }

    func testRecognizersAreInstalledOnTheSurface() {
        let c = surface(opensOnTap: true)
        let installed = view.gestureRecognizers ?? []

        XCTAssertTrue(installed.contains(c.tap))
        XCTAssertTrue(installed.contains(c.hold))
        XCTAssertTrue(installed.contains(c.pan))
        XCTAssertTrue(installed.allSatisfy { $0.delegate === c })
    }

    func testOnlyAMostlySidewaysMovementIsAScrub() {
        typealias C = HistoryScrubSurface.Coordinator
        XCTAssertTrue(C.isSideways(CGPoint(x: 12, y: 3)))
        XCTAssertTrue(C.isSideways(CGPoint(x: -12, y: 3)))
        XCTAssertFalse(C.isSideways(CGPoint(x: 3, y: 12)))
        XCTAssertFalse(C.isSideways(CGPoint(x: 3, y: -12)))
        XCTAssertFalse(C.isSideways(CGPoint(x: 5, y: 5)))
        XCTAssertFalse(C.isSideways(.zero))
    }

    func testTapAndHoldMayAlwaysBeginButAStillPanMayNot() {
        let c = surface(opensOnTap: true)

        XCTAssertTrue(c.gestureRecognizerShouldBegin(c.tap))
        XCTAssertTrue(c.gestureRecognizerShouldBegin(c.hold))
        XCTAssertFalse(c.gestureRecognizerShouldBegin(c.pan), "a pan at rest")
    }

    func testThePageScrollWaitsOnlyForTheScrub() {
        let c = surface(opensOnTap: true)
        let pagePan = scroll.panGestureRecognizer
        let otherPan = UIPanGestureRecognizer()
        UIView().addGestureRecognizer(otherPan)

        XCTAssertTrue(c.gestureRecognizer(c.pan, shouldBeRequiredToFailBy: pagePan))
        XCTAssertFalse(c.gestureRecognizer(c.tap, shouldBeRequiredToFailBy: pagePan))
        XCTAssertFalse(c.gestureRecognizer(c.hold, shouldBeRequiredToFailBy: pagePan))
        XCTAssertFalse(c.gestureRecognizer(c.pan, shouldBeRequiredToFailBy: otherPan))
    }

    func testOnlyTheHoldSharesTheTouch() {
        let c = surface(opensOnTap: true)
        let pagePan = scroll.panGestureRecognizer

        XCTAssertTrue(c.gestureRecognizer(c.hold, shouldRecognizeSimultaneouslyWith: pagePan))
        XCTAssertTrue(c.gestureRecognizer(pagePan, shouldRecognizeSimultaneouslyWith: c.hold))
        XCTAssertTrue(c.gestureRecognizer(c.pan, shouldRecognizeSimultaneouslyWith: c.hold))
        XCTAssertFalse(c.gestureRecognizer(c.pan, shouldRecognizeSimultaneouslyWith: pagePan))
        XCTAssertFalse(c.gestureRecognizer(c.tap, shouldRecognizeSimultaneouslyWith: c.pan))
    }
}
