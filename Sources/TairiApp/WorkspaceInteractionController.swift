import Foundation

@MainActor
final class WorkspaceInteractionController: ObservableObject {
    enum TileTransition {
        case immediate
        case animatedReveal
    }

    struct CanvasTransition: Equatable {
        let id: Int
        let tileID: UUID
        let animated: Bool
    }

    @Published private(set) var canvasTransition: CanvasTransition?

    private let store: WorkspaceStore
    private var nextTransitionID = 1

    init(store: WorkspaceStore) {
        self.store = store
    }

    func selectWorkspace(_ workspaceID: UUID, preferredVisibleMidX: CGFloat? = nil) {
        store.selectWorkspace(workspaceID, preferredVisibleMidX: preferredVisibleMidX)
    }

    func selectAdjacentWorkspace(offset: Int, preferredVisibleMidX: CGFloat? = nil) {
        store.selectAdjacentWorkspace(offset: offset, preferredVisibleMidX: preferredVisibleMidX)
    }

    func selectTile(_ tileID: UUID, transition: TileTransition = .immediate) {
        let previousTileID = store.selectedTileID
        store.selectTile(tileID)

        guard previousTileID != tileID || transition == .animatedReveal else {
            return
        }
        publishReveal(for: tileID, animated: transition == .animatedReveal)
    }

    func selectAdjacentTile(offset: Int, transition: TileTransition = .immediate) {
        let previousTileID = store.selectedTileID
        store.selectAdjacentTile(offset: offset)

        guard let selectedTileID = store.selectedTileID, previousTileID != selectedTileID else {
            return
        }
        publishReveal(for: selectedTileID, animated: transition == .animatedReveal)
    }

    func scrollSelectedWorkspaceHorizontally(deltaX: CGFloat, viewportWidth: CGFloat) {
        store.scrollSelectedWorkspaceHorizontally(deltaX: deltaX, viewportWidth: viewportWidth)
    }

    func revealTile(_ tileID: UUID, viewportWidth: CGFloat) {
        store.revealTile(tileID, viewportWidth: viewportWidth)
    }

    private func publishReveal(for tileID: UUID, animated: Bool) {
        canvasTransition = CanvasTransition(
            id: nextTransitionID,
            tileID: tileID,
            animated: animated
        )
        nextTransitionID += 1
    }
}
