import XCTest

@testable import TairiApp

@MainActor
final class WorkspaceTileReorderControllerTests: XCTestCase {
    private nonisolated(unsafe) var userDefaultsSuiteNames: [String] = []

    override func tearDown() {
        for suiteName in userDefaultsSuiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        userDefaultsSuiteNames = []
        super.tearDown()
    }

    func testSplitColumnDragRetargetsAfterExtractionPreview() throws {
        let store = makeStore(initialStrips: [.init(tileWidthFactors: [1, 1])])
        let draggedTileID = try XCTUnwrap(store.selectedTileID)
        let trailingTile = try XCTUnwrap(store.selectedWorkspace.tiles.dropFirst().first)
        let splitTile = try XCTUnwrap(store.splitTerminalTile(draggedTileID, sessionID: UUID()))
        let controller = WorkspaceTileReorderController(store: store)
        let initialFrames = tileFrames(in: store.selectedWorkspace)
        let draggedFrame = try XCTUnwrap(initialFrames[draggedTileID])
        let initialPoint = CGPoint(x: draggedFrame.midX, y: draggedFrame.midY)
        let session = controller.beginSession(
            tileID: draggedTileID,
            workspaceID: store.selectedWorkspaceID,
            initialPointerLocation: initialPoint,
            initialTileFrame: draggedFrame
        )

        let extractionSession = controller.updateSession(
            session,
            currentPointerLocation: CGPoint(x: initialPoint.x + 150, y: initialPoint.y),
            workspaces: store.workspaces,
            tileFrames: initialFrames
        )

        XCTAssertEqual(extractionSession.move, WorkspaceTileMove(targetTileID: splitTile.id, direction: .right))

        let previewWorkspace = try XCTUnwrap(extractionSession.previewWorkspace)
        let previewFrames = tileFrames(in: previewWorkspace)
        let trailingFrame = try XCTUnwrap(previewFrames[trailingTile.id])
        let retargetedSession = controller.updateSession(
            extractionSession,
            currentPointerLocation: CGPoint(x: trailingFrame.midX, y: trailingFrame.midY),
            workspaces: store.workspaces,
            tileFrames: previewFrames
        )

        XCTAssertEqual(retargetedSession.move?.targetTileID, trailingTile.id)
        XCTAssertNotEqual(retargetedSession.move, extractionSession.move)
    }

    private func tileFrames(
        in workspace: WorkspaceStore.Workspace,
        tileHeight: CGFloat = 640
    ) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        var originX: CGFloat = 0

        for column in WorkspaceColumnLayout.columns(in: workspace) {
            frames.merge(
                WorkspaceColumnLayout.columnTileFrames(
                    for: column,
                    originX: originX,
                    originY: 0,
                    width: column.width,
                    height: tileHeight
                ),
                uniquingKeysWith: { _, new in new }
            )
            originX += column.width + WorkspaceCanvasLayoutMetrics.tileSpacing
        }

        return frames
    }

    private func makeStore(
        initialStrips: [TairiLaunchConfiguration.Strip]
    ) -> WorkspaceStore {
        WorkspaceStore(
            initialTerminalWorkingDirectory: "/tmp/dev-root",
            initialStrips: initialStrips,
            sidebarPersistence: makeSidebarPersistence()
        )
    }

    private func makeSidebarPersistence() -> WorkspaceSidebarPersistence {
        let suiteName = "WorkspaceTileReorderControllerTests.\(UUID().uuidString)"
        userDefaultsSuiteNames.append(suiteName)
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return WorkspaceSidebarPersistence(userDefaults: userDefaults)
    }
}
