import AppKit
import Foundation
import XCTest

private enum Identifiers {
    static let appRoot = "app-root"
    static let workspaceTitle = "workspace-title"
    static let workspaceButtonPrefix = "workspace-button-"
    static let workspaceRenameFieldPrefix = "workspace-rename-field-"
    static let workspaceTilePattern = "^workspace-tile-[0-9a-f-]{36}$"
    static let workspaceTileCloseButtonPattern = "^workspace-tile-close-button-[0-9a-f-]{36}$"
    static let workspaceTileResizeHandlePattern = "^workspace-tile-resize-handle-[0-9a-f-]{36}$"
    static let zoomOutOverviewButton = "zoom-out-overview-button"
    static let emptyWorkspaceState = "empty-workspace-state"
}

@MainActor
final class TairiUITests: XCTestCase {
    private nonisolated(unsafe) var userDefaultsSuiteNames: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        for suiteName in userDefaultsSuiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        userDefaultsSuiteNames = []
        try super.tearDownWithError()
    }

    func testWorkspaceSmokeFlow() throws {
        let app = try launchApp()
        defer { app.terminate() }

        XCTAssertTrue(element(in: app, identifiedBy: Identifiers.appRoot).waitForExistence(timeout: 10))
        XCTAssertTrue(selectedWorkspaceTitle(in: app).hasPrefix("Workspace "))
        XCTAssertGreaterThanOrEqual(workspaceButtons(in: app).count, 1)

        let initialTileCount = visibleTileElements(in: app).count
        XCTAssertGreaterThanOrEqual(initialTileCount, 1)
        createNewTile(in: app)
        XCTAssertTrue(waitForVisibleTileCount(in: app, atLeast: initialTileCount + 1))
    }

    func testSidebarKeepsSelectedWorkspaceVisibleWhenListOverflows() throws {
        let app = try launchApp()
        defer { app.terminate() }

        XCTAssertTrue(workspaceButton(in: app, at: 0).waitForExistence(timeout: 10))

        for workspaceNumber in 2...15 {
            selectNextWorkspace(in: app)
            assertSelectedWorkspaceTitle(in: app, equals: "Workspace New Strip \(workspaceNumber)")
            createNewTile(in: app)
        }

        selectNextWorkspace(in: app)

        let lastWorkspaceButton = workspaceButton(in: app, at: 15)
        XCTAssertTrue(lastWorkspaceButton.waitForExistence(timeout: 5))
        assertSelectedWorkspaceTitle(in: app, equals: "Workspace New Strip 16")
        XCTAssertTrue(lastWorkspaceButton.isHittable)
    }

    func testWorkspaceCanBeRenamedFromSidebar() throws {
        let app = try launchApp()
        defer { app.terminate() }

        let initialWorkspaceButton = workspaceButton(in: app, at: 0)
        XCTAssertTrue(initialWorkspaceButton.waitForExistence(timeout: 10))

        initialWorkspaceButton.doubleClick()

        let renameField = workspaceRenameField(in: app)
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.click()
        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        renameField.typeText("Inbox\n")

        assertSelectedWorkspaceTitle(in: app, equals: "Workspace Inbox")
    }

    func testSelectingEmptyWorkspaceShowsEmptyWorkspaceState() throws {
        let app = try launchApp()
        defer { app.terminate() }

        let emptyWorkspaceButton = workspaceButton(in: app, at: 1)
        XCTAssertTrue(emptyWorkspaceButton.waitForExistence(timeout: 10))

        emptyWorkspaceButton.click()

        XCTAssertTrue(emptyWorkspaceState(in: app).waitForExistence(timeout: 5))
        assertSelectedWorkspaceTitle(in: app, equals: "Workspace New Strip 2")
        XCTAssertTrue(element(in: app, identifiedBy: Identifiers.appRoot).exists)
    }

    func testClosingLastTileShowsEmptyWorkspaceState() throws {
        let app = try launchApp()
        defer { app.terminate() }

        let closeButton = tileCloseButtonQuery(in: app).element(boundBy: 0)
        XCTAssertTrue(closeButton.waitForExistence(timeout: 10))

        closeButton.click()

        XCTAssertTrue(emptyWorkspaceState(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(waitForVisibleTileCount(in: app, toEqual: 0))
        XCTAssertTrue(element(in: app, identifiedBy: Identifiers.appRoot).exists)
    }

    func testSingleTileStripHasInvisibleResizeHandleAndCanGrowWidth() throws {
        let app = try launchApp()
        defer { app.terminate() }

        let firstTile = tileQuery(in: app).element(boundBy: 0)
        XCTAssertTrue(firstTile.waitForExistence(timeout: 10))

        let resizeHandle = tileResizeHandleQuery(in: app).element(boundBy: 0)
        XCTAssertTrue(resizeHandle.waitForExistence(timeout: 5))
        XCTAssertTrue(resizeHandle.isHittable)
        XCTAssertGreaterThan(resizeHandle.frame.height, resizeHandle.frame.width)
        XCTAssertGreaterThan(resizeHandle.frame.height, firstTile.frame.height * 0.8)

        let startingWidth = firstTile.frame.width
        let dragStart = resizeHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let dragEnd = dragStart.withOffset(CGVector(dx: 120, dy: 0))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)

        XCTAssertTrue(
            waitForFrameWidth(
                of: { self.tileQuery(in: app).element(boundBy: 0) },
                toBeGreaterThan: startingWidth + 24
            )
        )
    }

    func testLaunchAppResetsPersistedWorkspaceState() throws {
        let suiteName = makeDefaultsSuiteName()
        let dirtyApp = try launchApp(defaultsSuiteName: suiteName)
        let initialWorkspaceButton = workspaceButton(in: dirtyApp, at: 0)
        XCTAssertTrue(initialWorkspaceButton.waitForExistence(timeout: 10))

        rename(workspaceButton: initialWorkspaceButton, in: dirtyApp, to: "Inbox")
        assertSelectedWorkspaceTitle(in: dirtyApp, equals: "Workspace Inbox")
        dirtyApp.terminate()

        let resetApp = try launchApp(defaultsSuiteName: suiteName)
        defer { resetApp.terminate() }

        XCTAssertEqual(selectedWorkspaceTitle(in: resetApp), "Workspace New Strip 1")
    }

    private func launchApp(defaultsSuiteName: String? = nil) throws -> XCUIApplication {
        let defaultsSuiteName = defaultsSuiteName ?? makeDefaultsSuiteName()
        UserDefaults(suiteName: defaultsSuiteName)?.removePersistentDomain(forName: defaultsSuiteName)
        let app = XCUIApplication(url: try resolvedAppBundleURL())
        app.terminate()
        app.launchEnvironment["TAIRI_UI_TEST"] = "1"
        app.launchEnvironment["TAIRI_UI_TEST_DEFAULTS_SUITE"] = defaultsSuiteName
        app.launch()
        app.activate()
        XCTAssertTrue(element(in: app, identifiedBy: Identifiers.appRoot).waitForExistence(timeout: 15))
        return app
    }

    private func makeDefaultsSuiteName() -> String {
        let suiteName = "TairiUITests.\(UUID().uuidString)"
        userDefaultsSuiteNames.append(suiteName)
        return suiteName
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
        return repoRoot.appendingPathComponent("dist/Tairi.app")
    }

    private func tileQuery(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier MATCHES %@", Identifiers.workspaceTilePattern)
        )
    }

    private func element(in app: XCUIApplication, identifiedBy identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func createNewTile(in app: XCUIApplication) {
        app.typeKey("n", modifierFlags: [.command])
    }

    private func visibleTileElements(in app: XCUIApplication) -> [XCUIElement] {
        tileQuery(in: app).allElementsBoundByIndex.filter(\.exists)
    }

    private func selectedWorkspaceTitle(in app: XCUIApplication) -> String {
        let titledElement = app.staticTexts[Identifiers.workspaceTitle]
        if titledElement.exists {
            let explicitValue = titledElement.value as? String
            if let explicitValue, !explicitValue.isEmpty {
                return explicitValue
            }

            if !titledElement.label.isEmpty {
                return titledElement.label
            }
        }

        let fallback = app.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@", "Workspace ")
        ).firstMatch
        return stringValue(of: fallback)
    }

    private func selectNextWorkspace(in app: XCUIApplication) {
        app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: [.command, .option])
    }

    private func workspaceButtons(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", Identifiers.workspaceButtonPrefix)
        )
    }

    private func workspaceButton(in app: XCUIApplication, at index: Int) -> XCUIElement {
        workspaceButtons(in: app).element(boundBy: index)
    }

    private func workspaceRenameField(in app: XCUIApplication) -> XCUIElement {
        app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", Identifiers.workspaceRenameFieldPrefix)
        ).firstMatch
    }

    private func rename(workspaceButton: XCUIElement, in app: XCUIApplication, to title: String) {
        workspaceButton.doubleClick()

        let renameField = workspaceRenameField(in: app)
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.click()
        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        renameField.typeText("\(title)\n")
    }

    private func emptyWorkspaceState(in app: XCUIApplication) -> XCUIElement {
        element(in: app, identifiedBy: Identifiers.emptyWorkspaceState)
    }

    private func tileCloseButtonQuery(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier MATCHES %@", Identifiers.workspaceTileCloseButtonPattern)
        )
    }

    private func tileResizeHandleQuery(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier MATCHES %@", Identifiers.workspaceTileResizeHandlePattern)
        )
    }

    private func waitForFrameWidth(
        of element: @escaping () -> XCUIElement,
        toBeLessThan threshold: CGFloat,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate { _, _ in
            element().frame.width < threshold
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForFrameWidth(
        of element: @escaping () -> XCUIElement,
        toBeGreaterThan threshold: CGFloat,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate { _, _ in
            element().frame.width > threshold
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForVisibleTileCount(
        in app: XCUIApplication,
        atLeast threshold: Int,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate { _, _ in
            self.visibleTileElements(in: app).count >= threshold
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForVisibleTileCount(
        in app: XCUIApplication,
        toEqual expectedCount: Int,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate { _, _ in
            self.visibleTileElements(in: app).count == expectedCount
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func assertSelectedWorkspaceTitle(
        in app: XCUIApplication,
        equals expectedTitle: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            waitForSelectedWorkspaceTitle(in: app, toEqual: expectedTitle, timeout: timeout),
            file: file,
            line: line
        )
        XCTAssertEqual(selectedWorkspaceTitle(in: app), expectedTitle, file: file, line: line)
    }

    private func waitForSelectedWorkspaceTitle(
        in app: XCUIApplication,
        toEqual expectedTitle: String,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate { _, _ in
            self.selectedWorkspaceTitle(in: app) == expectedTitle
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

    private func stringValue(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }
}
