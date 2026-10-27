import CoreGraphics
import XCTest
@testable import Keyring

final class UnfoldedSplitTests: XCTestCase {
    func testCompactWidthKeepsOneColumn() {
        XCTAssertNil(UnfoldedSplit.make(width: 951, isRegularWidth: false, fold: 470...481))
    }

    func testFoldedOuterDisplayKeepsOneColumn() {
        XCTAssertNil(UnfoldedSplit.make(width: 466, isRegularWidth: true, fold: nil))
    }

    func testUnfoldedPortraitIsTooNarrowForTwoPanes() {
        XCTAssertNil(UnfoldedSplit.make(width: 669, isRegularWidth: true, fold: nil))
    }

    func testPanesMeetTheFoldEdges() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 470...481)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 470, secondaryX: 481, secondaryWidth: 470))
    }

    func testNoReportedFoldSplitsEvenly() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: nil)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 475, secondaryX: 475, secondaryWidth: 476))
    }

    func testFoldTooCloseToAnEdgeSplitsEvenly() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 300...310)
        XCTAssertEqual(split?.primaryWidth, 475)
        XCTAssertEqual(split?.secondaryX, 475)
    }

    func testEveryPaneIsAtLeastTheMinimumWidth() {
        for width in stride(from: CGFloat(720), through: 1_400, by: 7) {
            let split = UnfoldedSplit.make(width: width, isRegularWidth: true, fold: nil)
            XCTAssertNotNil(split)
            XCTAssertGreaterThanOrEqual(split!.primaryWidth, UnfoldedSplit.minimumPaneWidth)
            XCTAssertGreaterThanOrEqual(split!.secondaryWidth, UnfoldedSplit.minimumPaneWidth)
            XCTAssertEqual(split!.secondaryX + split!.secondaryWidth, width)
        }
    }

    @MainActor
    func testEmptyGarageHasNoPaneVehicle() {
        let pane = VehiclePane()
        XCTAssertNil(pane.vehicle(in: []))
    }
}
