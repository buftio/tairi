import AppKit
import Foundation
import XCTest

private enum Identifiers {
    static let appRoot = "app-root"
    static let workspaceSidebar = "workspace-sidebar"
    static let workspaceList = "workspace-list"
    static let workspaceTitle = "workspace-title"
    static let workspaceCanvas = "workspace-canvas"
    static let widthPicker = "tile-width-picker"
    static let newTileButton = "new-tile-button"
    static let nextWorkspaceButton = "next-workspace-button"
    static let tileSpotlight = "tile-spotlight"
    static let tileSpotlightSearchField = "tile-spotlight-search-field"

    static func workspaceButton(_ title: String) -> String {
        "workspace-button-\(title)"
    }
}

@MainActor
final class TairiUITests: XCTestCase {
    private let bundleIdentifier = "org.tairi.app"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWorkspaceSmokeFlow() throws {
        let app = try launchApp()
        defer { app.terminate() }

        XCTAssertTrue(app.otherElements[Identifiers.appRoot].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts[Identifiers.workspaceTitle].label, "Workspace 01")
        XCTAssertTrue(app.buttons[Identifiers.workspaceButton("01")].exists)
        XCTAssertTrue(app.buttons[Identifiers.workspaceButton("02")].exists)

        app.buttons[Identifiers.newTileButton].click()
        XCTAssertEqual(tileQuery(in: app).count, 2)

        app.buttons[Identifiers.workspaceButton("02")].click()
        XCTAssertEqual(app.staticTexts[Identifiers.workspaceTitle].label, "Workspace 02")

        app.buttons[Identifiers.newTileButton].click()
        XCTAssertTrue(app.segmentedControls[Identifiers.widthPicker].waitForExistence(timeout: 5))
        app.segmentedControls[Identifiers.widthPicker].buttons["Wide"].click()
    }

