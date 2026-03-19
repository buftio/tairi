import XCTest
import GhosttyDyn
@testable import TairiApp

final class GhosttyActionAdapterTests: XCTestCase {
    func testNewSplitRightCreatesSiblingTile() {
        let adapter = GhosttyActionAdapter()
        let sessionID = UUID()
        let action = ghostty_action_s(
            tag: GHOSTTY_ACTION_NEW_SPLIT,
            action: ghostty_action_u(new_split: GHOSTTY_SPLIT_DIRECTION_RIGHT)
        )

        let event = adapter.decode(action: action, sessionID: sessionID)

        guard case .createTile(let nextToSessionID) = event else {
            return XCTFail("expected createTile, got \(event)")
        }
        XCTAssertEqual(nextToSessionID, sessionID)
    }

    func testNewSplitDownIsIgnoredToAvoidRecursiveSplitLoop() {
        let adapter = GhosttyActionAdapter()
        let sessionID = UUID()
        let action = ghostty_action_s(
            tag: GHOSTTY_ACTION_NEW_SPLIT,
            action: ghostty_action_u(new_split: GHOSTTY_SPLIT_DIRECTION_DOWN)
        )

        let event = adapter.decode(action: action, sessionID: sessionID)

        guard case .ignore = event else {
            return XCTFail("expected ignore, got \(event)")
        }
    }

    func testGotoSplitIsIgnoredByActionAdapter() {
        let adapter = GhosttyActionAdapter()
        let sessionID = UUID()
        let action = ghostty_action_s(
            tag: GHOSTTY_ACTION_GOTO_SPLIT,
            action: ghostty_action_u(goto_split: GHOSTTY_GOTO_SPLIT_NEXT)
        )

        let event = adapter.decode(action: action, sessionID: sessionID)

        guard case .ignore = event else {
            return XCTFail("expected ignore, got \(event)")
        }
    }
}
