import XCTest
@testable import TairiApp

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    func testInitialTileUsesProvidedWorkingDirectory() {
        let store = WorkspaceStore(initialTerminalWorkingDirectory: "/tmp/dev-root")

        XCTAssertEqual(store.selectedTile?.pwd, "/tmp/dev-root")
    }

    func testNewTileInheritsSelectedTileDirectory() throws {
        let store = WorkspaceStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let firstTileID = try XCTUnwrap(store.selectedTileID)

        store.updatePWD("/tmp/project-a", for: firstTileID)
        let newTile = store.addTerminalTile(nextTo: firstTileID, sessionID: UUID())

        XCTAssertEqual(newTile.pwd, "/tmp/project-a")
    }

    func testNewTileInEmptyWorkspaceFallsBackToHomeDirectory() throws {
        let store = WorkspaceStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let emptyWorkspaceID = try XCTUnwrap(
            store.workspaces.first(where: { $0.id != store.selectedWorkspaceID })?.id
        )

        store.selectWorkspace(emptyWorkspaceID)
        let newTile = store.addTerminalTile(sessionID: UUID())

        XCTAssertEqual(newTile.pwd, TerminalWorkingDirectory.defaultDirectoryForEmptyWorkspace())
    }

    func testInitialTileBindsSessionIdentity() throws {
        let sessionID = UUID()
        let store = WorkspaceStore(
            initialTerminalWorkingDirectory: "/tmp/dev-root",
            initialTerminalSessionID: sessionID
        )

        XCTAssertEqual(try XCTUnwrap(store.selectedTile).surface.terminalSessionID, sessionID)
    }

    func testInitialStripsCreateOneWorkspacePerStripWithConfiguredWidths() throws {
        let store = WorkspaceStore(
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

    func testSingleTileLayoutExpandsToViewport() throws {
        let store = WorkspaceStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
        let tile = try XCTUnwrap(store.selectedTile)
        let workspace = store.selectedWorkspace

        let renderedWidth = WorkspaceRowLayout.renderedTileWidth(
            for: tile,
            in: workspace,
            viewportWidth: 1_260,
            stripLeadingInset: WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)
        )

        XCTAssertEqual(renderedWidth, 991, accuracy: 0.5)
    }

    func testClosingSelectedTileChoosesNeighborNearestVisibleCenter() throws {
        let store = WorkspaceStore(initialTerminalWorkingDirectory: "/tmp/dev-root")
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
}
