import XCTest

@testable import TairiApp

@MainActor
final class WorkspaceStoreDirectoryTests: XCTestCase {
    private nonisolated(unsafe) var userDefaultsSuiteNames: [String] = []
    private nonisolated(unsafe) var temporaryDirectoryURLs: [URL] = []

    override func tearDown() {
        for directoryURL in temporaryDirectoryURLs {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        temporaryDirectoryURLs = []
        for suiteName in userDefaultsSuiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        userDefaultsSuiteNames = []
        super.tearDown()
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

    func testGitTileUsesAssignedWorkspaceFolder() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let store = makeStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let firstTileID = try XCTUnwrap(store.selectedTileID)

        store.setWorkspaceFolder(store.selectedWorkspaceID, to: tempDirectory)
        let gitTile = store.addGitTile(nextTo: firstTileID)

        XCTAssertEqual(gitTile.surface.kind, .git)
        XCTAssertNil(gitTile.surface.terminalSessionID)
        XCTAssertEqual(gitTile.pwd, tempDirectory)
    }

    func testSettingWorkspaceFolderUpdatesExistingGitTiles() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let store = makeStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let gitTile = store.addGitTile()

        store.setWorkspaceFolder(store.selectedWorkspaceID, to: tempDirectory)

        XCTAssertEqual(store.tile(gitTile.id)?.pwd, tempDirectory)
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

    func testTemporaryDirectoryHelperIsolatesRepeatedNames() throws {
        let firstDirectory = URL(fileURLWithPath: try makeTemporaryDirectory(named: "Inbox"), isDirectory: true)
        let secondDirectory = URL(fileURLWithPath: try makeTemporaryDirectory(named: "Inbox"), isDirectory: true)

        XCTAssertNotEqual(firstDirectory, secondDirectory)
        XCTAssertEqual(firstDirectory.lastPathComponent, "Inbox")
        XCTAssertEqual(secondDirectory.lastPathComponent, "Inbox")
        XCTAssertNotEqual(firstDirectory.deletingLastPathComponent(), secondDirectory.deletingLastPathComponent())
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

    func testRestoredPersistentStripWithDeletedFolderFallsBackForInitialTile() throws {
        let tempDirectory = try makeTemporaryDirectory()
        let persistence = makeSidebarPersistence()
        let initialStore = WorkspaceStore(
            initialTerminalWorkingDirectory: "/tmp/dev-root",
            sidebarPersistence: persistence
        )
        let persistentWorkspaceID = try XCTUnwrap(
            initialStore.workspaces.first(where: { $0.id != initialStore.selectedWorkspaceID })?.id
        )

        initialStore.renameWorkspace(persistentWorkspaceID, to: "Docs")
        initialStore.setWorkspaceFolder(persistentWorkspaceID, to: tempDirectory)
        try FileManager.default.removeItem(atPath: tempDirectory)

        let restoredStore = WorkspaceStore(
            initialTerminalWorkingDirectory: "/tmp/dev-root",
            sidebarPersistence: persistence
        )

        let restoredWorkspace = try XCTUnwrap(restoredStore.workspaces.first(where: { $0.title == "Docs" }))
        XCTAssertEqual(restoredWorkspace.folderPath, tempDirectory)
        XCTAssertEqual(restoredWorkspace.tiles.first?.pwd, "/tmp/dev-root")
    }

    private func makeSidebarPersistence() -> WorkspaceSidebarPersistence {
        let suiteName = "WorkspaceStoreDirectoryTests.\(UUID().uuidString)"
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
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        temporaryDirectoryURLs.append(directoryURL.deletingLastPathComponent())
        return directoryURL.path(percentEncoded: false)
    }
}
