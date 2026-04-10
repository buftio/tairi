import XCTest

@testable import TairiApp

@MainActor
final class WorkspaceCanvasZoomControllerTests: XCTestCase {
    func testOverviewWorkspacesDropOnlyTrailingEmptyStrips() {
        let tiledWorkspace = WorkspaceStore.Workspace(
            title: "One",
            tiles: [makeTile(width: 800)]
        )
        let middleEmptyWorkspace = WorkspaceStore.Workspace(title: "Two")
        let trailingTiledWorkspace = WorkspaceStore.Workspace(
            title: "Three",
            tiles: [makeTile(width: 640)]
        )
        let trailingEmptyWorkspace = WorkspaceStore.Workspace(title: "Four")
        let placeholderWorkspace = WorkspaceStore.Workspace(title: "Five")

        let overviewWorkspaces = WorkspaceCanvasZoomController.overviewWorkspaces(
            from: [
                tiledWorkspace,
                middleEmptyWorkspace,
                trailingTiledWorkspace,
                trailingEmptyWorkspace,
                placeholderWorkspace,
            ]
        )

        XCTAssertEqual(
            overviewWorkspaces.map(\.id),
            [
                tiledWorkspace.id,
                middleEmptyWorkspace.id,
                trailingTiledWorkspace.id,
            ]
        )
    }

    func testOverviewScaleIgnoresTrailingEmptyStrips() {
        let controller = WorkspaceCanvasZoomController()
        let tiledWorkspace = WorkspaceStore.Workspace(
            title: "One",
            tiles: [makeTile(width: 760)]
        )
        let trailingEmptyWorkspace = WorkspaceStore.Workspace(title: "Two")
        let viewportSize = CGSize(width: 1440, height: 900)
        let stripLeadingInset = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)

        let scaleWithoutTrailingEmpty = controller.scale(
            mode: .overview,
            viewportSize: viewportSize,
            workspaces: [tiledWorkspace],
            stripLeadingInset: stripLeadingInset
        )
        let scaleWithTrailingEmpty = controller.scale(
            mode: .overview,
            viewportSize: viewportSize,
            workspaces: [tiledWorkspace, trailingEmptyWorkspace],
            stripLeadingInset: stripLeadingInset
        )

        XCTAssertEqual(scaleWithTrailingEmpty, scaleWithoutTrailingEmpty, accuracy: 0.001)
    }

    private func makeTile(width: CGFloat) -> WorkspaceStore.Tile {
        WorkspaceStore.Tile(
            width: width,
            surface: .terminal(sessionID: UUID())
        )
    }
}
