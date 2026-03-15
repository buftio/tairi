import AppKit
import SwiftUI

struct WorkspaceCanvasView: NSViewRepresentable {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var interactionController: WorkspaceInteractionController
    @ObservedObject var runtime: GhosttyRuntime
    let sidebarHidden: Bool

    func makeNSView(context: Context) -> WorkspaceCanvasContainerView {
        WorkspaceCanvasContainerView(store: store, interactionController: interactionController, runtime: runtime)
    }

    func updateNSView(_ nsView: WorkspaceCanvasContainerView, context: Context) {
        let allTileIDs = Set(store.workspaces.flatMap(\.tiles).map(\.id))
        nsView.update(
            workspaces: store.workspaces,
            selectedWorkspaceID: store.selectedWorkspaceID,
            selectedTileID: store.selectedTileID,
            allTileIDs: allTileIDs,
            canvasTransition: interactionController.canvasTransition,
            tileCloseAnimation: interactionController.tileCloseAnimation,
            tileOpenAnimation: interactionController.tileOpenAnimation,
            sidebarHidden: sidebarHidden
        )
    }
}

@MainActor
final class WorkspaceCanvasContainerView: NSView {
    private let scrollView = WorkspaceCanvasScrollView()
    private let documentView: WorkspaceCanvasDocumentView
    private var lastSelectedTileID: UUID?
    private var lastSelectedWorkspaceID: UUID?
    private var lastCanvasTransitionID: Int?
    private var lastTileCloseAnimationID: Int?
    private var lastTileOpenAnimationID: Int?
    private var currentSelectedWorkspaceID: UUID?
    private var currentSelectedTileID: UUID?
    private var currentSidebarHidden = false
    private var shouldSuppressFallbackReveal = false
    private var hasStabilizedInitialViewport = false
    private var lastSidebarHidden: Bool?

    init(store: WorkspaceStore, interactionController: WorkspaceInteractionController, runtime: GhosttyRuntime) {
        documentView = WorkspaceCanvasDocumentView(
            store: store,
            interactionController: interactionController,
            runtime: runtime
        )
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        configureAccessibility(
            identifier: TairiAccessibility.workspaceCanvas,
            label: "Workspace canvas"
        )

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.canvasDocumentView = documentView
        scrollView.documentView = documentView

        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        documentView.viewportSize = scrollView.contentView.bounds.size
        stabilizeInitialViewportIfNeeded()
    }

    func update(
        workspaces: [WorkspaceStore.Workspace],
        selectedWorkspaceID: UUID,
        selectedTileID: UUID?,
        allTileIDs: Set<UUID>,
        canvasTransition: WorkspaceInteractionController.CanvasTransition?,
        tileCloseAnimation: WorkspaceInteractionController.TileCloseAnimation?,
        tileOpenAnimation: WorkspaceInteractionController.TileOpenAnimation?,
        sidebarHidden: Bool
    ) {
        currentSelectedWorkspaceID = selectedWorkspaceID
        currentSelectedTileID = selectedTileID
        currentSidebarHidden = sidebarHidden
        documentView.update(
            workspaces: workspaces,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedTileID: selectedTileID,
            allTileIDs: allTileIDs,
            sidebarHidden: sidebarHidden
        )
        documentView.viewportSize = scrollView.contentView.bounds.size

        if let canvasTransition, canvasTransition.id != lastCanvasTransitionID {
            switch canvasTransition.kind {
            case .reveal(let tileID, let animated):
                documentView.revealTile(tileID, animated: animated)
                shouldSuppressFallbackReveal = false
            case .preserveViewport:
                shouldSuppressFallbackReveal = true
            }
            lastCanvasTransitionID = canvasTransition.id
        } else if lastSelectedWorkspaceID == selectedWorkspaceID,
                  lastSelectedTileID != selectedTileID,
                  let selectedTileID,
                  !shouldSuppressFallbackReveal {
            documentView.revealTile(selectedTileID, animated: false)
        } else {
            shouldSuppressFallbackReveal = false
        }

        if let tileCloseAnimation, tileCloseAnimation.id != lastTileCloseAnimationID {
            documentView.animateTileClose(tileCloseAnimation)
            lastTileCloseAnimationID = tileCloseAnimation.id
        }

        if let tileOpenAnimation, tileOpenAnimation.id != lastTileOpenAnimationID {
            documentView.animateTileOpen(tileOpenAnimation)
            lastTileOpenAnimationID = tileOpenAnimation.id
        }

        if lastSelectedWorkspaceID != selectedWorkspaceID || lastSelectedTileID != selectedTileID {
            documentView.scrollWorkspaceToVisible(
                selectedWorkspaceID,
                preserveHorizontalOrigin: true,
                animated: !TairiEnvironment.isUITesting
            )
        }

        documentView.layoutSubtreeIfNeeded()
        stabilizeInitialViewportIfNeeded()
        if lastSidebarHidden == true, !sidebarHidden {
            documentView.ensureSelectedTileClearsSidebar(animated: !TairiEnvironment.isUITesting)
        }

        lastSelectedTileID = selectedTileID
        lastSelectedWorkspaceID = selectedWorkspaceID
        lastSidebarHidden = sidebarHidden
    }

