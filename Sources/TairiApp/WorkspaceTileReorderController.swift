import AppKit

@MainActor
final class WorkspaceTileReorderController {
    struct Session {
        let tileID: UUID
        let workspaceID: UUID
        let initialPointerLocation: CGPoint
        let currentPointerLocation: CGPoint
        let initialTileFrame: CGRect
        let draggedFrame: CGRect
        let move: WorkspaceTileMove?
        let previewWorkspace: WorkspaceStore.Workspace?
    }

    private let store: WorkspaceStore

    init(store: WorkspaceStore) {
        self.store = store
    }

    func beginSession(
        tileID: UUID,
        workspaceID: UUID,
        initialPointerLocation: CGPoint,
        initialTileFrame: CGRect
    ) -> Session {
        Session(
            tileID: tileID,
            workspaceID: workspaceID,
            initialPointerLocation: initialPointerLocation,
            currentPointerLocation: initialPointerLocation,
            initialTileFrame: initialTileFrame,
            draggedFrame: initialTileFrame,
            move: nil,
            previewWorkspace: nil
        )
    }

    func updateSession(
        _ session: Session,
        currentPointerLocation: CGPoint,
        workspaces: [WorkspaceStore.Workspace],
        tileFrames: [UUID: CGRect]
    ) -> Session {
        let draggedFrame = session.initialTileFrame.offsetBy(
            dx: currentPointerLocation.x - session.initialPointerLocation.x,
            dy: currentPointerLocation.y - session.initialPointerLocation.y
        )
        let move = moveForDrag(
            at: currentPointerLocation,
            session: session,
            workspaces: workspaces,
            tileFrames: tileFrames
        )
        let previewWorkspace = move.flatMap { store.previewWorkspaceMovingTile(session.tileID, to: $0) }

        return Session(
            tileID: session.tileID,
            workspaceID: session.workspaceID,
            initialPointerLocation: session.initialPointerLocation,
            currentPointerLocation: currentPointerLocation,
            initialTileFrame: session.initialTileFrame,
            draggedFrame: draggedFrame,
            move: move,
            previewWorkspace: previewWorkspace
        )
    }

    func keyboardMove(
        for tileID: UUID,
        direction: TileReorderDirection,
        in workspaces: [WorkspaceStore.Workspace],
        tileHeight: CGFloat
    ) -> WorkspaceTileMove? {
        guard let workspaceID = store.workspaceID(containing: tileID),
            let workspace = workspaces.first(where: { $0.id == workspaceID }),
            let targetTileID = neighboringTileID(
                for: tileID,
                direction: direction,
                in: workspace,
                tileHeight: tileHeight
            )
        else {
            return nil
        }

        return WorkspaceTileMove(targetTileID: targetTileID, direction: direction)
    }

    private func moveForDrag(
        at point: CGPoint,
        session: Session,
        workspaces: [WorkspaceStore.Workspace],
        tileFrames: [UUID: CGRect]
    ) -> WorkspaceTileMove? {
        if let extractionMove = splitColumnExtractionMove(
            at: point,
            session: session,
            workspaces: workspaces,
            tileFrames: tileFrames
        ) {
            return extractionMove
        }

        let workspace = session.previewWorkspace ?? workspaces.first(where: { $0.id == session.workspaceID })
        guard let workspace else { return nil }

        let candidate = workspace.tiles
            .filter { $0.id != session.tileID }
            .compactMap { tile -> (tileID: UUID, frame: CGRect, distance: CGFloat)? in
                guard let frame = tileFrames[tile.id] else { return nil }
                return (tile.id, frame, distance(from: point, to: frame))
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
        at point: CGPoint,
        session: Session,
        workspaces: [WorkspaceStore.Workspace],
        tileFrames: [UUID: CGRect]
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
                guard let lhsFrame = tileFrames[lhs.id],
                    let rhsFrame = tileFrames[rhs.id]
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
        direction: TileReorderDirection,
        in workspace: WorkspaceStore.Workspace,
        tileHeight: CGFloat
    ) -> UUID? {
        let frames = logicalTileFrames(in: workspace, tileHeight: tileHeight)
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

    private func logicalTileFrames(
        in workspace: WorkspaceStore.Workspace,
        tileHeight: CGFloat
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

    private func moveDirection(
        for point: CGPoint,
        in frame: CGRect
    ) -> TileReorderDirection {
        let horizontalRatio = abs(point.x - frame.midX) / max(frame.width / 2, 1)
        let verticalRatio = abs(point.y - frame.midY) / max(frame.height / 2, 1)

        if horizontalRatio > verticalRatio {
            return point.x < frame.midX ? .left : .right
        }

        return point.y < frame.midY ? .up : .down
    }

    private func distance(
        from point: CGPoint,
        to frame: CGRect
    ) -> CGFloat {
        if frame.insetBy(dx: -10, dy: -10).contains(point) {
            return 0
        }

        let dx = max(max(frame.minX - point.x, 0), point.x - frame.maxX)
        let dy = max(max(frame.minY - point.y, 0), point.y - frame.maxY)
        return hypot(dx, dy)
    }
}
