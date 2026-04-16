import AppKit
import SwiftUI

struct WorkspaceCanvasView: NSViewRepresentable {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var interactionController: WorkspaceInteractionController
    @ObservedObject var runtime: GhosttyRuntime
    let sidebarHidden: Bool
    let renderedStripLeadingInset: CGFloat

    func makeNSView(context: Context) -> WorkspaceCanvasContainerView {
        WorkspaceCanvasContainerView(
            settings: settings,
            store: store,
            interactionController: interactionController,
            runtime: runtime
        )
    }

    func updateNSView(_ nsView: WorkspaceCanvasContainerView, context: Context) {
        let allTileIDs = Set(store.workspaces.flatMap(\.tiles).map(\.id))
        nsView.update(
            workspaces: store.workspaces,
            selectedWorkspaceID: store.selectedWorkspaceID,
            selectedTileID: store.selectedTileID,
            allTileIDs: allTileIDs,
            canvasTransition: interactionController.canvasTransition,
            workspaceRevealRequest: interactionController.workspaceRevealRequest,
            canvasZoomMode: interactionController.canvasZoomMode,
            tileCloseAnimation: interactionController.tileCloseAnimation,
            tileOpenAnimation: interactionController.tileOpenAnimation,
            sidebarHidden: sidebarHidden,
            renderedStripLeadingInset: renderedStripLeadingInset
        )
    }
}

@MainActor
final class WorkspaceCanvasDocumentView: NSView {
    enum Metrics {
        static let workspacePeek: CGFloat = 44
        static let workspaceScrollAnimationDuration: TimeInterval = 0.22
    }

    struct AnchoredZoomTransition {
        let tileID: UUID
        let startOrigin: NSPoint
        let targetOrigin: NSPoint
        let initialOverviewProgress: CGFloat
    }

    let store: WorkspaceStore
    let settings: AppSettings
    let interactionController: WorkspaceInteractionController
    let runtime: GhosttyRuntime
    let animator = WorkspaceCanvasAnimator()
    let zoomController = WorkspaceCanvasZoomController()
    let overviewRenderer = WorkspaceCanvasOverviewRenderer()
    let tileReorderController: WorkspaceTileReorderController

