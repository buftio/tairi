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

    func testScrollEventForwardsWhenTileIsAlreadySelected() {
        let tileID = UUID()

        XCTAssertTrue(
            GhosttySurfaceMouseInputPolicy.shouldForwardScrollEvent(
                tileID: tileID,
                selectedTileID: tileID
            )
        )
    }

    func testScrollEventIsSuppressedWhenTileIsNotSelected() {
        XCTAssertFalse(
            GhosttySurfaceMouseInputPolicy.shouldForwardScrollEvent(
                tileID: UUID(),
                selectedTileID: UUID()
            )
        )
    }

    func testScrollEventIsSuppressedWithoutTile() {
        XCTAssertFalse(
            GhosttySurfaceMouseInputPolicy.shouldForwardScrollEvent(
                tileID: nil,
                selectedTileID: UUID()
            )
        )
    }

    @MainActor
    func testReorderTileIDPrefersSelectedTileOverAttachedSurface() {
        let attachedTileID = UUID()
        let selectedTileID = UUID()

        XCTAssertEqual(
            GhosttySurfaceView.reorderTileID(
                attachedTileID: attachedTileID,
                selectedTileID: selectedTileID
            ),
            selectedTileID
        )
    }

    @MainActor
    func testReorderTileIDFallsBackToAttachedSurfaceWhenSelectionMissing() {
        let attachedTileID = UUID()

        XCTAssertEqual(
            GhosttySurfaceView.reorderTileID(
                attachedTileID: attachedTileID,
                selectedTileID: nil
            ),
            attachedTileID
        )
    }
}
