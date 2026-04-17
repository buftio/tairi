import Foundation

struct WorkspaceTileMove: Equatable {
    let targetTileID: UUID
    let direction: TileReorderDirection
}

@MainActor
extension WorkspaceStore {
    func previewWorkspaceMovingTile(
        _ tileID: UUID,
        to move: WorkspaceTileMove
    ) -> Workspace? {
        guard tileID != move.targetTileID,
            let workspaceIndex = workspaces.firstIndex(where: { workspace in
                workspace.tiles.contains(where: { $0.id == tileID })
                    && workspace.tiles.contains(where: { $0.id == move.targetTileID })
            })
        else {
            return nil
        }

        return workspaceApplyingTileMove(
            workspaces[workspaceIndex],
            moving: tileID,
            to: move
        )
    }

    @discardableResult
    func moveTile(
        _ tileID: UUID,
        to move: WorkspaceTileMove
    ) -> Bool {
        guard tileID != move.targetTileID,
            let workspaceIndex = workspaces.firstIndex(where: { workspace in
                workspace.tiles.contains(where: { $0.id == tileID })
                    && workspace.tiles.contains(where: { $0.id == move.targetTileID })
            }),
            let updatedWorkspace = workspaceApplyingTileMove(
                workspaces[workspaceIndex],
                moving: tileID,
                to: move
            )
        else {
            return false
        }

        replaceWorkspace(at: workspaceIndex, with: updatedWorkspace)
        return true
    }

    private func workspaceApplyingTileMove(
        _ workspace: Workspace,
        moving tileID: UUID,
        to move: WorkspaceTileMove
    ) -> Workspace? {
        var columns = WorkspaceColumnLayout.columns(in: workspace).map {
            TileMoveColumn(tiles: $0.tiles)
        }
        let originalTileIDs = workspace.tiles.map(\.id)

        guard let sourceLocation = tileLocation(of: tileID, in: columns) else {
            return nil
        }

        var movedTile = columns[sourceLocation.columnIndex].tiles.remove(at: sourceLocation.tileIndex)
        if columns[sourceLocation.columnIndex].tiles.isEmpty {
            columns.remove(at: sourceLocation.columnIndex)
        }

        guard let targetLocation = tileLocation(of: move.targetTileID, in: columns) else {
            return nil
        }

        switch move.direction {
        case .left:
            columns.insert(TileMoveColumn(id: UUID(), tiles: [movedTile]), at: targetLocation.columnIndex)
        case .right:
            columns.insert(TileMoveColumn(id: UUID(), tiles: [movedTile]), at: targetLocation.columnIndex + 1)
        case .up:
            let columnWidth = columns[targetLocation.columnIndex].tiles.first?.width ?? movedTile.width
            movedTile.width = columnWidth
            columns[targetLocation.columnIndex].tiles.insert(movedTile, at: targetLocation.tileIndex)
        case .down:
            let columnWidth = columns[targetLocation.columnIndex].tiles.first?.width ?? movedTile.width
            movedTile.width = columnWidth
            columns[targetLocation.columnIndex].tiles.insert(movedTile, at: targetLocation.tileIndex + 1)
        }

        let rebuiltWorkspace = rebuildWorkspace(workspace, from: columns)
        guard
            rebuiltWorkspace.tiles.map(\.id) != originalTileIDs
                || rebuiltWorkspace.tiles.map(\.columnID) != workspace.tiles.map(\.columnID)
                || rebuiltWorkspace.tiles.map(\.width) != workspace.tiles.map(\.width)
        else {
            return nil
        }

        return rebuiltWorkspace
    }

    private func rebuildWorkspace(
        _ workspace: Workspace,
        from columns: [TileMoveColumn]
    ) -> Workspace {
        var rebuiltWorkspace = workspace
        rebuiltWorkspace.tiles = columns.flatMap { column -> [Tile] in
            let columnID = column.id ?? column.tiles.first?.columnID ?? UUID()
            let columnWidth = column.tiles.first?.width ?? WidthPreset.standard.width
            return column.tiles.map { tile in
                var rebuiltTile = tile
                rebuiltTile.columnID = columnID
                rebuiltTile.width = columnWidth
                return rebuiltTile
            }
        }
        return rebuiltWorkspace
    }

    private func tileLocation(
        of tileID: UUID,
        in columns: [TileMoveColumn]
    ) -> TileMoveLocation? {
        for (columnIndex, column) in columns.enumerated() {
            if let tileIndex = column.tiles.firstIndex(where: { $0.id == tileID }) {
                return TileMoveLocation(columnIndex: columnIndex, tileIndex: tileIndex)
            }
        }
        return nil
    }
}

private struct TileMoveColumn {
    var id: UUID?
    var tiles: [WorkspaceStore.Tile]
}

private struct TileMoveLocation {
    let columnIndex: Int
    let tileIndex: Int
}
