import AppKit

@MainActor
extension WorkspaceCanvasDocumentView {
    func canBeginTileReorderDrag(for tileID: UUID) -> Bool {
        zoomMode != .overview && tileViews[tileID] != nil
    }

    func beginTileReorderDrag(_ tileID: UUID) {
        guard canBeginTileReorderDrag(for: tileID) else { return }
        activeTileReorderDragTileID = tileID
        hoveredTileReorderTargetTileID = nil
        needsLayout = true
    }

    func endTileReorderDrag(_ tileID: UUID) {
        guard activeTileReorderDragTileID == tileID else { return }
        activeTileReorderDragTileID = nil
        hoveredTileReorderTargetTileID = nil
        needsLayout = true
    }

    func setKeyboardTileReorderArmed(_ armed: Bool) {
        let nextValue = armed && selectedTileID != nil && zoomMode != .overview
        guard keyboardTileReorderArmed != nextValue else { return }
        keyboardTileReorderArmed = nextValue
        if !nextValue {
            hoveredTileReorderTargetTileID = nil
        }
        needsLayout = true
    }

    func handleKeyboardTileReorder(
        _ direction: TileReorderDirection,
        from tileID: UUID
    ) -> Bool {
        guard zoomMode != .overview,
            let targetTileID = neighboringTileID(for: tileID, direction: direction)
        else {
            return false
        }

        let didSwap = swapTileSlots(
            tileID,
            with: targetTileID,
            animated: true,
            revealMovedTile: true
        )
        if didSwap {
            runtime.focusSurface(tileID: tileID)
        }
        return didSwap
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateTileReorderHover(using: sender) ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateTileReorderHover(using: sender) ? .move : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hoveredTileReorderTargetTileID = nil
        needsLayout = true
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        tileReorderDropTarget(using: sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            hoveredTileReorderTargetTileID = nil
            needsLayout = true
        }

        guard let draggedTileID = draggedTileID(from: sender),
            let targetTileID = tileReorderDropTarget(using: sender)
        else {
            return false
        }

        return swapTileSlots(draggedTileID, with: targetTileID, animated: true)
    }

    private func swapTileSlots(
        _ tileID: UUID,
        with targetTileID: UUID,
        animated: Bool,
        revealMovedTile: Bool = false
    ) -> Bool {
        guard tileID != targetTileID else { return false }

        var startFrames: [UUID: CGRect] = [:]
        if let frame = tileViews[tileID]?.frame, !frame.isEmpty {
            startFrames[tileID] = frame
        }
        if let frame = tileViews[targetTileID]?.frame, !frame.isEmpty {
            startFrames[targetTileID] = frame
        }

        guard store.swapTileLayoutSlots(tileID, with: targetTileID) else { return false }
        store.selectTile(tileID)

        workspaces = store.workspaces
        selectedWorkspaceID = store.selectedWorkspaceID
        selectedTileID = store.selectedTileID
        if !startFrames.isEmpty {
            animator.queueTileReorder(
                tileIDs: Set(startFrames.keys),
                startFrames: startFrames,
                animated: animated
            )
        }
        if revealMovedTile {
            revealTile(tileID, animated: animated)
            workspaces = store.workspaces
            selectedWorkspaceID = store.selectedWorkspaceID
            selectedTileID = store.selectedTileID
        }
        needsLayout = true
        return true
    }

    private func updateTileReorderHover(using draggingInfo: NSDraggingInfo) -> Bool {
        let targetTileID = tileReorderDropTarget(using: draggingInfo)
        if hoveredTileReorderTargetTileID != targetTileID {
            hoveredTileReorderTargetTileID = targetTileID
            needsLayout = true
        }
        return targetTileID != nil
    }

    private func tileReorderDropTarget(using draggingInfo: NSDraggingInfo) -> UUID? {
        guard zoomMode != .overview,
            let draggedTileID = draggedTileID(from: draggingInfo),
            let sourceWorkspaceID = store.workspaceID(containing: draggedTileID)
        else {
            return nil
        }

        let localPoint = convert(draggingInfo.draggingLocation, from: nil)
        return tileID(
            at: localPoint,
            in: sourceWorkspaceID,
            excluding: draggedTileID
        )
    }

    private func draggedTileID(from draggingInfo: NSDraggingInfo) -> UUID? {
        let pasteboard = draggingInfo.draggingPasteboard
        guard let rawValue = pasteboard.string(forType: workspaceTileDragType) else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }

    private func tileID(
        at point: NSPoint,
        in workspaceID: UUID,
        excluding excludedTileID: UUID?
    ) -> UUID? {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return nil }

        return workspace.tiles
            .map(\.id)
            .filter { $0 != excludedTileID }
            .first { tileID in
                guard let frame = tileViews[tileID]?.frame else { return false }
                return frame.insetBy(dx: -10, dy: -10).contains(point)
            }
    }

    private func neighboringTileID(
        for tileID: UUID,
        direction: TileReorderDirection
    ) -> UUID? {
        guard let workspaceID = store.workspaceID(containing: tileID),
            let workspace = workspaces.first(where: { $0.id == workspaceID })
        else {
            return nil
        }

        let frames = logicalTileFrames(in: workspace)
        guard let sourceFrame = frames[tileID] else {
            return nil
        }

        let sourceMidX = sourceFrame.midX
        let sourceMidY = sourceFrame.midY

        return workspace.tiles
            .map(\.id)
            .filter { $0 != tileID }
            .compactMap { candidateID -> (tileID: UUID, primary: CGFloat, secondary: CGFloat)? in
                guard let candidateFrame = frames[candidateID] else { return nil }
                let deltaX = candidateFrame.midX - sourceMidX
                let deltaY = candidateFrame.midY - sourceMidY

                let primaryDistance: CGFloat
                let secondaryDistance: CGFloat

                switch direction {
                case .up:
                    guard deltaY < -0.5 else { return nil }
                    primaryDistance = -deltaY
                    secondaryDistance = abs(deltaX)
                case .down:
                    guard deltaY > 0.5 else { return nil }
                    primaryDistance = deltaY
                    secondaryDistance = abs(deltaX)
                case .left:
                    guard deltaX < -0.5 else { return nil }
                    primaryDistance = -deltaX
                    secondaryDistance = abs(deltaY)
                case .right:
                    guard deltaX > 0.5 else { return nil }
                    primaryDistance = deltaX
                    secondaryDistance = abs(deltaY)
                }

                return (candidateID, primaryDistance, secondaryDistance)
            }
            .min { lhs, rhs in
                if abs(lhs.primary - rhs.primary) > 0.5 {
                    return lhs.primary < rhs.primary
                }
                if abs(lhs.secondary - rhs.secondary) > 0.5 {
                    return lhs.secondary < rhs.secondary
                }
                return lhs.tileID.uuidString < rhs.tileID.uuidString
            }?
            .tileID
    }

    private func logicalTileFrames(in workspace: WorkspaceStore.Workspace) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        var originX: CGFloat = 0

        for column in WorkspaceColumnLayout.columns(in: workspace) {
            frames.merge(
                WorkspaceColumnLayout.columnTileFrames(
                    for: column,
                    originX: originX,
                    originY: 0,
                    width: column.width,
                    height: baseTileHeight()
                ),
                uniquingKeysWith: { _, new in new }
            )
            originX += column.width + WorkspaceCanvasLayoutMetrics.tileSpacing
        }

        return frames
    }
}
