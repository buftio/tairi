import XCTest

@testable import TairiApp

@MainActor
final class WindowChromeControllerTests: XCTestCase {
    func testToggleSidebarUpdatesRenderedInsetWhenAnimationsAreDisabled() {
        let userDefaults = makeUserDefaults()
        let settings = AppSettings(userDefaults: userDefaults)
        settings.animationsEnabled = false
        settings.sidebarHidden = false
        let controller = WindowChromeController(settings: settings)

        controller.toggleSidebarVisibility()

        XCTAssertTrue(controller.isSidebarHidden)
        XCTAssertTrue(settings.sidebarHidden)
        XCTAssertEqual(
            controller.renderedStripLeadingInset,
            WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: true),
            accuracy: 0.001
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "tairi.tests.window-chrome-controller.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}
