import AppKit

@MainActor
extension WorkspaceCanvasDocumentView {
    enum TileReorderShortcutSource {
        case surface(attachedTileID: UUID?)
        case tileHost(UUID)
        case container(preferredTileID: UUID?)
    }

    func canBeginTileReorderDrag(for tileID: UUID) -> Bool {
        zoomMode != .overview && tileViews[tileID] != nil
    }

    func beginTileReorderDrag(_ tileID: UUID, windowLocation: CGPoint) {
        guard canBeginTileReorderDrag(for: tileID),
            let workspaceID = store.workspaceID(containing: tileID),
            let initialTileFrame = tileViews[tileID]?.frame
        else {
            return
        }

        let localPoint = convert(windowLocation, from: nil)
        tileReorderSession = tileReorderController.beginSession(
            tileID: tileID,
            workspaceID: workspaceID,
            initialPointerLocation: localPoint,
            initialTileFrame: initialTileFrame
        )
        needsLayout = true
    }

    func updateTileReorderDrag(windowLocation: CGPoint) {
        guard let tileReorderSession else { return }

        let localPoint = convert(windowLocation, from: nil)
        self.tileReorderSession = tileReorderController.updateSession(
            tileReorderSession,
            currentPointerLocation: localPoint,
            workspaces: workspaces,
            tileFrames: currentTileFrames()
        )
        needsLayout = true
    }

    func endTileReorderDrag(_ tileID: UUID, windowLocation: CGPoint) {
        guard let tileReorderSession,
            tileReorderSession.tileID == tileID
        else {
            return
        }

        updateTileReorderDrag(windowLocation: windowLocation)
        commitTileMove(tileID)
        self.tileReorderSession = nil
        needsLayout = true
    }

    func handleTileReorderShortcut(
        _ event: NSEvent,
        source: TileReorderShortcutSource
    ) -> Bool {
        guard let direction = TairiHotkeys.tileReorderDirection(for: event),
            let tileID = tileReorderSourceTileID(for: source)
        else {
            return false
        }

        return handleKeyboardTileReorder(direction, from: tileID)
    }

    func handleKeyboardTileReorder(
        _ direction: TileReorderDirection,
        from tileID: UUID
    ) -> Bool {
        guard zoomMode != .overview,
            let move = tileReorderController.keyboardMove(
                for: tileID,
                direction: direction,
                in: workspaces,
                tileHeight: baseTileHeight()
            )
        else {
            return false
        }

        let didMove = commitTileMove(
            tileID,
            to: move,
            animated: true,
            revealMovedTile: true,
            selectMovedTile: true
        )
        if didMove {
            runtime.focusSurface(tileID: tileID)
        }
        return didMove
    }

    private func commitTileMove(
        _ tileID: UUID,
        to move: WorkspaceTileMove,
        animated: Bool,
        revealMovedTile: Bool = false,
        selectMovedTile: Bool = false
    ) -> Bool {
        guard tileID != move.targetTileID else { return false }

        let startFrames = captureTileMoveStartFrames(for: tileID)
        guard applyTileMove(move, to: tileID, selectMovedTile: selectMovedTile) else { return false }

        syncDocumentSelectionFromStore()
        queueTileMoveAnimation(startFrames: startFrames, animated: animated)
        finishCommittedTileMove(tileID: tileID, animated: animated, revealMovedTile: revealMovedTile)
        return true
    }

    private func commitTileMove(_ tileID: UUID) {
        guard let tileReorderSession,
            tileReorderSession.tileID == tileID,
            let move = tileReorderSession.move
        else {
            return
        }

        _ = commitTileMove(
            tileID,
            to: move,
            animated: true,
            revealMovedTile: false,
            selectMovedTile: false
        )
    }

    private func captureTileMoveStartFrames(for tileID: UUID) -> [UUID: CGRect] {
        var startFrames: [UUID: CGRect] = [:]

        if let workspaceID = store.workspaceID(containing: tileID),
            let workspace = workspaces.first(where: { $0.id == workspaceID })
        {
            for tile in workspace.tiles {
                if let frame = tileViews[tile.id]?.frame, !frame.isEmpty {
                    startFrames[tile.id] = frame
                }
            }
        }

        if let tileReorderSession,
            tileReorderSession.tileID == tileID
        {
            startFrames[tileID] = tileReorderSession.draggedFrame
        }

        return startFrames
    }

    private func applyTileMove(
        _ move: WorkspaceTileMove,
        to tileID: UUID,
        selectMovedTile: Bool
    ) -> Bool {
        guard store.moveTile(tileID, to: move) else { return false }
        if selectMovedTile {
            store.selectTile(tileID)
        }
        return true
    }

    private func syncDocumentSelectionFromStore() {
        workspaces = store.workspaces
        selectedWorkspaceID = store.selectedWorkspaceID
        selectedTileID = store.selectedTileID
    }

    private func queueTileMoveAnimation(
        startFrames: [UUID: CGRect],
        animated: Bool
    ) {
        guard !startFrames.isEmpty else { return }
        animator.queueTileReorder(
            tileIDs: Set(startFrames.keys),
            startFrames: startFrames,
            animated: animated
        )
    }

    private func finishCommittedTileMove(
        tileID: UUID,
        animated: Bool,
        revealMovedTile: Bool
    ) {
        if revealMovedTile {
            revealTile(tileID, animated: animated)
            syncDocumentSelectionFromStore()
        }
        needsLayout = true
    }

    private func currentTileFrames() -> [UUID: CGRect] {
        tileViews.reduce(into: [UUID: CGRect]()) { frames, entry in
            let (tileID, view) = entry
            let frame = view.frame
            guard !frame.isEmpty else { return }
            frames[tileID] = frame
        }
    }

    private func tileReorderSourceTileID(for source: TileReorderShortcutSource) -> UUID? {
        switch source {
        case .surface(let attachedTileID):
            return GhosttySurfaceView.reorderTileID(
                attachedTileID: attachedTileID,
                selectedTileID: selectedTileID
            )
        case .tileHost(let tileID):
            return tileID
        case .container(let preferredTileID):
            if let focusedTileID = focusedTileHostID() {
                return focusedTileID
            }
            return selectedTileID ?? preferredTileID
        }
    }

    private func focusedTileHostID() -> UUID? {
        guard let firstResponderView = window?.firstResponder as? NSView else {
            return nil
        }

        var ancestor: NSView? = firstResponderView
        while let view = ancestor {
            if let tileHostView = view as? WorkspaceTileHostView {
                return tileHostView.representedTileID
            }
            if view === self {
                break
            }
            ancestor = view.superview
        }

        return nil
    }
}
