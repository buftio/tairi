import XCTest

@testable import TairiApp

@MainActor
final class WorkspaceInteractionControllerTests: XCTestCase {
    private nonisolated(unsafe) var userDefaultsSuiteNames: [String] = []

    override func tearDown() {
        for suiteName in userDefaultsSuiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        userDefaultsSuiteNames = []
        super.tearDown()
    }

    func testAddTerminalTilePublishesColumnOpenAnimation() throws {
        let store = makeStore()
        let controller = WorkspaceInteractionController(store: store)
        let tileID = try XCTUnwrap(store.selectedTileID)

        let tile = controller.addTerminalTile(
            nextTo: tileID,
            sessionID: UUID(),
            transition: .animatedReveal
        )
        let animation = try XCTUnwrap(controller.tileOpenAnimation)

        XCTAssertEqual(animation.tileID, tile.id)
        XCTAssertTrue(animation.animated)
        XCTAssertEqual(animation.kind, .columnOpen)
    }

    func testSplitTerminalTilePublishesVerticalSplitOpenAnimation() throws {
        let store = makeStore()
        let controller = WorkspaceInteractionController(store: store)
        let sourceTileID = try XCTUnwrap(store.selectedTileID)

        let tile = try XCTUnwrap(
            controller.splitTerminalTile(
                sourceTileID,
                sessionID: UUID(),
                transition: .animatedReveal
            )
        )
        let animation = try XCTUnwrap(controller.tileOpenAnimation)

        XCTAssertEqual(animation.tileID, tile.id)
        XCTAssertTrue(animation.animated)
        XCTAssertEqual(animation.kind, .verticalSplit(sourceTileID: sourceTileID))
    }

    func testAddGitTilePublishesColumnOpenAnimation() throws {
        let store = makeStore()
        let controller = WorkspaceInteractionController(store: store)
        let tileID = try XCTUnwrap(store.selectedTileID)

        let tile = controller.addGitTile(
            nextTo: tileID,
            transition: .animatedReveal
        )
        let animation = try XCTUnwrap(controller.tileOpenAnimation)

        XCTAssertEqual(tile.surface.kind, .git)
        XCTAssertEqual(animation.tileID, tile.id)
        XCTAssertTrue(animation.animated)
        XCTAssertEqual(animation.kind, .columnOpen)
    }

    func testSelectAdjacentWorkspacePreservingViewportUsesTargetWorkspaceOffset() throws {
        let store = makeStore(
            initialStrips: [
                .init(tileWidthFactors: [1, 1, 1]),
                .init(tileWidthFactors: [1, 1, 1]),
            ]
        )
        let controller = WorkspaceInteractionController(store: store)
        let secondWorkspace = try XCTUnwrap(store.workspaces.dropFirst().first(where: { !$0.tiles.isEmpty }))
        let secondTileID = secondWorkspace.tiles[1].id
        let viewportWidth: CGFloat = 900
        let stripLeadingInset = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)

        store.setHorizontalOffset(
            secondWorkspace.tiles[1].width + WorkspaceCanvasLayoutMetrics.tileSpacing
                - WorkspaceCanvasLayoutMetrics.neighboringTilePeek,
            for: secondWorkspace.id,
            viewportWidth: viewportWidth,
            stripLeadingInset: stripLeadingInset
        )
        controller.updateWorkspaceNavigationViewport(width: viewportWidth)

        controller.selectAdjacentWorkspacePreservingViewport(offset: 1)

        XCTAssertEqual(store.selectedWorkspaceID, secondWorkspace.id)
        XCTAssertEqual(store.selectedTileID, secondTileID)
    }

    private func makeStore(
        initialStrips: [TairiLaunchConfiguration.Strip] = TairiLaunchConfiguration.defaultStrips
    ) -> WorkspaceStore {
        WorkspaceStore(
            initialTerminalWorkingDirectory: "/tmp/dev-root",
            initialStrips: initialStrips,
            sidebarPersistence: makeSidebarPersistence()
        )
    }

    private func makeSidebarPersistence() -> WorkspaceSidebarPersistence {
        let suiteName = "WorkspaceInteractionControllerTests.\(UUID().uuidString)"
        userDefaultsSuiteNames.append(suiteName)
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return WorkspaceSidebarPersistence(userDefaults: userDefaults)
    }
}
