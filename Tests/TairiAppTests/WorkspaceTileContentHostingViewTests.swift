import SwiftUI
import XCTest

@testable import TairiApp

@MainActor
final class WorkspaceTileContentHostingViewTests: XCTestCase {
    func testHorizontalScrollWheelIsConsumedWhenDominant() {
        XCTAssertTrue(
            WorkspaceTileContentHostingView<EmptyView>.shouldConsumeHorizontalScrollWheel(
                deltaX: 8,
                deltaY: 2
            )
        )
    }

    func testVerticalScrollWheelIsForwardedWhenDominant() {
        XCTAssertFalse(
            WorkspaceTileContentHostingView<EmptyView>.shouldConsumeHorizontalScrollWheel(
                deltaX: 2,
                deltaY: 8
            )
        )
    }

    func testVerticalOnlyScrollWheelIsForwarded() {
        XCTAssertFalse(
            WorkspaceTileContentHostingView<EmptyView>.shouldConsumeHorizontalScrollWheel(
                deltaX: 0,
                deltaY: 8
            )
        )
    }
}
