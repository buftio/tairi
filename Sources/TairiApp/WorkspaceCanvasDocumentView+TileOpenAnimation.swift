import AppKit

@MainActor
extension WorkspaceCanvasDocumentView {
    struct VerticalSplitOpenAnimation {
        let tileID: UUID
        let startFrames: [UUID: CGRect]
    }

    func queueVerticalSplitOpenAnimation(
        tileID: UUID,
        sourceTileID: UUID,
        animated: Bool
    ) {
        guard animated,
              let workspace = workspaces.first(where: { workspace in
                  workspace.tiles.contains(where: { $0.id == tileID })
              }),
              let newTile = workspace.tiles.first(where: { $0.id == tileID }),
              let sourceTile = workspace.tiles.first(where: { $0.id == sourceTileID }),
              newTile.columnID == sourceTile.columnID,
              let sourceFrame = tileViews[sourceTileID]?.frame,
              !sourceFrame.isEmpty else {
            verticalSplitOpenAnimation = nil
            animator.queueOpeningTile(
                tileID: tileID,
                animated: false,
                style: .verticalSplit
            )
            return
        }

        let columnTileIDs = workspace.tiles
            .filter { $0.columnID == sourceTile.columnID }
            .map(\.id)
        var startFrames: [UUID: CGRect] = [:]

        for columnTileID in columnTileIDs {
            if columnTileID == tileID {
                startFrames[columnTileID] = CGRect(
                    x: sourceFrame.minX,
                    y: sourceFrame.maxY + WorkspaceCanvasLayoutMetrics.tileSpacing,
                    width: sourceFrame.width,
                    height: 0
                )
                continue
            }

            if let frame = tileViews[columnTileID]?.frame, !frame.isEmpty {
                startFrames[columnTileID] = frame
            }
        }

        guard startFrames[sourceTileID] != nil, startFrames[tileID] != nil else {
            verticalSplitOpenAnimation = nil
            animator.queueOpeningTile(
                tileID: tileID,
                animated: false,
                style: .verticalSplit
            )
            return
        }

        verticalSplitOpenAnimation = VerticalSplitOpenAnimation(
            tileID: tileID,
            startFrames: startFrames
        )
        animator.queueOpeningTile(
            tileID: tileID,
            animated: true,
            style: .verticalSplit
        )
    }

    func effectiveFocusedFrame(for tileID: UUID, targetFrame: CGRect) -> CGRect {
        guard let animation = verticalSplitOpenAnimation else {
            return targetFrame
        }

        guard let progress = animator.openingTileProgress(
            for: animation.tileID,
            style: .verticalSplit
        ) else {
            verticalSplitOpenAnimation = nil
            return targetFrame
        }

        guard progress < 0.999 else {
            verticalSplitOpenAnimation = nil
            return targetFrame
        }

        guard let startFrame = animation.startFrames[tileID] else {
            return targetFrame
        }

        return CGRect(
            x: interpolatedValue(from: startFrame.minX, to: targetFrame.minX, progress: progress),
            y: interpolatedValue(from: startFrame.minY, to: targetFrame.minY, progress: progress),
            width: interpolatedValue(from: startFrame.width, to: targetFrame.width, progress: progress),
            height: interpolatedValue(from: startFrame.height, to: targetFrame.height, progress: progress)
        )
    }

    func pruneVerticalSplitOpenAnimation(using allTileIDs: Set<UUID>) {
        guard let animation = verticalSplitOpenAnimation else { return }
        let activeTileIDs = Set(animation.startFrames.keys).union([animation.tileID])
        guard activeTileIDs.isSubset(of: allTileIDs) else {
            verticalSplitOpenAnimation = nil
            return
        }
    }

    private func interpolatedValue(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }
}
