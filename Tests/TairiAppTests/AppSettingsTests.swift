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
    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "tairi.tests.app-settings.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
