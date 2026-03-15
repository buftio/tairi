import AppKit

@MainActor
final class WorkspaceInteractionController: ObservableObject {
    enum TileTransition: Equatable {
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

    struct TileCloseAnimation: Equatable {
        let id: Int
        let workspaceID: UUID
        let insertionIndex: Int
        let snapshotWidth: CGFloat
        let gapWidth: CGFloat
        let animated: Bool
        let snapshotImage: NSImage?

        static func == (lhs: TileCloseAnimation, rhs: TileCloseAnimation) -> Bool {
            lhs.id == rhs.id
        }
    }

    struct TileOpenAnimation: Equatable {
        let id: Int
        let tileID: UUID
        let animated: Bool
    }

    @Published private(set) var canvasTransition: CanvasTransition?
    @Published private(set) var tileCloseAnimation: TileCloseAnimation?
    @Published private(set) var tileOpenAnimation: TileOpenAnimation?

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
        if transition != .preserveViewport {
            tileOpenAnimation = TileOpenAnimation(
                id: nextTransitionID,
                tileID: tile.id,
                animated: transition == .animatedReveal
            )
            nextTransitionID += 1
        }
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

    func revealSelection(of tileID: UUID, transition: TileTransition = .immediate) {
        publishTransition(for: tileID, transition: transition)
    }

    func animateTileClose(
        workspaceID: UUID,
        insertionIndex: Int,
        snapshotWidth: CGFloat,
        gapWidth: CGFloat,
        animated: Bool,
        snapshotImage: NSImage?
    ) {
        tileCloseAnimation = TileCloseAnimation(
            id: nextTransitionID,
            workspaceID: workspaceID,
            insertionIndex: insertionIndex,
            snapshotWidth: snapshotWidth,
            gapWidth: gapWidth,
            animated: animated,
            snapshotImage: snapshotImage
        )
        nextTransitionID += 1
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
