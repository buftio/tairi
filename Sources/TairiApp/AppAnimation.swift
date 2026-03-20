import Foundation
import SwiftUI

enum TairiAnimationCurve {
    case easeInOut
    case easeOut
}

struct AppAnimationPolicy: Equatable {
    static let defaultValue = AppAnimationPolicy(
        animationsEnabled: true,
        speedMultiplier: 1,
        systemReduceMotionEnabled: false,
        uiTesting: false
    )

    let animationsEnabled: Bool
    let speedMultiplier: Double
    let systemReduceMotionEnabled: Bool
    let uiTesting: Bool

    var effectiveAnimationsEnabled: Bool {
        animationsEnabled && !systemReduceMotionEnabled && !uiTesting
    }

    func shouldAnimate(_ requested: Bool = true) -> Bool {
        requested && effectiveAnimationsEnabled
    }

    func scaledDuration(_ baseDuration: TimeInterval, requested: Bool = true) -> TimeInterval {
        guard shouldAnimate(requested) else { return 0 }
        return baseDuration / max(speedMultiplier, 0.01)
    }

    func swiftUIAnimation(
        _ curve: TairiAnimationCurve,
        duration baseDuration: TimeInterval,
        requested: Bool = true
    ) -> Animation? {
        guard shouldAnimate(requested) else { return nil }

        let duration = scaledDuration(baseDuration, requested: requested)
        switch curve {
        case .easeInOut:
            return .easeInOut(duration: duration)
        case .easeOut:
            return .easeOut(duration: duration)
        }
    }
}
