import AppKit

@MainActor
final class WorkspaceCanvasContainerView: NSView {
    private let settings: AppSettings
    private let store: WorkspaceStore
    private let scrollView = WorkspaceCanvasScrollView()
    private let documentView: WorkspaceCanvasDocumentView
    private var lastSelectedTileID: UUID?
    private var lastSelectedWorkspaceID: UUID?
    private var lastCanvasTransitionID: Int?
    private var lastWorkspaceRevealRequestID: Int?
    private var lastCanvasZoomMode: WorkspaceInteractionController.CanvasZoomMode = .focused
    private var lastTileCloseAnimationID: Int?
    private var lastTileOpenAnimationID: Int?
    private var currentSelectedWorkspaceID: UUID?
    private var currentSelectedTileID: UUID?
    private var currentCanvasZoomMode: WorkspaceInteractionController.CanvasZoomMode = .focused
    private var currentSidebarHidden = false
    private var currentRenderedStripLeadingInset = WorkspaceCanvasLayoutMetrics.stripLeadingInset(sidebarHidden: false)
    private var shouldSuppressFallbackReveal = false
    private var hasStabilizedInitialViewport = false
    private var lastSidebarHidden: Bool?
    private var pendingRevealRequest: (tileID: UUID, animated: Bool)?
    private var pendingSidebarClearRevealAnimated: Bool?

