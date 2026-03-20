import AppKit

enum WorkspaceColumnLayout {
    static func columns(in workspace: WorkspaceStore.Workspace) -> [WorkspaceStore.Column] {
        var result: [WorkspaceStore.Column] = []

        for tile in workspace.tiles {
            if let lastIndex = result.indices.last, result[lastIndex].id == tile.columnID {
                result[lastIndex].tiles.append(tile)
            } else {
                result.append(WorkspaceStore.Column(id: tile.columnID, tiles: [tile]))
            }
        }

        return result
    }

    static func rawTileSpan(for workspace: WorkspaceStore.Workspace) -> CGFloat {
        let columns = columns(in: workspace)
        let tileWidths = columns.reduce(CGFloat.zero) { partialResult, column in
            partialResult + column.width
        }
        let spacing = CGFloat(max(columns.count - 1, 0)) * WorkspaceCanvasLayoutMetrics.tileSpacing
        return tileWidths + spacing
    }

    static func contentWidth(
        for workspace: WorkspaceStore.Workspace,
        stripLeadingInset: CGFloat
    ) -> CGFloat {
        let columns = columns(in: workspace)
        guard !columns.isEmpty else { return 0 }

        return stripLeadingInset
            + (WorkspaceCanvasLayoutMetrics.horizontalPadding * 2)
            + rawTileSpan(for: workspace)
    }

    static func tileFrame(
        for tileID: UUID,
        in workspace: WorkspaceStore.Workspace,
        stripLeadingInset: CGFloat,
        availableHeight: CGFloat
    ) -> CGRect? {
        var x = stripLeadingInset + WorkspaceCanvasLayoutMetrics.horizontalPadding

        for column in columns(in: workspace) {
            let columnFrames = columnTileFrames(
                for: column,
                originX: x,
                originY: 0,
                width: column.width,
                height: availableHeight
            )

            if let frame = columnFrames[tileID] {
                return frame
            }

            x += column.width + WorkspaceCanvasLayoutMetrics.tileSpacing
        }

        return nil
    }

    static func columnTileFrames(
        for column: WorkspaceStore.Column,
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> [UUID: CGRect] {
        let totalSpacing = CGFloat(max(column.tiles.count - 1, 0)) * WorkspaceCanvasLayoutMetrics.tileSpacing
        let totalWeight = max(column.tiles.reduce(CGFloat.zero) { $0 + $1.heightWeight }, 0.0001)
        let usableHeight = max(height - totalSpacing, 1)
        var y = originY
        var frames: [UUID: CGRect] = [:]

        for (index, tile) in column.tiles.enumerated() {
            let remainingHeight = (originY + height) - y
                - (CGFloat(max(column.tiles.count - index - 1, 0)) * WorkspaceCanvasLayoutMetrics.tileSpacing)
            let tileHeight: CGFloat
            if index == column.tiles.count - 1 {
                tileHeight = max(remainingHeight, 1)
            } else {
                tileHeight = max((usableHeight * tile.heightWeight / totalWeight).rounded(.down), 1)
            }

            frames[tile.id] = CGRect(x: originX, y: y, width: width, height: tileHeight)
            y += tileHeight + WorkspaceCanvasLayoutMetrics.tileSpacing
        }

        return frames
    }
}
