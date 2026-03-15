import Foundation

@MainActor
final class WorkspaceInteractionController: ObservableObject {
    enum TileTransition {
        case immediate
        case animatedReveal
        case preserveViewport
    }

    struct CanvasTransition: Equatable {
        enum Kind: Equatable {
            case reveal(tileID: UUID, animated: Bool)
            case preserveViewport
        }

        let id: Int
        let kind: Kind
    }

    @Published private(set) var canvasTransition: CanvasTransition?

    private let store: WorkspaceStore
    private var nextTransitionID = 1

    init(store: WorkspaceStore) {
        self.store = store
    }

    func selectWorkspace(
        _ workspaceID: UUID,
        preferredVisibleMidX: CGFloat? = nil,
        stripLeadingInset: CGFloat = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)
    ) {
        store.selectWorkspace(
            workspaceID,
            preferredVisibleMidX: preferredVisibleMidX,
            stripLeadingInset: stripLeadingInset
        )
    }

    func selectAdjacentWorkspace(
        offset: Int,
        preferredVisibleMidX: CGFloat? = nil,
        stripLeadingInset: CGFloat = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)
    ) {
        store.selectAdjacentWorkspace(
            offset: offset,
            preferredVisibleMidX: preferredVisibleMidX,
            stripLeadingInset: stripLeadingInset
        )
    }

    func selectTile(_ tileID: UUID, transition: TileTransition = .immediate) {
        let previousTileID = store.selectedTileID
        store.selectTile(tileID)

        guard previousTileID != tileID || transition == .animatedReveal else {
            return
        }
        publishTransition(for: tileID, transition: transition)
    }

    func selectAdjacentTile(offset: Int, transition: TileTransition = .immediate) {
        let previousTileID = store.selectedTileID
        store.selectAdjacentTile(offset: offset)

        guard let selectedTileID = store.selectedTileID, previousTileID != selectedTileID else {
            return
        }
        publishTransition(for: selectedTileID, transition: transition)
    }

    @discardableResult
    func addTerminalTile(
        nextTo tileID: UUID? = nil,
        workingDirectory: String? = nil,
        sessionID: UUID,
        transition: TileTransition = .preserveViewport
    ) -> WorkspaceStore.Tile {
        let tile = store.addTerminalTile(
            nextTo: tileID,
            workingDirectory: workingDirectory,
            sessionID: sessionID
        )
        publishTransition(for: tile.id, transition: transition)
        return tile
    }

    func scrollSelectedWorkspaceHorizontally(
        deltaX: CGFloat,
        viewportWidth: CGFloat,
        stripLeadingInset: CGFloat
    ) {
        store.scrollSelectedWorkspaceHorizontally(
            deltaX: deltaX,
            viewportWidth: viewportWidth,
            stripLeadingInset: stripLeadingInset
        )
    }

    func revealTile(_ tileID: UUID, viewportWidth: CGFloat, stripLeadingInset: CGFloat) {
        store.revealTile(
            tileID,
            viewportWidth: viewportWidth,
            stripLeadingInset: stripLeadingInset
        )
    }

    private func publishTransition(for tileID: UUID, transition: TileTransition) {
        let kind: CanvasTransition.Kind
        switch transition {
        case .immediate:
            kind = .reveal(tileID: tileID, animated: false)
        case .animatedReveal:
            kind = .reveal(tileID: tileID, animated: true)
        case .preserveViewport:
            kind = .preserveViewport
        }

        canvasTransition = CanvasTransition(
            id: nextTransitionID,
            kind: kind
        )
        nextTransitionID += 1
    }
}