    func testWorkspaceSidebarRowIsClickableAcrossItsFullWidth() throws {
        let app = try launchApp()
        defer { app.terminate() }

        let workspaceButton = app.buttons[Identifiers.workspaceButton("02")]
        XCTAssertTrue(workspaceButton.waitForExistence(timeout: 10))

        workspaceButton.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)).click()

        XCTAssertEqual(app.staticTexts[Identifiers.workspaceTitle].label, "Workspace 02")
    }

    func testSidebarKeepsSelectedWorkspaceVisibleWhenListOverflows() throws {
        let app = try launchApp()
        defer { app.terminate() }

        XCTAssertTrue(app.otherElements[Identifiers.workspaceList].waitForExistence(timeout: 10))

        for workspaceNumber in 2...15 {
            app.buttons[Identifiers.nextWorkspaceButton].click()
            XCTAssertEqual(
                app.staticTexts[Identifiers.workspaceTitle].label,
                "Workspace \(String(format: "%02d", workspaceNumber))"
            )
            app.buttons[Identifiers.newTileButton].click()
        }

        app.buttons[Identifiers.nextWorkspaceButton].click()

        let lastWorkspaceButton = app.buttons[Identifiers.workspaceButton("16")]
        XCTAssertTrue(lastWorkspaceButton.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts[Identifiers.workspaceTitle].label, "Workspace 16")
        XCTAssertTrue(lastWorkspaceButton.isHittable)
    }

    func testInitialTileStartsImmediatelyAfterSidebar() throws {
        let app = try launchApp()
        defer { app.terminate() }

        let sidebar = app.otherElements[Identifiers.workspaceSidebar]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10))

        let firstTile = tileQuery(in: app).element(boundBy: 0)
        XCTAssertTrue(firstTile.waitForExistence(timeout: 10))

        let tileGap = firstTile.frame.minX - sidebar.frame.maxX
        XCTAssertGreaterThanOrEqual(tileGap, 0)
        XCTAssertLessThanOrEqual(tileGap, 24)
    }

    func testSingleTileStripShowsResizeHandleAndCanGrowWidth() throws {
        let app = try launchApp()
        defer { app.terminate() }

        let firstTile = tileQuery(in: app).element(boundBy: 0)
        XCTAssertTrue(firstTile.waitForExistence(timeout: 10))

        let resizeHandle = tileResizeHandleQuery(in: app).element(boundBy: 0)
        XCTAssertTrue(resizeHandle.waitForExistence(timeout: 5))
        XCTAssertTrue(resizeHandle.isHittable)

        let startingWidth = firstTile.frame.width
        let dragStart = resizeHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let dragEnd = dragStart.withOffset(CGVector(dx: 120, dy: 0))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)

        XCTAssertTrue(waitForFrameWidth(of: firstTile, toBeGreaterThan: startingWidth + 24))
    }

    func testZoomOutOverviewAndClickZoomIn() throws {
        let app = try launchApp()
        defer { app.terminate() }

        XCTAssertTrue(app.buttons[Identifiers.newTileButton].waitForExistence(timeout: 10))
        app.buttons[Identifiers.newTileButton].click()
        XCTAssertEqual(tileQuery(in: app).count, 2)

        let canvas = app.otherElements[Identifiers.workspaceCanvas]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let firstTile = tileQuery(in: app).element(boundBy: 0)
        let secondTile = tileQuery(in: app).element(boundBy: 1)
        XCTAssertTrue(firstTile.waitForExistence(timeout: 5))
        XCTAssertTrue(secondTile.waitForExistence(timeout: 5))

        let focusedWidth = secondTile.frame.width

        app.typeKey("-", modifierFlags: [.command, .option])
        XCTAssertTrue(waitForValue(of: canvas, toEqual: "overview"))
        XCTAssertTrue(waitForFrameWidth(of: secondTile, toBeLessThan: focusedWidth * 0.8))

        firstTile.click()
        XCTAssertTrue(waitForValue(of: canvas, toEqual: "focused"))
        XCTAssertTrue(waitForFrameWidth(of: firstTile, toBeGreaterThan: focusedWidth * 0.9))
    }

    func testCommandKOpensTileSpotlightAndShowsMatches() throws {
        let app = try launchApp()
        defer { app.terminate() }

        XCTAssertTrue(app.otherElements[Identifiers.appRoot].waitForExistence(timeout: 10))

        app.typeKey("k", modifierFlags: [.command])

        let spotlight = app.otherElements[Identifiers.tileSpotlight]
        XCTAssertTrue(spotlight.waitForExistence(timeout: 5))

        let searchField = app.textFields[Identifiers.tileSpotlightSearchField]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.click()
        searchField.typeText("shell")

        let results = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tile-spotlight-result-"))
        XCTAssertGreaterThan(results.count, 0)
    }

    private func launchApp() throws -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        app.terminate()

        let appBundleURL = try resolvedAppBundleURL()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = false
        configuration.environment = [
            "TAIRI_UI_TEST": "1",
        ]

        let launched = expectation(description: "Launch app bundle")
        var launchError: Error?
        NSWorkspace.shared.openApplication(at: appBundleURL, configuration: configuration) { _, error in
            launchError = error
            launched.fulfill()
        }
        wait(for: [launched], timeout: 15)
        if let launchError {
            throw launchError
        }

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        return app
    }

    private func resolvedAppBundleURL() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["TAIRI_APP_BUNDLE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot.appendingPathComponent("dist/tairi.app")
    }

    private func tileQuery(in app: XCUIApplication) -> XCUIElementQuery {
        app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workspace-tile-"))
    }

    private func tileResizeHandleQuery(in app: XCUIApplication) -> XCUIElementQuery {
        app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workspace-tile-resize-handle-"))
    }

    private func waitForFrameWidth(
        of element: XCUIElement,
        toBeLessThan threshold: CGFloat,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate { _, _ in
            element.frame.width < threshold
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForFrameWidth(
        of element: XCUIElement,
        toBeGreaterThan threshold: CGFloat,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate { _, _ in
            element.frame.width > threshold
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForValue(
        of element: XCUIElement,
        toEqual expectedValue: String,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate { _, _ in
            element.value as? String == expectedValue
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
