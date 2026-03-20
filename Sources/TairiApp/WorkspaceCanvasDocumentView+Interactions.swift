import AppKit

@MainActor
extension WorkspaceCanvasDocumentView {
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

    func handleZoomKeyCommand(
        _ command: WorkspaceCanvasZoomController.Command,
        preferredTileID: UUID?
    ) -> Bool {
        switch command {
        case .zoomOut:
            interactionController.zoomOutCanvas()
            return true
        case .zoomIn:
            interactionController.zoomInOnSelection(transition: .animatedReveal)
            let tileID = preferredTileID ?? store.selectedTileID
            if let tileID {
                runtime.focusSurface(tileID: tileID)
            }
            return true
        }
    }

    func handleHorizontalScrollGesture(_ event: NSEvent) -> Bool {
        guard shouldTreatAsHorizontalScroll(event) else { return false }
        return handleHorizontalScroll(event)
    }

    func handleMagnify(_ event: NSEvent, preferredTileID: UUID?) -> Bool {
        zoomController.handleMagnify(
            event,
            mode: zoomMode,
            preferredTileID: preferredTileID
        ) { [weak self] command, tileID in
            guard let self else { return }
            _ = self.handleZoomKeyCommand(command, preferredTileID: tileID)
        }
    }

    func handleTileOverviewClick(_ tileID: UUID) -> Bool {
        guard zoomController.isOverviewPresented else { return false }
        activateOverviewTile(tileID)
        return true
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
        switch animation.kind {
        case .columnOpen:
            verticalSplitOpenAnimation = nil
            animator.queueOpeningTile(
                tileID: animation.tileID,
                animated: animation.animated,
                style: .widthExpand
            )
        case .verticalSplit(let sourceTileID):
            queueVerticalSplitOpenAnimation(
                tileID: animation.tileID,
                sourceTileID: sourceTileID,
                animated: animation.animated
            )
        }
    }

    func layoutClosingTileSnapshotIfNeeded(
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

    func activateOverviewTile(_ tileID: UUID) {
        guard store.tile(tileID) != nil,
              let workspaceID = store.workspaceID(containing: tileID) else { return }

        stopWorkspaceScrollAnimation()
        store.selectTile(tileID)
        store.revealTile(
            tileID,
            viewportWidth: viewportSize.width,
            stripLeadingInset: targetStripLeadingInset
        )
        workspaces = store.workspaces
        selectedWorkspaceID = store.selectedWorkspaceID
        selectedTileID = store.selectedTileID

        if let clipView = enclosingScrollView?.contentView {
            anchoredZoomTransition = AnchoredZoomTransition(
                tileID: tileID,
                startOrigin: clipView.bounds.origin,
                targetOrigin: focusedViewportOrigin(for: workspaceID, in: clipView),
                initialOverviewProgress: max(zoomController.renderedOverviewProgress, 0.001)
            )
        }

        interactionController.zoomInOnSelection(transition: .preserveViewport)
        runtime.focusSurface(tileID: tileID)
        needsLayout = true
    }

    private func handleHorizontalScroll(_ event: NSEvent) -> Bool {
        if zoomController.isOverviewPresented {
            return true
        }
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

    func visibleMidX(for workspace: WorkspaceStore.Workspace) -> CGFloat {
        workspace.horizontalOffset + (viewportSize.width / 2)
    }

    func visibleMidX(forWorkspaceID workspaceID: UUID) -> CGFloat? {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else { return nil }
        return visibleMidX(for: workspace)
    }

    func animateWorkspaceScroll(to targetOrigin: NSPoint, in clipView: NSClipView, animated: Bool) {
        anchoredZoomTransition = nil
        let currentOrigin = clipView.bounds.origin
        guard settings.animationPolicy.shouldAnimate(animated) else {
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
        let duration = settings.animationPolicy.scaledDuration(Metrics.workspaceScrollAnimationDuration)
        guard duration > 0 else {
            clipView.setBoundsOrigin(workspaceScrollAnimationTargetOrigin)
            enclosingScrollView?.reflectScrolledClipView(clipView)
            stopWorkspaceScrollAnimation()
            return
        }
        let progress = min(max(elapsed / duration, 0), 1)
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

    func stopWorkspaceScrollAnimation() {
        workspaceScrollAnimationTimer?.invalidate()
        workspaceScrollAnimationTimer = nil
    }

    func syncAnchoredZoomViewportIfNeeded(contentHeight: CGFloat) {
        guard let anchoredZoomTransition,
              let clipView = enclosingScrollView?.contentView else {
            return
        }

        let normalizedProgress = 1 - (zoomController.renderedOverviewProgress / anchoredZoomTransition.initialOverviewProgress)
        let progress = min(max(normalizedProgress, 0), 1)
        let maxOriginY = max(contentHeight - clipView.bounds.height, 0)
        let targetOrigin = NSPoint(
            x: max(anchoredZoomTransition.targetOrigin.x, 0),
            y: min(max(anchoredZoomTransition.targetOrigin.y, 0), maxOriginY)
        )
        let currentOrigin = NSPoint(
            x: anchoredZoomTransition.startOrigin.x
                + (targetOrigin.x - anchoredZoomTransition.startOrigin.x) * progress,
            y: anchoredZoomTransition.startOrigin.y
                + (targetOrigin.y - anchoredZoomTransition.startOrigin.y) * progress
        )

        if clipView.bounds.origin != currentOrigin {
            clipView.setBoundsOrigin(currentOrigin)
            enclosingScrollView?.reflectScrolledClipView(clipView)
        }

        if progress >= 0.999 || !zoomController.isOverviewPresented {
            self.anchoredZoomTransition = nil
        }
    }

    private func focusedViewportOrigin(for workspaceID: UUID, in clipView: NSClipView) -> NSPoint {
        let rowHeight = baseRowHeight()
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }),
              let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
            return clipView.bounds.origin
        }

        let preferredOriginY = CGFloat(workspaceIndex) * (rowHeight + WorkspaceCanvasLayoutMetrics.rowSpacing) - Metrics.workspacePeek
        let maxOriginY = max(
            rowHeight * CGFloat(workspaces.count)
                + WorkspaceCanvasLayoutMetrics.rowSpacing * CGFloat(max(workspaces.count - 1, 0))
                - clipView.bounds.height,
            0
        )

        return NSPoint(
            x: workspace.horizontalOffset,
            y: min(max(preferredOriginY, 0), maxOriginY)
        )
    }

    func baseTileHeight() -> CGFloat {
        max(
            max(viewportSize.height, 1)
                - (Metrics.workspacePeek * 2)
                - (WorkspaceCanvasLayoutMetrics.verticalPadding * 2),
            WorkspaceCanvasLayoutMetrics.minimumTileHeight
        )
    }

    func baseRowHeight() -> CGFloat {
        baseTileHeight() + (WorkspaceCanvasLayoutMetrics.verticalPadding * 2)
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
}