    private func stabilizeInitialViewportIfNeeded() {
        guard !hasStabilizedInitialViewport,
              scrollView.contentView.bounds.width > 0,
              scrollView.contentView.bounds.height > 0,
              let currentSelectedWorkspaceID else {
            return
        }

        if let currentSelectedTileID {
            documentView.revealTile(currentSelectedTileID, animated: false)
        }

        documentView.scrollWorkspaceToVisible(
            currentSelectedWorkspaceID,
            preserveHorizontalOrigin: false,
            animated: false
        )
        hasStabilizedInitialViewport = true
    }
}

@MainActor
final class WorkspaceCanvasDocumentView: NSView {
    private enum Metrics {
        static let workspacePeek: CGFloat = 72
        static let workspaceScrollAnimationDuration: TimeInterval = 0.22
    }

    private let store: WorkspaceStore
    private let interactionController: WorkspaceInteractionController
    private let runtime: GhosttyRuntime
    private let animator = WorkspaceCanvasAnimator()

    private var workspaces: [WorkspaceStore.Workspace] = []
    private var selectedWorkspaceID: UUID?
    private var selectedTileID: UUID?
    private var tileViews: [UUID: WorkspaceTileHostView] = [:]
    private var resizeHandles: [UUID: WorkspaceTileResizeHandleView] = [:]
    private var closingTileSnapshotView: WorkspaceClosingSnapshotView?
    private var closingTileSnapshotAnimation: WorkspaceInteractionController.TileCloseAnimation?
    private var lastVerticalScrollEventAt = Date.distantPast
    private var lastDiscreteVerticalNavigationAt = Date.distantPast
    private var verticalScrollAccumulator: CGFloat = 0
    private var didNavigateDuringCurrentScrollGesture = false
    private var isSidebarHidden = false
    private var workspaceScrollAnimationTimer: Timer?
    private var workspaceScrollAnimationStartOrigin: NSPoint = .zero
    private var workspaceScrollAnimationTargetOrigin: NSPoint = .zero
    private var workspaceScrollAnimationStartedAt = Date.distantPast

