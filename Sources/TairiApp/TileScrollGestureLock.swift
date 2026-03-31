import AppKit

struct TileScrollGestureLock {
    enum AxisLock: Equatable {
        case undecided
        case vertical
        case horizontal
    }

    enum RoutingDecision: Equatable {
        case forwardToTile
        case interceptForWorkspaceHorizontalPan
    }

    struct Sample {
        let deltaX: CGFloat
        let deltaY: CGFloat
        let hasPreciseScrollingDeltas: Bool
        let phase: NSEvent.Phase
        let momentumPhase: NSEvent.Phase
    }

    static let clearAxisThreshold: CGFloat = 4
    static let idleTimeout: TimeInterval = 0.25

    private(set) var axisLock: AxisLock = .undecided
    private(set) var lastEventAt = Date.distantPast

    mutating func routingDecision(for sample: Sample, now: Date = Date()) -> RoutingDecision {
        if !sample.hasPreciseScrollingDeltas {
            reset()
            return Self.isHorizontallyDominant(deltaX: sample.deltaX, deltaY: sample.deltaY)
                ? .interceptForWorkspaceHorizontalPan
                : .forwardToTile
        }

        resetIfNeeded(for: sample, now: now)

        if axisLock == .undecided, let latchedAxis = Self.clearDominantAxis(for: sample) {
            axisLock = latchedAxis
        }

        let decision: RoutingDecision
        switch axisLock {
        case .horizontal:
            decision = abs(sample.deltaX) > 0 ? .interceptForWorkspaceHorizontalPan : .forwardToTile
        case .vertical:
            decision = .forwardToTile
        case .undecided:
            decision =
                Self.isHorizontallyDominant(deltaX: sample.deltaX, deltaY: sample.deltaY)
                ? .interceptForWorkspaceHorizontalPan
                : .forwardToTile
        }

        lastEventAt = now

        if Self.isGestureEnding(sample) {
            reset()
        }

        return decision
    }

    mutating func reset() {
        axisLock = .undecided
        lastEventAt = Date.distantPast
    }

    static func clearDominantAxis(for sample: Sample) -> AxisLock? {
        guard sample.hasPreciseScrollingDeltas else { return nil }

        let horizontalDelta = abs(sample.deltaX)
        let verticalDelta = abs(sample.deltaY)
        let dominantDelta = max(horizontalDelta, verticalDelta)

        guard dominantDelta >= clearAxisThreshold else { return nil }
        guard horizontalDelta != verticalDelta else { return nil }

        return horizontalDelta > verticalDelta ? .horizontal : .vertical
    }

    static func isHorizontallyDominant(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        let horizontalDelta = abs(deltaX)
        guard horizontalDelta > 0 else { return false }
        return horizontalDelta >= abs(deltaY)
    }

    static func isVerticallyDominant(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        let verticalDelta = abs(deltaY)
        guard verticalDelta > 0 else { return false }
        return verticalDelta > abs(deltaX)
    }

    private mutating func resetIfNeeded(for sample: Sample, now: Date) {
        let phaseBegan = sample.phase.contains(.began) || sample.phase.contains(.mayBegin)
        let timedOut = now.timeIntervalSince(lastEventAt) > Self.idleTimeout
        if phaseBegan || timedOut {
            reset()
        }
    }

    private static func isGestureEnding(_ sample: Sample) -> Bool {
        sample.phase.contains(.ended)
            || sample.phase.contains(.cancelled)
            || sample.momentumPhase.contains(.ended)
    }
}
