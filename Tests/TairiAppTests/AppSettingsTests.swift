import XCTest

@testable import TairiApp

@MainActor
final class AppSettingsTests: XCTestCase {
    func testAnimationsEnabledDefaultsToTrue() {
        let userDefaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: userDefaults)

        XCTAssertTrue(settings.animationsEnabled)
    }

    func testAnimationsEnabledPersists() {
        let userDefaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: userDefaults)

        settings.animationsEnabled = false

        let reloadedSettings = AppSettings(userDefaults: userDefaults)
        XCTAssertFalse(reloadedSettings.animationsEnabled)
    }

    func testAnimationSpeedMultiplierDefaultsToOne() {
        let userDefaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: userDefaults)

        XCTAssertEqual(settings.animationSpeedMultiplier, 1)
    }

    func testAnimationSpeedMultiplierPersists() {
        let userDefaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: userDefaults)

        settings.animationSpeedMultiplier = 1.5

        let reloadedSettings = AppSettings(userDefaults: userDefaults)
        XCTAssertEqual(reloadedSettings.animationSpeedMultiplier, 1.5)
    }

    func testDefaultTerminalExitBehaviorClosesImmediately() {
        let userDefaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: userDefaults)

        XCTAssertEqual(settings.terminalExitBehavior, .closeImmediately)
    }

    func testTerminalExitBehaviorPersists() {
        let userDefaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: userDefaults)

        settings.terminalExitBehavior = .closeImmediately

        let reloadedSettings = AppSettings(userDefaults: userDefaults)
        XCTAssertEqual(reloadedSettings.terminalExitBehavior, .closeImmediately)
    }

    func testDefaultWindowGlassOpacityIsDisabled() {
        let userDefaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: userDefaults)

        XCTAssertEqual(settings.windowGlassOpacityPercent, 0)
    }

    func testWindowGlassOpacityPersists() {
        let userDefaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: userDefaults)

        settings.windowGlassOpacityPercent = 82

        let reloadedSettings = AppSettings(userDefaults: userDefaults)
        XCTAssertEqual(reloadedSettings.windowGlassOpacityPercent, 82)
    }

    func testLegacyTileOpacityValueMigratesToWindowGlassOpacity() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(61, forKey: AppSettings.legacyTileBackgroundOpacityPercentKey)

        let settings = AppSettings(userDefaults: userDefaults)

        XCTAssertEqual(settings.windowGlassOpacityPercent, 61)
    }

    func testLegacyWindowOpacityValueMigratesToWindowGlassOpacity() {
        let userDefaults = makeUserDefaults()
        userDefaults.set(74, forKey: AppSettings.legacyWindowOpacityPercentKey)

        let settings = AppSettings(userDefaults: userDefaults)

        XCTAssertEqual(settings.windowGlassOpacityPercent, 74)
    }

    func testSidebarHiddenDefaultsToVisible() {
        let userDefaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: userDefaults)

        XCTAssertFalse(settings.sidebarHidden)
    }

    func testSidebarHiddenPersists() {
        let userDefaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: userDefaults)

        settings.sidebarHidden = true

        let reloadedSettings = AppSettings(userDefaults: userDefaults)
        XCTAssertTrue(reloadedSettings.sidebarHidden)
    }

    func testAnimationPolicyDisablesAnimationsWhenAppToggleIsOff() {
        let userDefaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: userDefaults)

        settings.animationsEnabled = false

        XCTAssertFalse(settings.animationPolicy.effectiveAnimationsEnabled)
    }

    func testAnimationPolicyDisablesAnimationsWhenSystemReduceMotionIsEnabled() {
        let userDefaults = makeUserDefaults()
        let settings = AppSettings(
            userDefaults: userDefaults,
            reduceMotionProvider: { true }
        )

        XCTAssertTrue(settings.systemReduceMotionEnabled)
        XCTAssertFalse(settings.animationPolicy.effectiveAnimationsEnabled)
    }

    func testSystemReduceMotionRefreshesFromNotification() {
        let userDefaults = makeUserDefaults()
        let notificationCenter = NotificationCenter()
        var systemReduceMotionEnabled = false
        let settings = AppSettings(
            userDefaults: userDefaults,
            reduceMotionProvider: { systemReduceMotionEnabled },
            notificationCenter: notificationCenter
        )

        XCTAssertFalse(settings.systemReduceMotionEnabled)

        systemReduceMotionEnabled = true
        notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertTrue(settings.systemReduceMotionEnabled)
        XCTAssertFalse(settings.animationPolicy.effectiveAnimationsEnabled)
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "tairi.tests.app-settings.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