    private var targetStripLeadingInset: CGFloat {
        WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: isSidebarHidden)
    }

    var viewportSize: CGSize = .zero {
        didSet {
            guard oldValue != viewportSize else { return }
            needsLayout = true
        }
    }

    override var isFlipped: Bool { true }

    init(store: WorkspaceStore, interactionController: WorkspaceInteractionController, runtime: GhosttyRuntime) {
        self.store = store
        self.interactionController = interactionController
        self.runtime = runtime
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        animator.onChange = { [weak self] in
            self?.needsLayout = true
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
        sidebarHidden: Bool
    ) {
        self.workspaces = workspaces
        self.selectedWorkspaceID = selectedWorkspaceID
        self.selectedTileID = selectedTileID
        isSidebarHidden = sidebarHidden
        animator.syncRenderedStripLeadingInset(
            sidebarHidden: sidebarHidden,
            animated: !TairiEnvironment.isUITesting
        )

        let handleIDs = Set(workspaces.flatMap { $0.tiles.dropLast() }.map(\.id))

        for (tileID, view) in tileViews where !allTileIDs.contains(tileID) {
            view.dispose()
            view.removeFromSuperview()
            tileViews.removeValue(forKey: tileID)
        }

        animator.pruneOffsets(workspaces: workspaces)

        for (tileID, handle) in resizeHandles where !handleIDs.contains(tileID) {
            handle.removeFromSuperview()
            resizeHandles.removeValue(forKey: tileID)
        }

        for tile in allTileIDs where tileViews[tile] == nil {
            _ = makeTileView(for: tile)
        }

        for workspace in workspaces {
            for tile in workspace.tiles {
                let tileView = tileViews[tile.id] ?? makeTileView(for: tile.id)
                if tileView.superview !== self {
                    tileView.removeFromSuperview()
                    addSubview(tileView)
                }
                tileView.update(tile: tile, selected: tile.id == selectedTileID)
            }
        }

        for tile in workspaces.flatMap({ $0.tiles.dropLast() }) {
            let handle = resizeHandles[tile.id] ?? makeResizeHandle(for: tile.id)
            handle.tileID = tile.id
        }

        animator.syncRenderedHorizontalOffsets(for: workspaces)

        needsLayout = true
    }

    override func layout() {
        super.layout()

        let viewportWidth = max(viewportSize.width, 1)
        let viewportHeight = max(viewportSize.height, 1)
        let tileHeight = currentTileHeight()
        let rowHeight = currentRowHeight()
        let stripLeadingInset = animator.effectiveStripLeadingInset(sidebarHidden: isSidebarHidden)

        for (workspaceIndex, workspace) in workspaces.enumerated() {
            let rowOriginY = CGFloat(workspaceIndex) * (rowHeight + WorkspaceCanvasLayoutMetrics.rowSpacing)
            var x = stripLeadingInset
                + WorkspaceCanvasLayoutMetrics.horizontalPadding
                - animator.effectiveHorizontalOffset(for: workspace)

            for (tileIndex, tile) in workspace.tiles.enumerated() {
                let gapWidth = animator.closingGapWidth(beforeTileAt: tileIndex, in: workspace.id)
                layoutClosingTileSnapshotIfNeeded(
                    workspaceID: workspace.id,
                    insertionIndex: tileIndex,
                    originX: x,
                    rowOriginY: rowOriginY,
                    tileHeight: tileHeight,
                    gapWidth: gapWidth
                )
                x += gapWidth
                guard let tileView = tileViews[tile.id] else { continue }
                let renderedWidth = WorkspaceRowLayout.renderedTileWidth(
                    for: tile,
                    in: workspace,
                    viewportWidth: viewportSize.width,
                    stripLeadingInset: stripLeadingInset
                )
                let animatedWidth = animator.effectiveTileWidth(renderedWidth, for: tile.id)
                tileView.frame = NSRect(
                    x: x,
                    y: rowOriginY + WorkspaceCanvasLayoutMetrics.verticalPadding,
                    width: animatedWidth,
                    height: tileHeight
                )

                if tileIndex < workspace.tiles.count - 1, let handle = resizeHandles[tile.id] {
                    let handleCenterX = x + animatedWidth + (WorkspaceCanvasLayoutMetrics.tileSpacing / 2)
                    handle.frame = NSRect(
                        x: handleCenterX - (WorkspaceCanvasLayoutMetrics.resizeHandleWidth / 2),
                        y: rowOriginY + WorkspaceCanvasLayoutMetrics.verticalPadding + WorkspaceCanvasLayoutMetrics.resizeHandleInset,
                        width: WorkspaceCanvasLayoutMetrics.resizeHandleWidth,
                        height: max(tileHeight - (WorkspaceCanvasLayoutMetrics.resizeHandleInset * 2), 72)
                    )
                }

                x += animatedWidth + WorkspaceCanvasLayoutMetrics.tileSpacing
            }

            let trailingGapWidth = animator.closingGapWidth(beforeTileAt: workspace.tiles.count, in: workspace.id)
            layoutClosingTileSnapshotIfNeeded(
                workspaceID: workspace.id,
                insertionIndex: workspace.tiles.count,
                originX: x,
                rowOriginY: rowOriginY,
                tileHeight: tileHeight,
                gapWidth: trailingGapWidth
            )
        }

        let totalHeight = rowHeight * CGFloat(workspaces.count)
            + WorkspaceCanvasLayoutMetrics.rowSpacing * CGFloat(max(workspaces.count - 1, 0))
        let contentSize = NSSize(width: viewportWidth, height: max(totalHeight, viewportHeight))
        if frame.size != contentSize {
            setFrameSize(contentSize)
        }
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
              let tileView = tileViews[selectedTileID] else {
            return
        }

        let safeLeadingX = targetStripLeadingInset
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
              let clipView = enclosingScrollView?.contentView else {
            return
        }

        let rowOriginY = CGFloat(workspaceIndex) * (currentRowHeight() + WorkspaceCanvasLayoutMetrics.rowSpacing)
        let preferredOriginY = rowOriginY - Metrics.workspacePeek
        let maxOriginY = max(bounds.height - clipView.bounds.height, 0)
        let targetOrigin = NSPoint(
            x: preserveHorizontalOrigin ? clipView.bounds.origin.x : 0,
            y: min(max(preferredOriginY, 0), maxOriginY)
        )

        animateWorkspaceScroll(to: targetOrigin, in: clipView, animated: animated)
    }

    func handleScrollWheel(_ event: NSEvent) -> Bool {
        if shouldTreatAsHorizontalScroll(event) {
            return handleHorizontalScroll(event)
        }
        if shouldTreatAsVerticalScroll(event) {
            return handleVerticalScroll(event)
        }
        return false
    }

    func handleWorkspaceKeyNavigation(offset: Int, from tileID: UUID) -> Bool {
        guard let tile = store.tile(tileID), viewportSize.width > 0 else { return false }
        interactionController.selectTile(tile.id)
        return navigateWorkspace(offset: offset, preferredVisibleMidX: visibleMidX(for: store.selectedWorkspace))
    }

    func handleTileKeyNavigation(offset: Int, from tileID: UUID) -> Bool {
        guard store.tile(tileID) != nil else { return false }
        interactionController.selectTile(tileID)
        interactionController.selectAdjacentTile(offset: offset, transition: .animatedReveal)
        guard let selectedTileID = store.selectedTileID else { return false }
        runtime.focusSurface(tileID: selectedTileID)
        return true
    }

    private func handleHorizontalScroll(_ event: NSEvent) -> Bool {
        guard viewportSize.width > 0, abs(event.scrollingDeltaX) > 0 else { return false }
        interactionController.scrollSelectedWorkspaceHorizontally(
            deltaX: -event.scrollingDeltaX,
            viewportWidth: viewportSize.width,
            stripLeadingInset: targetStripLeadingInset
        )
        return true
    }

    private func handleVerticalScroll(_ event: NSEvent) -> Bool {
        let deltaY = event.scrollingDeltaY
        guard abs(deltaY) > 0 else { return false }

        if event.hasPreciseScrollingDeltas {
            resetVerticalGestureIfNeeded(for: event)
            verticalScrollAccumulator += deltaY

            let threshold: CGFloat = 36
            if !didNavigateDuringCurrentScrollGesture, abs(verticalScrollAccumulator) >= threshold {
                let offset = verticalScrollAccumulator > 0 ? -1 : 1
                let didNavigate = navigateWorkspace(offset: offset)
                didNavigateDuringCurrentScrollGesture = didNavigate
                verticalScrollAccumulator = 0
            }

            if event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended) {
                resetVerticalGestureState()
            }
            return true
        }

        let now = Date()
        guard now.timeIntervalSince(lastDiscreteVerticalNavigationAt) >= 0.18 else { return true }
        lastDiscreteVerticalNavigationAt = now
        return navigateWorkspace(offset: deltaY > 0 ? -1 : 1)
    }

    private func navigateWorkspace(offset: Int, preferredVisibleMidX: CGFloat? = nil) -> Bool {
        guard let selectedWorkspaceIndex = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else {
            return false
        }

        let nextIndex = min(max(selectedWorkspaceIndex + offset, 0), workspaces.count - 1)
        guard nextIndex != selectedWorkspaceIndex else { return false }

        let targetWorkspace = workspaces[nextIndex]
        let targetVisibleMidX = preferredVisibleMidX ?? visibleMidX(for: targetWorkspace)
        interactionController.selectAdjacentWorkspace(
            offset: offset,
            preferredVisibleMidX: targetVisibleMidX,
            stripLeadingInset: targetStripLeadingInset
        )

        if let selectedTileID = store.selectedTileID {
            runtime.focusSurface(tileID: selectedTileID)
        } else {
            window?.makeFirstResponder(enclosingScrollView)
        }
        return true
    }

    private func visibleMidX(for workspace: WorkspaceStore.Workspace) -> CGFloat {
        workspace.horizontalOffset + (viewportSize.width / 2)
    }

    func visibleMidX(forWorkspaceID workspaceID: UUID) -> CGFloat? {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return nil }
        return visibleMidX(for: workspace)
    }

    var currentStripLeadingInset: CGFloat {
        targetStripLeadingInset
    }

    func animateTileClose(_ animation: WorkspaceInteractionController.TileCloseAnimation) {
        animator.queueClosingGap(
            workspaceID: animation.workspaceID,
            insertionIndex: animation.insertionIndex,
            width: animation.gapWidth,
            animated: animation.animated
        )
        closingTileSnapshotAnimation = animation

        if let snapshotImage = animation.snapshotImage {
            let snapshotView = closingTileSnapshotView ?? WorkspaceClosingSnapshotView(image: snapshotImage)
            snapshotView.image = snapshotImage
            snapshotView.isHidden = false
            if snapshotView.superview !== self {
                addSubview(snapshotView)
            }
            closingTileSnapshotView = snapshotView
        } else {
            closingTileSnapshotView?.removeFromSuperview()
            closingTileSnapshotView = nil
        }
        needsLayout = true
    }

    func animateTileOpen(_ animation: WorkspaceInteractionController.TileOpenAnimation) {
        animator.queueOpeningTile(
            tileID: animation.tileID,
            animated: animation.animated
        )
    }

    private func layoutClosingTileSnapshotIfNeeded(
        workspaceID: UUID,
        insertionIndex: Int,
        originX: CGFloat,
        rowOriginY: CGFloat,
        tileHeight: CGFloat,
        gapWidth: CGFloat
    ) {
        guard let animation = closingTileSnapshotAnimation,
              animation.workspaceID == workspaceID,
              animation.insertionIndex == insertionIndex,
              let closingTileSnapshotView else {
            return
        }

        let snapshotWidth = min(animation.snapshotWidth, max(gapWidth, 0))
        guard snapshotWidth > 0.5 else {
            closingTileSnapshotView.isHidden = true
            return
        }

        closingTileSnapshotView.isHidden = false
        closingTileSnapshotView.alphaValue = max(min(snapshotWidth / max(animation.snapshotWidth, 1), 1), 0)
        closingTileSnapshotView.frame = NSRect(
            x: originX,
            y: rowOriginY + WorkspaceCanvasLayoutMetrics.verticalPadding,
            width: snapshotWidth,
            height: tileHeight
        )
    }

    private func animateWorkspaceScroll(to targetOrigin: NSPoint, in clipView: NSClipView, animated: Bool) {
        let currentOrigin = clipView.bounds.origin
        guard animated else {
            stopWorkspaceScrollAnimation()
            clipView.setBoundsOrigin(targetOrigin)
            enclosingScrollView?.reflectScrolledClipView(clipView)
            return
        }

        guard abs(currentOrigin.x - targetOrigin.x) > 0.5 || abs(currentOrigin.y - targetOrigin.y) > 0.5 else {
            stopWorkspaceScrollAnimation()
            clipView.setBoundsOrigin(targetOrigin)
            enclosingScrollView?.reflectScrolledClipView(clipView)
            return
        }

        workspaceScrollAnimationStartOrigin = currentOrigin
        workspaceScrollAnimationTargetOrigin = targetOrigin
        workspaceScrollAnimationStartedAt = Date()

        workspaceScrollAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self, weak clipView] _ in
            Task { @MainActor in
                guard let self, let clipView else { return }
                self.stepWorkspaceScrollAnimation(in: clipView)
            }
        }
        workspaceScrollAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stepWorkspaceScrollAnimation(in clipView: NSClipView) {
        let elapsed = Date().timeIntervalSince(workspaceScrollAnimationStartedAt)
        let progress = min(max(elapsed / Metrics.workspaceScrollAnimationDuration, 0), 1)
        let eased = 1 - pow(1 - progress, 3)
        let currentOrigin = NSPoint(
            x: workspaceScrollAnimationStartOrigin.x
                + (workspaceScrollAnimationTargetOrigin.x - workspaceScrollAnimationStartOrigin.x) * eased,
            y: workspaceScrollAnimationStartOrigin.y
                + (workspaceScrollAnimationTargetOrigin.y - workspaceScrollAnimationStartOrigin.y) * eased
        )

        clipView.setBoundsOrigin(currentOrigin)
        enclosingScrollView?.reflectScrolledClipView(clipView)

        if progress >= 1 {
            stopWorkspaceScrollAnimation()
        }
    }

    private func stopWorkspaceScrollAnimation() {
        workspaceScrollAnimationTimer?.invalidate()
        workspaceScrollAnimationTimer = nil
    }

    private func currentTileHeight() -> CGFloat {
        max(
            max(viewportSize.height, 1)
                - (Metrics.workspacePeek * 2)
                - (WorkspaceCanvasLayoutMetrics.verticalPadding * 2),
            WorkspaceCanvasLayoutMetrics.minimumTileHeight
        )
    }

    private func currentRowHeight() -> CGFloat {
        currentTileHeight() + (WorkspaceCanvasLayoutMetrics.verticalPadding * 2)
    }

    private func shouldTreatAsHorizontalScroll(_ event: NSEvent) -> Bool {
        let horizontalDelta = abs(event.scrollingDeltaX)
        guard horizontalDelta > 0 else { return false }
        return horizontalDelta >= abs(event.scrollingDeltaY)
    }

    private func shouldTreatAsVerticalScroll(_ event: NSEvent) -> Bool {
        let verticalDelta = abs(event.scrollingDeltaY)
        guard verticalDelta > 0 else { return false }
        return verticalDelta > abs(event.scrollingDeltaX)
    }

    private func resetVerticalGestureIfNeeded(for event: NSEvent) {
        let now = Date()
        let phaseBegan = event.phase.contains(.began) || event.phase.contains(.mayBegin)
        let timedOut = now.timeIntervalSince(lastVerticalScrollEventAt) > 0.25
        if phaseBegan || timedOut {
            resetVerticalGestureState()
        }
        lastVerticalScrollEventAt = now
    }

    private func resetVerticalGestureState() {
        verticalScrollAccumulator = 0
        didNavigateDuringCurrentScrollGesture = false
    }

    private func makeTileView(for tileID: UUID) -> WorkspaceTileHostView {
        let view = WorkspaceTileHostView(runtime: runtime, tileID: tileID)
        tileViews[tileID] = view
        addSubview(view)
        return view
    }

    private func makeResizeHandle(for tileID: UUID) -> WorkspaceTileResizeHandleView {
        let handle = WorkspaceTileResizeHandleView(
            store: store,
            interactionController: interactionController,
            tileID: tileID
        )
        resizeHandles[tileID] = handle
        addSubview(handle)
        return handle
    }
}