    var workspaces: [WorkspaceStore.Workspace] = []
    var selectedWorkspaceID: UUID?
    var selectedTileID: UUID?
    var zoomMode: WorkspaceInteractionController.CanvasZoomMode = .focused
    var tileViews: [UUID: WorkspaceTileHostView] = [:]
    var resizeHandles: [UUID: WorkspaceTileResizeHandleView] = [:]
    var closingTileSnapshotView: WorkspaceClosingSnapshotView?
    var closingTileSnapshotAnimation: WorkspaceInteractionController.TileCloseAnimation?
    var verticalSplitOpenAnimation: VerticalSplitOpenAnimation?
    var lastVerticalScrollEventAt = Date.distantPast
    var lastDiscreteVerticalNavigationAt = Date.distantPast
    var verticalScrollAccumulator: CGFloat = 0
    var didNavigateDuringCurrentScrollGesture = false
    var tileScrollGestureLock = TileScrollGestureLock()
    var isSidebarHidden = false
    var currentStripLeadingInset = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)
    var workspaceScrollAnimationTimer: Timer?
    var workspaceScrollAnimationStartOrigin: NSPoint = .zero
    var workspaceScrollAnimationTargetOrigin: NSPoint = .zero
    var workspaceScrollAnimationStartedAt = Date.distantPast
    var anchoredZoomTransition: AnchoredZoomTransition?
    var tileReorderSession: WorkspaceTileReorderController.Session?

    var targetStripLeadingInset: CGFloat {
        WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: isSidebarHidden)
    }

    var viewportSize: CGSize = .zero {
        didSet {
            guard oldValue != viewportSize else { return }
            needsLayout = true
        }
    }

    override var isFlipped: Bool { true }

    var isManagingAnchoredZoomTransition: Bool {
        anchoredZoomTransition != nil
    }

    var isAnimatingPointerSensitiveTransition: Bool {
        animator.isHorizontalRevealAnimationActive
            || workspaceScrollAnimationTimer != nil
            || anchoredZoomTransition != nil
    }

    init(
        settings: AppSettings,
        store: WorkspaceStore,
        interactionController: WorkspaceInteractionController,
        runtime: GhosttyRuntime
    ) {
        self.settings = settings
        self.store = store
        self.interactionController = interactionController
        self.runtime = runtime
        tileReorderController = WorkspaceTileReorderController(store: store)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        animator.onChange = { [weak self] in
            self?.needsLayout = true
        }
        zoomController.onChange = { [weak self] in
            self?.needsLayout = true
        }
        overviewRenderer.onTileActivated = { [weak self] tileID in
            self?.activateOverviewTile(tileID)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        workspaces: [WorkspaceStore.Workspace],
        selectedWorkspaceID: UUID,
        selectedTileID: UUID?,
        allTileIDs: Set<UUID>,
        canvasZoomMode: WorkspaceInteractionController.CanvasZoomMode,
        sidebarHidden: Bool,
        renderedStripLeadingInset: CGFloat
    ) {
        let animationPolicy = settings.animationPolicy
        self.workspaces = workspaces
        self.selectedWorkspaceID = selectedWorkspaceID
        self.selectedTileID = selectedTileID
        zoomMode = canvasZoomMode
        isSidebarHidden = sidebarHidden
        currentStripLeadingInset = renderedStripLeadingInset
        animator.animationPolicy = animationPolicy
        zoomController.animationPolicy = animationPolicy

        if !animationPolicy.effectiveAnimationsEnabled,
            workspaceScrollAnimationTimer != nil,
            let clipView = enclosingScrollView?.contentView
        {
            stopWorkspaceScrollAnimation()
            clipView.setBoundsOrigin(workspaceScrollAnimationTargetOrigin)
            enclosingScrollView?.reflectScrolledClipView(clipView)
        }

        let handleIDs = Set(resizeHandleTileIDs(in: workspaces))
        let shouldKeepTileViewsInDocument = canvasZoomMode != .overview

        for (tileID, view) in tileViews where !allTileIDs.contains(tileID) {
            view.dispose()
            view.removeFromSuperview()
            tileViews.removeValue(forKey: tileID)
        }
        if let tileReorderSession, !allTileIDs.contains(tileReorderSession.tileID) {
            self.tileReorderSession = nil
        }
        if canvasZoomMode == .overview {
            tileReorderSession = nil
        }
        pruneVerticalSplitOpenAnimation(using: allTileIDs)

        animator.pruneOffsets(workspaces: workspaces)

        for (tileID, handle) in resizeHandles where !handleIDs.contains(tileID) {
            handle.removeFromSuperview()
            resizeHandles.removeValue(forKey: tileID)
        }

        for tile in allTileIDs where tileViews[tile] == nil {
            _ = makeTileView(for: tile)
        }

        for workspace in workspaces {
            let presentedWorkspace = presentedWorkspace(for: workspace)
            for tile in presentedWorkspace.tiles {
                let tileView = tileViews[tile.id] ?? makeTileView(for: tile.id)
                if shouldKeepTileViewsInDocument, tileView.superview !== self {
                    tileView.removeFromSuperview()
                    addSubview(tileView)
                }
                tileView.update(tile: tile, selected: tile.id == selectedTileID)
                tileView.setTileReorderPresentation(
                    lifted: tile.id == tileReorderSession?.tileID,
                    dropTarget: tile.id == tileReorderSession?.move?.targetTileID,
                    dragSource: tile.id == tileReorderSession?.tileID,
                    animated: true,
                    animationPolicy: animationPolicy
                )
            }
        }

        for tileID in handleIDs {
            let handle = resizeHandles[tileID] ?? makeResizeHandle(for: tileID)
            handle.tileID = tileID
        }

        animator.syncRenderedHorizontalOffsets(for: workspaces)
        zoomController.sync(
            mode: zoomMode,
            animated: true
        )
        overviewRenderer.sync(
            tileViews: tileViews,
            allTileIDs: allTileIDs,
            isOverviewPresented: zoomController.isOverviewPresented,
            selectedTileID: selectedTileID,
            theme: runtime.appTheme,
            hostView: self
        )

        needsLayout = true
    }

    override func layout() {
        super.layout()

        let viewportWidth = max(viewportSize.width, 1)
        let viewportHeight = max(viewportSize.height, 1)
        let tileHeight = baseTileHeight()
        let rowHeight = self.baseRowHeight()
        let baseRowSpacing = WorkspaceCanvasLayoutMetrics.rowSpacing
        let baseVerticalPadding = WorkspaceCanvasLayoutMetrics.verticalPadding
        let baseTileSpacing = WorkspaceCanvasLayoutMetrics.tileSpacing
        let scale = zoomController.scale(
            mode: zoomMode,
            viewportSize: viewportSize,
            workspaces: workspaces,
            stripLeadingInset: currentStripLeadingInset
        )
        let stripLeadingInset = currentStripLeadingInset
        let anchorX = stripLeadingInset + WorkspaceCanvasLayoutMetrics.horizontalPadding
        let isOverviewPresented = zoomController.isOverviewPresented
        let overviewTileHeight = tileHeight * scale
        let overviewRowHeight = rowHeight * scale
        let overviewRowSpacing = baseRowSpacing * scale
        let overviewVerticalPadding = baseVerticalPadding * scale
        let overviewTileSpacing = baseTileSpacing * scale
        let overviewTopInsetAdjustment = max(baseVerticalPadding - overviewVerticalPadding, 0)
        overviewRenderer.sync(
            tileViews: tileViews,
            allTileIDs: Set(tileViews.keys),
            isOverviewPresented: isOverviewPresented,
            selectedTileID: selectedTileID,
            theme: runtime.appTheme,
            hostView: self
        )

        for (workspaceIndex, workspace) in workspaces.enumerated() {
            let layoutWorkspace = presentedWorkspace(for: workspace)
            let columns = WorkspaceColumnLayout.columns(in: layoutWorkspace)
            let focusedRowOriginY = CGFloat(workspaceIndex) * (rowHeight + baseRowSpacing)
            let overviewRowOriginY =
                overviewTopInsetAdjustment
                + CGFloat(workspaceIndex) * (overviewRowHeight + overviewRowSpacing)
            var focusedX = anchorX - animator.effectiveHorizontalOffset(for: workspace)
            var overviewX =
                anchorX
                - zoomController.effectiveHorizontalOffset(animator.effectiveHorizontalOffset(for: workspace)) * scale

            for (columnIndex, column) in columns.enumerated() {
                let representativeTileID = column.tiles.first?.id ?? UUID()
                let gapWidth = animator.closingGapWidth(beforeTileAt: columnIndex, in: workspace.id)
                let overviewGapWidth = gapWidth * scale
                let tileWidth = animator.effectiveTileWidth(column.width, for: representativeTileID)
                layoutClosingTileSnapshotIfNeeded(
                    workspaceID: layoutWorkspace.id,
                    insertionIndex: columnIndex,
                    originX: isOverviewPresented ? overviewX : focusedX,
                    rowOriginY: isOverviewPresented ? overviewRowOriginY : focusedRowOriginY,
                    tileHeight: isOverviewPresented ? overviewTileHeight : tileHeight,
                    gapWidth: isOverviewPresented ? overviewGapWidth : gapWidth
                )
                focusedX += gapWidth
                overviewX += overviewGapWidth
                let columnFrames = WorkspaceColumnLayout.columnTileFrames(
                    for: column,
                    originX: focusedX,
                    originY: focusedRowOriginY + baseVerticalPadding,
                    width: tileWidth,
                    height: tileHeight
                )
                let previewFrames = WorkspaceColumnLayout.columnTileFrames(
                    for: column,
                    originX: overviewX,
                    originY: overviewRowOriginY + overviewVerticalPadding,
                    width: tileWidth * scale,
                    height: overviewTileHeight
                )

                for tile in column.tiles {
                    guard let tileView = tileViews[tile.id],
                        let focusedFrame = columnFrames[tile.id],
                        let previewFrame = previewFrames[tile.id]
                    else {
                        continue
                    }

                    if isOverviewPresented {
                        overviewRenderer.layoutPreview(
                            for: tile.id,
                            previewFrame: previewFrame,
                            contentSize: focusedFrame.size
                        )
                    } else {
                        overviewRenderer.hidePreview(for: tile.id)
                        tileView.frame = effectiveTileFrame(for: tile.id, targetFrame: focusedFrame)
                    }
                }

                if shouldShowResizeHandle(for: columnIndex, in: columns), let handle = resizeHandles[representativeTileID] {
                    handle.isHidden = isOverviewPresented
                    if !isOverviewPresented {
                        let handleCenterX = focusedX + tileWidth + (baseTileSpacing / 2)
                        handle.frame = NSRect(
                            x: handleCenterX - (WorkspaceCanvasLayoutMetrics.resizeHandleWidth / 2),
                            y: focusedRowOriginY + baseVerticalPadding + WorkspaceCanvasLayoutMetrics.resizeHandleInset,
                            width: WorkspaceCanvasLayoutMetrics.resizeHandleWidth,
                            height: max(
                                tileHeight - (WorkspaceCanvasLayoutMetrics.resizeHandleInset * 2),
                                72
                            )
                        )
                    }
                }

                focusedX += tileWidth + baseTileSpacing
                overviewX += (tileWidth * scale) + overviewTileSpacing
            }

            let trailingGapWidth = animator.closingGapWidth(beforeTileAt: columns.count, in: workspace.id)
            layoutClosingTileSnapshotIfNeeded(
                workspaceID: layoutWorkspace.id,
                insertionIndex: columns.count,
                originX: isOverviewPresented ? overviewX : focusedX,
                rowOriginY: isOverviewPresented ? overviewRowOriginY : focusedRowOriginY,
                tileHeight: isOverviewPresented ? overviewTileHeight : tileHeight,
                gapWidth: isOverviewPresented ? trailingGapWidth * scale : trailingGapWidth
            )
        }

        let overviewWorkspaces = WorkspaceCanvasZoomController.overviewWorkspaces(from: workspaces)
        let totalHeight =
            isOverviewPresented
            ? overviewTopInsetAdjustment
                + overviewRowHeight * CGFloat(overviewWorkspaces.count)
                + overviewRowSpacing * CGFloat(max(overviewWorkspaces.count - 1, 0))
            : rowHeight * CGFloat(workspaces.count)
                + baseRowSpacing * CGFloat(max(workspaces.count - 1, 0))
        let contentSize = NSSize(width: viewportWidth, height: max(totalHeight, viewportHeight))
        if frame.size != contentSize {
            setFrameSize(contentSize)
        }

        syncAnchoredZoomViewportIfNeeded(contentHeight: contentSize.height)
    }

    func revealTile(_ tileID: UUID, animated: Bool) {
        guard viewportSize.width > 0 else { return }
        animator.queueReveal(for: tileID, animated: animated, in: workspaces)
        interactionController.revealTile(
            tileID,
            viewportWidth: viewportSize.width,
            stripLeadingInset: targetStripLeadingInset
        )
    }

    func ensureSelectedTileClearsSidebar(animated: Bool) {
        guard !isSidebarHidden,
            let selectedTileID,
            let tileView = tileViews[selectedTileID]
        else {
            return
        }

        let safeLeadingX =
            targetStripLeadingInset
            + WorkspaceCanvasLayoutMetrics.horizontalPadding
        guard tileView.frame.minX < safeLeadingX - 0.5 else { return }

        revealTile(selectedTileID, animated: animated)
    }

    func closeTile(_ tileID: UUID, animated: Bool) {
        let workspaceID = store.workspaceID(containing: tileID) ?? store.selectedWorkspaceID
        runtime.closeTile(
            tileID,
            preferredVisibleMidX: visibleMidX(forWorkspaceID: workspaceID),
            stripLeadingInset: targetStripLeadingInset,
            transition: animated ? .animatedReveal : .immediate,
            snapshotImage: tileViews[tileID]?.tairiSnapshotImage()
        )
    }

    func scrollWorkspaceToVisible(
        _ workspaceID: UUID,
        preserveHorizontalOrigin: Bool = true,
        animated: Bool = true
    ) {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }),
            let clipView = enclosingScrollView?.contentView
        else {
            return
        }

        let rowOriginY = CGFloat(workspaceIndex) * (baseRowHeight() + WorkspaceCanvasLayoutMetrics.rowSpacing)
        let preferredOriginY = rowOriginY - Metrics.workspacePeek
        let maxOriginY = max(bounds.height - clipView.bounds.height, 0)
        let targetOrigin = NSPoint(
            x: preserveHorizontalOrigin ? clipView.bounds.origin.x : 0,
            y: min(max(preferredOriginY, 0), maxOriginY)
        )

        animateWorkspaceScroll(to: targetOrigin, in: clipView, animated: animated)
    }

    func scrollOverviewToOrigin(animated: Bool) {
        guard let clipView = enclosingScrollView?.contentView else { return }
        animateWorkspaceScroll(to: NSPoint.zero, in: clipView, animated: animated)
    }

    private func resizeHandleTileIDs(in workspaces: [WorkspaceStore.Workspace]) -> [UUID] {
        workspaces.flatMap { workspace in
            let columns = WorkspaceColumnLayout.columns(in: workspace)
            if columns.count == 1 {
                return columns.compactMap { $0.tiles.first?.id }
            }
            return Array(columns.dropLast()).compactMap { $0.tiles.first?.id }
        }
    }

    private func shouldShowResizeHandle(for columnIndex: Int, in columns: [WorkspaceStore.Column]) -> Bool {
        if columns.count == 1 {
            return columnIndex == 0
        }
        return columnIndex < columns.count - 1
    }

    private func makeTileView(for tileID: UUID) -> WorkspaceTileHostView {
        let view = WorkspaceTileHostView(runtime: runtime, tileID: tileID)
        tileViews[tileID] = view
        addSubview(view)
        return view
    }

    private func makeResizeHandle(for tileID: UUID) -> WorkspaceTileResizeHandleView {
        let handle = WorkspaceTileResizeHandleView(
            runtime: runtime,
            store: store,
            interactionController: interactionController,
            tileID: tileID
        )
        resizeHandles[tileID] = handle
        addSubview(handle)
        return handle
    }

    var isTileReorderActive: Bool {
        tileReorderSession != nil
    }

    private func presentedWorkspace(for workspace: WorkspaceStore.Workspace) -> WorkspaceStore.Workspace {
        guard let tileReorderSession,
            tileReorderSession.workspaceID == workspace.id,
            let previewWorkspace = tileReorderSession.previewWorkspace
        else {
            return workspace
        }

        return previewWorkspace
    }

    private func effectiveTileFrame(for tileID: UUID, targetFrame: CGRect) -> CGRect {
        if let tileReorderSession,
            tileReorderSession.tileID == tileID
        {
            return tileReorderSession.draggedFrame
        }

        return effectiveFocusedFrame(for: tileID, targetFrame: targetFrame)
    }
}
