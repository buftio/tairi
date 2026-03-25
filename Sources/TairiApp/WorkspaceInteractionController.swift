import AppKit

@MainActor
final class WorkspaceInteractionController: ObservableObject {
    enum CanvasZoomMode: Equatable {
        case focused
        case overview
    }

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

    struct WorkspaceRevealRequest: Equatable {
        let id: Int
        let workspaceID: UUID
        let animated: Bool
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
        enum Kind: Equatable {
            case columnOpen
            case verticalSplit(sourceTileID: UUID)
        }

        let id: Int
        let tileID: UUID
        let kind: Kind
        let animated: Bool
    }

    @Published private(set) var canvasTransition: CanvasTransition?
    @Published private(set) var tileCloseAnimation: TileCloseAnimation?
    @Published private(set) var tileOpenAnimation: TileOpenAnimation?
    @Published private(set) var workspaceRevealRequest: WorkspaceRevealRequest?
    @Published private(set) var canvasZoomMode: CanvasZoomMode = .focused

    private let store: WorkspaceStore
    private var nextTransitionID = 1

    init(
        store: WorkspaceStore,
        initialCanvasZoomMode: CanvasZoomMode = .focused
    ) {
        self.store = store
        canvasZoomMode = initialCanvasZoomMode
    }

    func selectWorkspace(
        _ workspaceID: UUID,
        preferredVisibleMidX: CGFloat? = nil,
        stripLeadingInset: CGFloat = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)
    ) {
        TairiLog.write(
            "workspace interaction selectWorkspace workspace=\(workspaceID.uuidString) preferredVisibleMidX=\(preferredVisibleMidX.map { String(format: "%.1f", $0) } ?? "nil") stripLeadingInset=\(String(format: "%.1f", stripLeadingInset)) fromWorkspace=\(store.selectedWorkspaceID.uuidString) fromTile=\(store.selectedTileID?.uuidString ?? "none")"
        )
        store.selectWorkspace(
            workspaceID,
            preferredVisibleMidX: preferredVisibleMidX,
            stripLeadingInset: stripLeadingInset
        )
        TairiLog.write(
            "workspace interaction selectWorkspace resolved workspace=\(store.selectedWorkspaceID.uuidString) tile=\(store.selectedTileID?.uuidString ?? "none")"
        )
    }

    func selectAdjacentWorkspace(
        offset: Int,
        preferredVisibleMidX: CGFloat? = nil,
        stripLeadingInset: CGFloat = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)
    ) {
        TairiLog.write(
            "workspace interaction selectAdjacentWorkspace offset=\(offset) preferredVisibleMidX=\(preferredVisibleMidX.map { String(format: "%.1f", $0) } ?? "nil") stripLeadingInset=\(String(format: "%.1f", stripLeadingInset)) fromWorkspace=\(store.selectedWorkspaceID.uuidString) fromTile=\(store.selectedTileID?.uuidString ?? "none")"
        )
        store.selectAdjacentWorkspace(
            offset: offset,
            preferredVisibleMidX: preferredVisibleMidX,
            stripLeadingInset: stripLeadingInset
        )
        TairiLog.write(
            "workspace interaction selectAdjacentWorkspace resolved workspace=\(store.selectedWorkspaceID.uuidString) tile=\(store.selectedTileID?.uuidString ?? "none")"
        )
    }

    func selectTile(_ tileID: UUID, transition: TileTransition = .immediate) {
        let previousTileID = store.selectedTileID
        let previousWorkspaceID = store.selectedWorkspaceID
        store.selectTile(tileID)
        TairiLog.write(
            "workspace interaction selectTile tile=\(tileID.uuidString) transition=\(String(describing: transition)) fromWorkspace=\(previousWorkspaceID.uuidString) fromTile=\(previousTileID?.uuidString ?? "none") resolvedWorkspace=\(store.selectedWorkspaceID.uuidString) resolvedTile=\(store.selectedTileID?.uuidString ?? "none")"
        )

        guard previousTileID != tileID || transition == .animatedReveal else {
            return
        }
        publishTransition(for: tileID, transition: transition)
    }

    func selectAdjacentTile(offset: Int, transition: TileTransition = .immediate) {
        let previousTileID = store.selectedTileID
        let previousWorkspaceID = store.selectedWorkspaceID
        store.selectAdjacentTile(offset: offset)
        TairiLog.write(
            "workspace interaction selectAdjacentTile offset=\(offset) transition=\(String(describing: transition)) fromWorkspace=\(previousWorkspaceID.uuidString) fromTile=\(previousTileID?.uuidString ?? "none") resolvedWorkspace=\(store.selectedWorkspaceID.uuidString) resolvedTile=\(store.selectedTileID?.uuidString ?? "none")"
        )

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
                kind: .columnOpen,
                animated: transition == .animatedReveal
            )
            nextTransitionID += 1
        }
        publishTransition(for: tile.id, transition: transition)
        return tile
    }

    @discardableResult
    func splitTerminalTile(
        _ tileID: UUID,
        workingDirectory: String? = nil,
        sessionID: UUID,
        transition: TileTransition = .preserveViewport
    ) -> WorkspaceStore.Tile? {
        guard let tile = store.splitTerminalTile(tileID, workingDirectory: workingDirectory, sessionID: sessionID) else {
            return nil
        }
        if transition != .preserveViewport {
            tileOpenAnimation = TileOpenAnimation(
                id: nextTransitionID,
                tileID: tile.id,
                kind: .verticalSplit(sourceTileID: tileID),
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
        TairiLog.write(
            "workspace interaction revealSelection tile=\(tileID.uuidString) transition=\(String(describing: transition)) selectedWorkspace=\(store.selectedWorkspaceID.uuidString)"
        )
        publishTransition(for: tileID, transition: transition)
    }

    func revealWorkspace(_ workspaceID: UUID, animated: Bool = true) {
        TairiLog.write(
            "workspace interaction revealWorkspace workspace=\(workspaceID.uuidString) animated=\(animated) selectedWorkspace=\(store.selectedWorkspaceID.uuidString) selectedTile=\(store.selectedTileID?.uuidString ?? "none")"
        )
        workspaceRevealRequest = WorkspaceRevealRequest(
            id: nextTransitionID,
            workspaceID: workspaceID,
            animated: animated
        )
        nextTransitionID += 1
    }

    func zoomOutCanvas() {
        guard canvasZoomMode != .overview else { return }
        canvasZoomMode = .overview
    }

    func zoomInOnSelection(transition: TileTransition = .animatedReveal) {
        canvasZoomMode = .focused
        guard let selectedTileID = store.selectedTileID else { return }
        publishTransition(for: selectedTileID, transition: transition)
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
        if transition != .preserveViewport, canvasZoomMode == .overview {
            canvasZoomMode = .focused
        }

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
        TairiLog.write(
            "workspace interaction publishTransition id=\(nextTransitionID) tile=\(tileID.uuidString) transition=\(String(describing: transition)) zoomMode=\(String(describing: canvasZoomMode))"
        )
        nextTransitionID += 1
    }
}
