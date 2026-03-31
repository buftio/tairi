import AppKit
import XCTest

@testable import TairiApp

final class TileScrollGestureLockTests: XCTestCase {
    func testTinyDiagonalMovementDoesNotLatch() {
        var lock = TileScrollGestureLock()

        let decision = lock.routingDecision(
            for: sample(deltaX: 3, deltaY: 3, phase: .began),
            now: date(0)
        )

        XCTAssertEqual(decision, .interceptForWorkspaceHorizontalPan)
        XCTAssertEqual(lock.axisLock, .undecided)
    }

    func testClearVerticalMovementLatchesVertical() {
        var lock = TileScrollGestureLock()

        let decision = lock.routingDecision(
            for: sample(deltaX: 1, deltaY: 6, phase: .began),
            now: date(0)
        )

        XCTAssertEqual(decision, .forwardToTile)
        XCTAssertEqual(lock.axisLock, .vertical)
    }

    func testVerticalLockSuppressesLaterHorizontalPanUntilGestureEnds() {
        var lock = TileScrollGestureLock()

        _ = lock.routingDecision(
            for: sample(deltaX: 1, deltaY: 6, phase: .began),
            now: date(0)
        )

        let decision = lock.routingDecision(
            for: sample(deltaX: 10, deltaY: 1, phase: .changed),
            now: date(0.05)
        )

        XCTAssertEqual(decision, .forwardToTile)
        XCTAssertEqual(lock.axisLock, .vertical)
    }

    func testHorizontalFirstGestureKeepsHorizontalPanBehavior() {
        var lock = TileScrollGestureLock()

        let decision = lock.routingDecision(
            for: sample(deltaX: 8, deltaY: 2, phase: .began),
            now: date(0)
        )

        XCTAssertEqual(decision, .interceptForWorkspaceHorizontalPan)
        XCTAssertEqual(lock.axisLock, .horizontal)
    }

    func testGestureResetOnEndAllowsNextTouchToChooseNewAxis() {
        var lock = TileScrollGestureLock()

        _ = lock.routingDecision(
            for: sample(deltaX: 8, deltaY: 2, phase: .began),
            now: date(0)
        )

        let endedDecision = lock.routingDecision(
            for: sample(deltaX: 4, deltaY: 1, phase: .ended),
            now: date(0.05)
        )

        let nextDecision = lock.routingDecision(
            for: sample(deltaX: 1, deltaY: 7, phase: .began),
            now: date(0.10)
        )

        XCTAssertEqual(endedDecision, .interceptForWorkspaceHorizontalPan)
        XCTAssertEqual(nextDecision, .forwardToTile)
        XCTAssertEqual(lock.axisLock, .vertical)
    }

    func testIdleTimeoutResetsGestureBeforeNextTouch() {
        var lock = TileScrollGestureLock()

        _ = lock.routingDecision(
            for: sample(deltaX: 8, deltaY: 2, phase: .began),
            now: date(0)
        )

        let decision = lock.routingDecision(
            for: sample(deltaX: 1, deltaY: 7, phase: []),
            now: date(TileScrollGestureLock.idleTimeout + 0.01)
        )

        XCTAssertEqual(decision, .forwardToTile)
        XCTAssertEqual(lock.axisLock, .vertical)
    }

    private func sample(
        deltaX: CGFloat,
        deltaY: CGFloat,
        hasPreciseScrollingDeltas: Bool = true,
        phase: NSEvent.Phase = [],
        momentumPhase: NSEvent.Phase = []
    ) -> TileScrollGestureLock.Sample {
        TileScrollGestureLock.Sample(
            deltaX: deltaX,
            deltaY: deltaY,
            hasPreciseScrollingDeltas: hasPreciseScrollingDeltas,
            phase: phase,
            momentumPhase: momentumPhase
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }
}
