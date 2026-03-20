import XCTest

@testable import TairiApp

@MainActor
final class TileSpotlightSearchTests: XCTestCase {
    func testSearchMatchesFolderNameWhenTitleDoesNot() throws {
        let store = WorkspaceStore(initialTerminalWorkingDirectory: "/tmp/root")
        let firstTileID = try XCTUnwrap(store.selectedTileID)

        store.updateTitle("shell", for: firstTileID)
        store.updatePWD("/tmp/projects/tairi", for: firstTileID)

        let results = store.spotlightResults(matching: "tair")

        XCTAssertEqual(results.first?.id, firstTileID)
        XCTAssertEqual(results.first?.folderName, "tairi")
    }

    func testSearchCombinesTitleAndFolderTokens() throws {
        let store = WorkspaceStore(initialTerminalWorkingDirectory: "/tmp/root")
        let firstTileID = try XCTUnwrap(store.selectedTileID)

        store.updateTitle("build", for: firstTileID)
        store.updatePWD("/tmp/projects/frontend-shell", for: firstTileID)

        let otherTile = store.addTerminalTile(nextTo: firstTileID, sessionID: UUID())
        store.updateTitle("build", for: otherTile.id)
        store.updatePWD("/tmp/projects/backend-api", for: otherTile.id)

        let results = store.spotlightResults(matching: "bui shell")

        XCTAssertEqual(results.first?.id, firstTileID)
        XCTAssertTrue(results.contains(where: { $0.id == firstTileID }))
        XCTAssertFalse(results.contains(where: { $0.id == otherTile.id }))
    }

    func testEmptyQueryKeepsSelectedTileRankedFirst() throws {
        let store = WorkspaceStore(initialTerminalWorkingDirectory: "/tmp/root")
        let firstTileID = try XCTUnwrap(store.selectedTileID)
        let secondTile = store.addTerminalTile(nextTo: firstTileID, sessionID: UUID())

        store.selectTile(firstTileID)
        let results = store.spotlightResults(matching: "")

        XCTAssertEqual(results.first?.id, firstTileID)
        XCTAssertEqual(results.dropFirst().first?.id, secondTile.id)
    }

    func testEmptyQueryUsesRecentVisitOrder() throws {
        let store = WorkspaceStore(initialTerminalWorkingDirectory: "/tmp/root")
        let firstTileID = try XCTUnwrap(store.selectedTileID)
        let secondTile = store.addTerminalTile(nextTo: firstTileID, sessionID: UUID())
        let thirdTile = store.addTerminalTile(nextTo: secondTile.id, sessionID: UUID())

        store.selectTile(secondTile.id)
        store.selectTile(firstTileID)

        let results = store.spotlightResults(matching: "")

        XCTAssertEqual(results.map(\.id).prefix(3), [firstTileID, secondTile.id, thirdTile.id])
    }
}