    init(
        settings: AppSettings,
        store: WorkspaceStore,
        interactionController: WorkspaceInteractionController,
        runtime: GhosttyRuntime
    ) {
        self.settings = settings
        self.store = store
        documentView = WorkspaceCanvasDocumentView(
            settings: settings,
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
        if #available(macOS 11.0, *) {
            scrollView.automaticallyAdjustsContentInsets = false
        }
        let zeroInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.contentInsets = zeroInsets
        scrollView.scrollerInsets = zeroInsets
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
        workspaceRevealRequest: WorkspaceInteractionController.WorkspaceRevealRequest?,
        canvasZoomMode: WorkspaceInteractionController.CanvasZoomMode,
        tileCloseAnimation: WorkspaceInteractionController.TileCloseAnimation?,
        tileOpenAnimation: WorkspaceInteractionController.TileOpenAnimation?,
        sidebarHidden: Bool,
        renderedStripLeadingInset: CGFloat
    ) {
        currentSelectedWorkspaceID = selectedWorkspaceID
        currentSelectedTileID = selectedTileID
        currentCanvasZoomMode = canvasZoomMode
        currentSidebarHidden = sidebarHidden
        currentRenderedStripLeadingInset = renderedStripLeadingInset
        documentView.update(
            workspaces: workspaces,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedTileID: selectedTileID,
            allTileIDs: allTileIDs,
            canvasZoomMode: canvasZoomMode,
            sidebarHidden: sidebarHidden,
            renderedStripLeadingInset: renderedStripLeadingInset
        )
        if lastSelectedWorkspaceID != selectedWorkspaceID || lastSelectedTileID != selectedTileID || lastCanvasZoomMode != canvasZoomMode {
            TairiLog.write(
                "workspace canvas update workspace=\(selectedWorkspaceID.uuidString) tile=\(selectedTileID?.uuidString ?? "none") zoomMode=\(String(describing: canvasZoomMode)) lastWorkspace=\(lastSelectedWorkspaceID?.uuidString ?? "none") lastTile=\(lastSelectedTileID?.uuidString ?? "none") workspaceCount=\(workspaces.count)"
            )
        }
        setAccessibilityValue(canvasZoomMode == .overview ? "overview" : "focused")
        documentView.viewportSize = scrollView.contentView.bounds.size

        if canvasZoomMode == .overview {
            if lastCanvasZoomMode != .overview {
                shouldSuppressFallbackReveal = true
                documentView.scrollOverviewToOrigin(animated: true)
            }
        } else if let canvasTransition, canvasTransition.id != lastCanvasTransitionID {
            switch canvasTransition.kind {
            case .reveal(let tileID, let animated):
                scheduleReveal(tileID: tileID, animated: animated)
                shouldSuppressFallbackReveal = false
            case .preserveViewport:
                shouldSuppressFallbackReveal = true
            }
            lastCanvasTransitionID = canvasTransition.id
        } else if lastSelectedWorkspaceID == selectedWorkspaceID,
            lastSelectedTileID != selectedTileID,
            let selectedTileID,
            !shouldSuppressFallbackReveal
        {
            scheduleReveal(tileID: selectedTileID, animated: false)
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

        if let workspaceRevealRequest, workspaceRevealRequest.id != lastWorkspaceRevealRequestID {
            documentView.scrollWorkspaceToVisible(
                workspaceRevealRequest.workspaceID,
                preserveHorizontalOrigin: true,
                animated: workspaceRevealRequest.animated
            )
            lastWorkspaceRevealRequestID = workspaceRevealRequest.id
        }

        if canvasZoomMode != .overview,
            !documentView.isManagingAnchoredZoomTransition,
            lastCanvasZoomMode == .overview || lastSelectedWorkspaceID != selectedWorkspaceID || lastSelectedTileID != selectedTileID
        {
            documentView.scrollWorkspaceToVisible(
                selectedWorkspaceID,
                preserveHorizontalOrigin: true,
                animated: true
            )
        }

        documentView.layoutSubtreeIfNeeded()
        stabilizeInitialViewportIfNeeded()
        if lastSidebarHidden == true, !sidebarHidden {
            scheduleSidebarClearReveal(animated: true)
        }

        lastSelectedTileID = selectedTileID
        lastSelectedWorkspaceID = selectedWorkspaceID
        lastCanvasZoomMode = canvasZoomMode
        lastSidebarHidden = sidebarHidden
    }

    private func stabilizeInitialViewportIfNeeded() {
        guard !hasStabilizedInitialViewport,
            scrollView.contentView.bounds.width > 0,
            scrollView.contentView.bounds.height > 0,
            let currentSelectedWorkspaceID
        else {
            return
        }
        TairiLog.write(
            "workspace canvas stabilizeInitialViewport workspace=\(currentSelectedWorkspaceID.uuidString) tile=\(currentSelectedTileID?.uuidString ?? "none") viewport=\(Int(scrollView.contentView.bounds.width))x\(Int(scrollView.contentView.bounds.height))"
        )

        if let currentSelectedTileID {
            scheduleReveal(tileID: currentSelectedTileID, animated: false)
        }

        let allTileIDs = Set(store.workspaces.flatMap(\.tiles).map(\.id))
        documentView.update(
            workspaces: store.workspaces,
            selectedWorkspaceID: store.selectedWorkspaceID,
            selectedTileID: store.selectedTileID,
            allTileIDs: allTileIDs,
            canvasZoomMode: currentCanvasZoomMode,
            sidebarHidden: currentSidebarHidden,
            renderedStripLeadingInset: currentRenderedStripLeadingInset
        )
        documentView.viewportSize = scrollView.contentView.bounds.size
        documentView.layoutSubtreeIfNeeded()

        documentView.scrollWorkspaceToVisible(
            currentSelectedWorkspaceID,
            preserveHorizontalOrigin: false,
            animated: false
        )
        hasStabilizedInitialViewport = true
    }

    private func scheduleReveal(tileID: UUID, animated: Bool) {
        TairiLog.write(
            "workspace canvas scheduleReveal tile=\(tileID.uuidString) animated=\(animated) windowReady=\(window != nil)"
        )
        pendingRevealRequest = (tileID: tileID, animated: animated)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                let request = self.pendingRevealRequest,
                self.window != nil
            else {
                return
            }
            self.pendingRevealRequest = nil
            TairiLog.write(
                "workspace canvas performReveal tile=\(request.tileID.uuidString) animated=\(request.animated) workspace=\(self.currentSelectedWorkspaceID?.uuidString ?? "none")"
            )
            self.documentView.revealTile(request.tileID, animated: request.animated)
        }
    }

    private func scheduleSidebarClearReveal(animated: Bool) {
        TairiLog.write(
            "workspace canvas scheduleSidebarClearReveal animated=\(animated) selectedTile=\(currentSelectedTileID?.uuidString ?? "none")"
        )
        pendingSidebarClearRevealAnimated = settings.animationPolicy.shouldAnimate(animated)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                let animated = self.pendingSidebarClearRevealAnimated,
                self.window != nil
            else {
                return
            }
            self.pendingSidebarClearRevealAnimated = nil
            TairiLog.write(
                "workspace canvas performSidebarClearReveal animated=\(animated) selectedTile=\(self.currentSelectedTileID?.uuidString ?? "none")"
            )
            self.documentView.ensureSelectedTileClearsSidebar(animated: animated)
        }
    }
}
