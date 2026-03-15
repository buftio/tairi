import XCTest
@testable import TairiApp

@MainActor
final class AppSettingsTests: XCTestCase {
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

    func testDefaultWindowGlassOpacityIsFullyEnabled() {
        let userDefaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: userDefaults)

        XCTAssertEqual(settings.windowGlassOpacityPercent, 100)
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

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "tairi.tests.app-settings.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
