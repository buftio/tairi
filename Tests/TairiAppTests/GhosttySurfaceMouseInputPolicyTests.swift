import XCTest

@testable import TairiApp

final class GhosttySurfaceMouseInputPolicyTests: XCTestCase {
    func testInitialMouseEventForwardsWhenClickedTileIsAlreadySelected() {
        let tileID = UUID()

        XCTAssertTrue(
            GhosttySurfaceMouseInputPolicy.shouldForwardInitialMouseEvent(
                clickedTileID: tileID,
                selectedTileID: tileID
            )
        )
    }

    func testInitialMouseEventIsSuppressedWhenClickedTileIsNotSelected() {
        XCTAssertFalse(
            GhosttySurfaceMouseInputPolicy.shouldForwardInitialMouseEvent(
                clickedTileID: UUID(),
                selectedTileID: UUID()
            )
        )
    }

    func testInitialMouseEventIsSuppressedWithoutClickedTile() {
        XCTAssertFalse(
            GhosttySurfaceMouseInputPolicy.shouldForwardInitialMouseEvent(
                clickedTileID: nil,
                selectedTileID: UUID()
            )
        )
    }

    func testPointerMotionIsSuppressedWhileCanvasIsAnimating() {
        XCTAssertFalse(
            GhosttySurfaceMouseInputPolicy.shouldForwardPointerMotion(isCanvasAnimating: true)
        )
    }

    func testPointerMotionForwardsWhenCanvasIsStable() {
        XCTAssertTrue(
            GhosttySurfaceMouseInputPolicy.shouldForwardPointerMotion(isCanvasAnimating: false)
        )
    }
}
