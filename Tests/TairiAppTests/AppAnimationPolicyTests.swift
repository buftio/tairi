import XCTest

@testable import TairiApp

final class AppAnimationPolicyTests: XCTestCase {
    func testScaledDurationRespectsSpeedMultiplier() {
        XCTAssertEqual(makePolicy(speedMultiplier: 0.5).scaledDuration(0.2), 0.4, accuracy: 0.0001)
        XCTAssertEqual(makePolicy(speedMultiplier: 1).scaledDuration(0.2), 0.2, accuracy: 0.0001)
        XCTAssertEqual(makePolicy(speedMultiplier: 2).scaledDuration(0.2), 0.1, accuracy: 0.0001)
    }

    func testScaledDurationIsZeroWhenAnimationsDisabled() {
        XCTAssertEqual(makePolicy(animationsEnabled: false).scaledDuration(0.2), 0)
    }

    func testScaledDurationIsZeroDuringUITesting() {
        XCTAssertEqual(makePolicy(uiTesting: true).scaledDuration(0.2), 0)
    }

    private func makePolicy(
        animationsEnabled: Bool = true,
        speedMultiplier: Double = 1,
        systemReduceMotionEnabled: Bool = false,
        uiTesting: Bool = false
    ) -> AppAnimationPolicy {
        AppAnimationPolicy(
            animationsEnabled: animationsEnabled,
            speedMultiplier: speedMultiplier,
            systemReduceMotionEnabled: systemReduceMotionEnabled,
            uiTesting: uiTesting
        )
    }
}
