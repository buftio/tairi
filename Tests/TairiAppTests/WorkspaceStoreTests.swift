import XCTest
@testable import TairiApp

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private nonisolated(unsafe) var userDefaultsSuiteNames: [String] = []

    override func tearDown() {
        for suiteName in userDefaultsSuiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        userDefaultsSuiteNames = []
        super.tearDown()
    }

    func testInitialTileUsesProvidedWorkingDirectory() {
        let store = makeStore(initialTerminalWorkingDirectory: "/tmp/dev-root")

        XCTAssertEqual(store.selectedTile?.pwd, "/tmp/dev-root")
    }

    func testNewTileInheritsSelectedTileDirectory() throws {
        let store = makeStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let firstTileID = try XCTUnwrap(store.selectedTileID)

        store.updatePWD("/tmp/project-a", for: firstTileID)
        let newTile = store.addTerminalTile(nextTo: firstTileID, sessionID: UUID())

        XCTAssertEqual(newTile.pwd, "/tmp/project-a")
    }

    func testNewTileInEmptyWorkspaceFallsBackToHomeDirectory() throws {
        let store = makeStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let emptyWorkspaceID = try XCTUnwrap(
            store.workspaces.first(where: { $0.id != store.selectedWorkspaceID })?.id
        )

        store.selectWorkspace(emptyWorkspaceID)
        let newTile = store.addTerminalTile(sessionID: UUID())

        XCTAssertEqual(newTile.pwd, TerminalWorkingDirectory.defaultDirectoryForEmptyWorkspace())
    }

    func testNewTilePrefersAssignedWorkspaceFolder() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let store = makeStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let firstTileID = try XCTUnwrap(store.selectedTileID)

        store.updatePWD("/tmp/project-a", for: firstTileID)
        store.setWorkspaceFolder(store.selectedWorkspaceID, to: tempDirectory)

        let newTile = store.addTerminalTile(nextTo: firstTileID, sessionID: UUID())

        XCTAssertEqual(newTile.pwd, tempDirectory)
    }

    func testSplitTileCreatesVerticalSiblingOnSameWorkspaceAndDividesHeight() throws {
        let store = makeStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let firstTileID = try XCTUnwrap(store.selectedTileID)
        let originalTile = try XCTUnwrap(store.selectedTile)

        let splitTile = try XCTUnwrap(store.splitTerminalTile(firstTileID, sessionID: UUID()))
        let tiles = store.selectedWorkspace.tiles

        XCTAssertEqual(tiles.count, 2)
        XCTAssertEqual(tiles[0].id, firstTileID)
        XCTAssertEqual(tiles[1].id, splitTile.id)
        XCTAssertEqual(tiles[0].columnID, originalTile.columnID)
        XCTAssertEqual(tiles[1].columnID, originalTile.columnID)
        XCTAssertEqual(tiles[0].width, originalTile.width, accuracy: 0.001)
        XCTAssertEqual(tiles[1].width, originalTile.width, accuracy: 0.001)
        XCTAssertEqual(tiles[0].heightWeight + tiles[1].heightWeight, originalTile.heightWeight, accuracy: 0.001)
    }

    func testInitialTileBindsSessionIdentity() throws {
        let sessionID = UUID()
        let store = makeStore(
            initialTerminalWorkingDirectory: "/tmp/dev-root",
            initialTerminalSessionID: sessionID
        )

        XCTAssertEqual(try XCTUnwrap(store.selectedTile).surface.terminalSessionID, sessionID)
    }

    func testInitialStripsCreateOneWorkspacePerStripWithConfiguredWidths() throws {
        let store = makeStore(
            initialTerminalWorkingDirectory: "/tmp/dev-root",
            initialStrips: [
                .init(tileWidthFactors: [1, 1, 1]),
                .init(tileWidthFactors: [0.5, 1]),
            ]
        )

        XCTAssertEqual(store.workspaces.count, 3)
        XCTAssertEqual(store.workspaces[0].tiles.count, 3)
        XCTAssertEqual(store.workspaces[1].tiles.count, 2)
        XCTAssertTrue(store.workspaces[2].tiles.isEmpty)
        XCTAssertEqual(store.workspaces[0].tiles[0].width, WorkspaceStore.WidthPreset.standard.width, accuracy: 0.001)
        XCTAssertEqual(store.workspaces[1].tiles[0].width, WorkspaceStore.WidthPreset.standard.width * 0.5, accuracy: 0.001)
    }

    func testCustomWorkspaceTitleSurvivesNormalizationAndBlankRenameRestoresAutomaticTitle() throws {
        let store = makeStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let firstWorkspaceID = try XCTUnwrap(store.workspaces.first?.id)
        let firstTileID = try XCTUnwrap(store.selectedTileID)

        store.renameWorkspace(firstWorkspaceID, to: "Inbox")
        _ = store.addTerminalTile(nextTo: firstTileID, sessionID: UUID())

        XCTAssertEqual(store.workspaces.first?.title, "Inbox")
        XCTAssertEqual(store.workspaces.dropFirst().first?.title, "New Strip 2")

        store.renameWorkspace(firstWorkspaceID, to: "   ")

        XCTAssertEqual(store.workspaces.first?.title, "New Strip 1")
        XCTAssertTrue(try XCTUnwrap(store.workspaces.first?.usesAutomaticTitle))
    }

    func testNamedWorkspaceStaysAfterClosingLastTile() throws {
        let store = makeStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let workspaceID = store.selectedWorkspaceID
        let tileID = try XCTUnwrap(store.selectedTileID)

        store.renameWorkspace(workspaceID, to: "Inbox")
        _ = store.closeTile(tileID)

        let workspace = try XCTUnwrap(store.workspaces.first(where: { $0.id == workspaceID }))
        XCTAssertEqual(workspace.title, "Inbox")
        XCTAssertTrue(workspace.tiles.isEmpty)
    }

    func testFolderAssignedWorkspaceStaysAfterClosingLastTile() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let store = makeStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let workspaceID = store.selectedWorkspaceID
        let tileID = try XCTUnwrap(store.selectedTileID)

        store.setWorkspaceFolder(workspaceID, to: tempDirectory)
        _ = store.closeTile(tileID)

        let workspace = try XCTUnwrap(store.workspaces.first(where: { $0.id == workspaceID }))
        XCTAssertEqual(workspace.folderPath, tempDirectory)
        XCTAssertTrue(workspace.tiles.isEmpty)
    }

    func testCustomIconWorkspaceStaysAfterClosingLastTile() throws {
        let store = makeStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let workspaceID = store.selectedWorkspaceID
        let tileID = try XCTUnwrap(store.selectedTileID)

        store.setWorkspaceIconSymbol(workspaceID, to: "terminal")
        _ = store.closeTile(tileID)

        let workspace = try XCTUnwrap(store.workspaces.first(where: { $0.id == workspaceID }))
        XCTAssertEqual(workspace.iconSymbolName, "terminal")
        XCTAssertTrue(workspace.tiles.isEmpty)
    }

    func testSettingIconFileClearsExistingSymbol() {
        let store = makeStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let workspaceID = store.selectedWorkspaceID

        store.setWorkspaceIconSymbol(workspaceID, to: "terminal")
        store.setWorkspaceIconFilePath(workspaceID, to: "/tmp/custom-icon.png")

        XCTAssertNil(store.selectedWorkspace.iconSymbolName)
        XCTAssertEqual(store.selectedWorkspace.iconFilePath, "/tmp/custom-icon.png")
    }

    func testAutomaticWorkspaceTitleUsesAssignedFolderName() throws {
        let tempDirectory = try makeTemporaryDirectory(named: "Inbox")
        let store = makeStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let workspaceID = store.selectedWorkspaceID

        store.setWorkspaceFolder(workspaceID, to: tempDirectory)

        let workspace = try XCTUnwrap(store.workspaces.first(where: { $0.id == workspaceID }))
        XCTAssertEqual(workspace.folderPath, tempDirectory)
        XCTAssertEqual(workspace.title, "Inbox")
        XCTAssertTrue(workspace.usesAutomaticTitle)
    }

    func testCustomWorkspaceTitleSurvivesAssignedFolderName() throws {
        let tempDirectory = try makeTemporaryDirectory(named: "Inbox")
        let store = makeStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let workspaceID = store.selectedWorkspaceID

        store.renameWorkspace(workspaceID, to: "Today")
        store.setWorkspaceFolder(workspaceID, to: tempDirectory)

        let workspace = try XCTUnwrap(store.workspaces.first(where: { $0.id == workspaceID }))
        XCTAssertEqual(workspace.folderPath, tempDirectory)
        XCTAssertEqual(workspace.title, "Today")
        XCTAssertFalse(workspace.usesAutomaticTitle)
    }

    func testInitialLaunchDirectoryFallsBackToHomeOutsideRepository() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let homeDirectory = "/Users/example"

        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let resolved = TerminalWorkingDirectory.defaultInitialLaunchDirectory(
            currentDirectoryPath: tempDirectory.path(percentEncoded: false),
            homeDirectoryPath: homeDirectory
        )

        XCTAssertEqual(resolved, homeDirectory)
    }

    func testClosingSelectedTileChoosesNeighborNearestVisibleCenter() throws {
        let store = makeStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let firstTileID = try XCTUnwrap(store.selectedTileID)

        let middleTile = store.addTerminalTile(nextTo: firstTileID, sessionID: UUID())
        let trailingNeighborTile = store.addTerminalTile(nextTo: middleTile.id, sessionID: UUID())
        let farTrailingTile = store.addTerminalTile(nextTo: trailingNeighborTile.id, sessionID: UUID())

        store.selectTile(middleTile.id)
        let selectedTileID = store.closeTile(
            middleTile.id,
            preferredVisibleMidX: 10_000,
            stripLeadingInset: WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)
        )

        XCTAssertEqual(selectedTileID, trailingNeighborTile.id)
        XCTAssertEqual(store.selectedTileID, trailingNeighborTile.id)
        XCTAssertNotEqual(store.selectedTileID, farTrailingTile.id)
    }

    func testMoveWorkspaceReordersList() throws {
        let store = makeStore(
            initialTerminalWorkingDirectory: "/tmp/dev-root",
            initialStrips: [
                .init(tileWidthFactors: [1]),
                .init(tileWidthFactors: [1]),
            ]
        )
        let originalIDs = store.workspaces.map(\.id)
        let sourceID = try XCTUnwrap(originalIDs.dropFirst().first)
        let targetID = try XCTUnwrap(originalIDs.first)

        store.moveWorkspace(sourceID, relativeTo: targetID, position: .before)

        XCTAssertEqual(store.workspaces.first?.id, sourceID)
        XCTAssertEqual(store.workspaces.dropFirst().first?.id, targetID)
    }

    func testPersistentStripsRestoreFromSidebarPersistence() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let persistence = makeSidebarPersistence()
        let initialStore = WorkspaceStore(
            initialTerminalWorkingDirectory: "/tmp/dev-root",
            sidebarPersistence: persistence
        )
        let persistentWorkspaceID = try XCTUnwrap(
            initialStore.workspaces.first(where: { $0.id != initialStore.selectedWorkspaceID })?.id
        )
        let iconFilePath = URL(fileURLWithPath: tempDirectory, isDirectory: true)
            .appendingPathComponent("icon.png", isDirectory: false)
            .path(percentEncoded: false)

        initialStore.renameWorkspace(persistentWorkspaceID, to: "Docs")
        initialStore.setWorkspaceFolder(persistentWorkspaceID, to: tempDirectory)
        initialStore.setWorkspaceIconFilePath(persistentWorkspaceID, to: iconFilePath)

        let restoredStore = WorkspaceStore(
            initialTerminalWorkingDirectory: "/tmp/dev-root",
            sidebarPersistence: persistence
        )

        let restoredWorkspace = try XCTUnwrap(restoredStore.workspaces.first(where: { $0.title == "Docs" }))
        XCTAssertEqual(restoredWorkspace.folderPath, tempDirectory)
        XCTAssertEqual(restoredWorkspace.iconFilePath, iconFilePath)
        XCTAssertNil(restoredWorkspace.iconSymbolName)
        XCTAssertEqual(restoredStore.workspaces.first?.id, restoredWorkspace.id)
        XCTAssertEqual(restoredStore.selectedWorkspaceID, restoredWorkspace.id)
        XCTAssertEqual(restoredWorkspace.tiles.count, 1)
        XCTAssertEqual(restoredWorkspace.tiles.first?.pwd, tempDirectory)
    }

    private func makeSidebarPersistence() -> WorkspaceSidebarPersistence {
        let suiteName = "WorkspaceStoreTests.\(UUID().uuidString)"
        userDefaultsSuiteNames.append(suiteName)
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return WorkspaceSidebarPersistence(userDefaults: userDefaults)
    }

    private func makeStore(
        initialTerminalWorkingDirectory: String,
        initialStrips: [TairiLaunchConfiguration.Strip] = TairiLaunchConfiguration.defaultStrips,
        initialTerminalSessionID: UUID = UUID()
    ) -> WorkspaceStore {
        WorkspaceStore(
            initialTerminalWorkingDirectory: initialTerminalWorkingDirectory,
            initialStrips: initialStrips,
            initialTerminalSessionID: initialTerminalSessionID,
            sidebarPersistence: makeSidebarPersistence()
        )
    }

    private func makeTemporaryDirectory(named name: String = UUID().uuidString) throws -> String {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.path(percentEncoded: false)
    }
}
