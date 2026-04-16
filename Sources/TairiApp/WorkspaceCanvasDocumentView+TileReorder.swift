import AppKit

@MainActor
extension WorkspaceCanvasDocumentView {
    struct TileReorderSession {
        let tileID: UUID
        let workspaceID: UUID
        let initialPointerLocation: CGPoint
        let currentPointerLocation: CGPoint
        let initialTileFrame: CGRect
        let draggedFrame: CGRect
        let move: WorkspaceTileMove?
        let previewWorkspace: WorkspaceStore.Workspace?
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
        tileReorderSession = TileReorderSession(
            tileID: tileID,
            workspaceID: workspaceID,
            initialPointerLocation: localPoint,
            currentPointerLocation: localPoint,
            initialTileFrame: initialTileFrame,
            draggedFrame: initialTileFrame,
            move: nil,
            previewWorkspace: nil
        )
        needsLayout = true
    }

    func updateTileReorderDrag(windowLocation: CGPoint) {
        guard let tileReorderSession else { return }

        let localPoint = convert(windowLocation, from: nil)
        let draggedFrame = frameForDraggedTile(
            initialFrame: tileReorderSession.initialTileFrame,
            initialPointerLocation: tileReorderSession.initialPointerLocation,
            currentPointerLocation: localPoint
        )
        let move = tileMove(at: localPoint, for: tileReorderSession)
        let previewWorkspace = move.flatMap { store.previewWorkspaceMovingTile(tileReorderSession.tileID, to: $0) }

        self.tileReorderSession = TileReorderSession(
            tileID: tileReorderSession.tileID,
            workspaceID: tileReorderSession.workspaceID,
            initialPointerLocation: tileReorderSession.initialPointerLocation,
            currentPointerLocation: localPoint,
            initialTileFrame: tileReorderSession.initialTileFrame,
            draggedFrame: draggedFrame,
            move: move,
            previewWorkspace: previewWorkspace
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

    func handleKeyboardTileReorder(
        _ direction: TileReorderDirection,
        from tileID: UUID
    ) -> Bool {
        guard zoomMode != .overview,
            let targetTileID = neighboringTileID(for: tileID, direction: direction)
        else {
            return false
        }

        let didMove = commitTileMove(
            tileID,
            to: WorkspaceTileMove(targetTileID: targetTileID, direction: direction),
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

        guard store.moveTile(tileID, to: move) else { return false }
        if selectMovedTile {
            store.selectTile(tileID)
        }

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

    private func tileMove(
        at point: NSPoint,
        for session: TileReorderSession
    ) -> WorkspaceTileMove? {
        if let extractionMove = splitColumnExtractionMove(at: point, for: session) {
            return extractionMove
        }

        let workspace =
            session.previewWorkspace
            ?? workspaces.first(where: { $0.id == session.workspaceID })
        guard let workspace else { return nil }

        let candidate = workspace.tiles
            .filter { $0.id != session.tileID }
            .compactMap { tile -> (tileID: UUID, frame: CGRect, distance: CGFloat)? in
                guard let frame = tileViews[tile.id]?.frame else { return nil }
                return (
                    tile.id,
                    frame,
                    distanceFrom(point, to: frame)
                )
            }
            .min { lhs, rhs in
                if abs(lhs.distance - rhs.distance) > 0.5 {
                    return lhs.distance < rhs.distance
                }
                return lhs.tileID.uuidString < rhs.tileID.uuidString
            }

        guard let candidate else { return nil }

        return WorkspaceTileMove(
            targetTileID: candidate.tileID,
            direction: moveDirection(for: point, in: candidate.frame)
        )
    }

    private func splitColumnExtractionMove(
        at point: NSPoint,
        for session: TileReorderSession
    ) -> WorkspaceTileMove? {
        guard let workspace = workspaces.first(where: { $0.id == session.workspaceID }) else {
            return nil
        }

        let columns = WorkspaceColumnLayout.columns(in: workspace)
        guard let sourceColumn = columns.first(where: { column in
            column.tiles.contains(where: { $0.id == session.tileID })
        }), sourceColumn.tiles.count > 1
        else {
            return nil
        }

        let horizontalDelta = point.x - session.initialPointerLocation.x
        let threshold = min(max(session.initialTileFrame.width * 0.16, 72), 140)
        guard abs(horizontalDelta) >= threshold else { return nil }

        let targetTile = sourceColumn.tiles
            .filter { $0.id != session.tileID }
            .min { lhs, rhs in
                guard let lhsFrame = tileViews[lhs.id]?.frame,
                    let rhsFrame = tileViews[rhs.id]?.frame
                else {
                    return lhs.id.uuidString < rhs.id.uuidString
                }

                let lhsDistance = abs(lhsFrame.midY - session.initialTileFrame.midY)
                let rhsDistance = abs(rhsFrame.midY - session.initialTileFrame.midY)
                if abs(lhsDistance - rhsDistance) > 0.5 {
                    return lhsDistance < rhsDistance
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        guard let targetTile else { return nil }

        return WorkspaceTileMove(
            targetTileID: targetTile.id,
            direction: horizontalDelta < 0 ? .left : .right
        )
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

    private func frameForDraggedTile(
        initialFrame: CGRect,
        initialPointerLocation: CGPoint,
        currentPointerLocation: CGPoint
    ) -> CGRect {
        initialFrame.offsetBy(
            dx: currentPointerLocation.x - initialPointerLocation.x,
            dy: currentPointerLocation.y - initialPointerLocation.y
        )
    }

    private func moveDirection(for point: CGPoint, in frame: CGRect) -> TileReorderDirection {
        let horizontalRatio = abs(point.x - frame.midX) / max(frame.width / 2, 1)
        let verticalRatio = abs(point.y - frame.midY) / max(frame.height / 2, 1)

        if horizontalRatio > verticalRatio {
            return point.x < frame.midX ? .left : .right
        }

        return point.y < frame.midY ? .up : .down
    }

    private func distanceFrom(_ point: CGPoint, to frame: CGRect) -> CGFloat {
        if frame.insetBy(dx: -10, dy: -10).contains(point) {
            return 0
        }

        let dx = max(max(frame.minX - point.x, 0), point.x - frame.maxX)
        let dy = max(max(frame.minY - point.y, 0), point.y - frame.maxY)
        return hypot(dx, dy)
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
}
