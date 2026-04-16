import AppKit

@MainActor
final class WorkspaceCanvasContainerView: NSView {
    private let settings: AppSettings
    private let store: WorkspaceStore
    private let interactionController: WorkspaceInteractionController
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
    private var pendingEmptySelectionResponderWorkspaceID: UUID?
    private var pendingEmptySelectionResponderReason: String?
    private var pendingEmptySelectionHeartbeatWorkspaceID: UUID?
    nonisolated(unsafe) private var keyDownMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleKeyboardReorderShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
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
        startKeyboardReorderMonitors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        documentView.viewportSize = scrollView.contentView.bounds.size
        interactionController.updateWorkspaceNavigationViewport(width: scrollView.contentView.bounds.width)
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
        requestEmptySelectionResponderHandoffIfNeeded(
            selectedWorkspaceID: selectedWorkspaceID,
            selectedTileID: selectedTileID,
            reason: "update"
        )
        if lastSelectedWorkspaceID != selectedWorkspaceID || lastSelectedTileID != selectedTileID || lastCanvasZoomMode != canvasZoomMode {
            TairiLog.write(
                "workspace canvas update workspace=\(selectedWorkspaceID.uuidString) tile=\(selectedTileID?.uuidString ?? "none") zoomMode=\(String(describing: canvasZoomMode)) lastWorkspace=\(lastSelectedWorkspaceID?.uuidString ?? "none") lastTile=\(lastSelectedTileID?.uuidString ?? "none") workspaceCount=\(workspaces.count)"
            )
        }
        setAccessibilityValue(canvasZoomMode == .overview ? "overview" : "focused")
        documentView.viewportSize = scrollView.contentView.bounds.size
        interactionController.updateWorkspaceNavigationViewport(width: scrollView.contentView.bounds.width)

        if !documentView.isTileReorderActive {
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
        } else {
            shouldSuppressFallbackReveal = true
        }

        if let tileCloseAnimation, tileCloseAnimation.id != lastTileCloseAnimationID {
            documentView.animateTileClose(tileCloseAnimation)
            lastTileCloseAnimationID = tileCloseAnimation.id
        }

        if let tileOpenAnimation, tileOpenAnimation.id != lastTileOpenAnimationID {
            documentView.animateTileOpen(tileOpenAnimation)
            lastTileOpenAnimationID = tileOpenAnimation.id
        }

        if !documentView.isTileReorderActive,
            let workspaceRevealRequest, workspaceRevealRequest.id != lastWorkspaceRevealRequestID
        {
            documentView.scrollWorkspaceToVisible(
                workspaceRevealRequest.workspaceID,
                preserveHorizontalOrigin: true,
                animated: workspaceRevealRequest.animated
            )
            lastWorkspaceRevealRequestID = workspaceRevealRequest.id
        }

        if !documentView.isTileReorderActive,
            canvasZoomMode != .overview,
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

    func requestEmptySelectionResponderHandoffIfNeeded(
        selectedWorkspaceID: UUID,
        selectedTileID: UUID?,
        reason: String
    ) {
        guard selectedTileID == nil else {
            pendingEmptySelectionResponderWorkspaceID = nil
            pendingEmptySelectionResponderReason = nil
            return
        }
        guard lastSelectedWorkspaceID != selectedWorkspaceID || lastSelectedTileID != selectedTileID else { return }

        pendingEmptySelectionResponderWorkspaceID = selectedWorkspaceID
        pendingEmptySelectionResponderReason = reason
        pendingEmptySelectionHeartbeatWorkspaceID = selectedWorkspaceID
        TairiLog.write(
            "workspace canvas emptySelection handoff requested workspace=\(selectedWorkspaceID.uuidString) reason=\(reason)"
        )
        scheduleEmptySelectionHeartbeat(
            selectedWorkspaceID: selectedWorkspaceID,
            reason: reason,
            delay: 0.25
        )
        scheduleEmptySelectionHeartbeat(
            selectedWorkspaceID: selectedWorkspaceID,
            reason: reason,
            delay: 1.0
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.currentSelectedWorkspaceID == selectedWorkspaceID else { return }
            guard self.currentSelectedTileID == nil else { return }
            guard self.pendingEmptySelectionResponderWorkspaceID == selectedWorkspaceID else { return }

            let requestedReason = self.pendingEmptySelectionResponderReason ?? reason
            self.pendingEmptySelectionResponderWorkspaceID = nil
            self.pendingEmptySelectionResponderReason = nil
            self.performEmptySelectionResponderHandoff(
                selectedWorkspaceID: selectedWorkspaceID,
                reason: requestedReason
            )
        }
    }

    private func performEmptySelectionResponderHandoff(
        selectedWorkspaceID: UUID,
        reason: String
    ) {
        guard let window else {
            TairiLog.write(
                "workspace canvas emptySelection handoff skipped workspace=\(selectedWorkspaceID.uuidString) reason=\(reason) window=nil"
            )
            return
        }

        let firstResponderDescription: String
        if let firstResponder = window.firstResponder as? NSView {
            firstResponderDescription = TairiLog.objectID(firstResponder)
        } else {
            firstResponderDescription = String(describing: window.firstResponder)
        }

        TairiLog.write(
            "workspace canvas emptySelection handoff workspace=\(selectedWorkspaceID.uuidString) reason=\(reason) firstResponder=\(firstResponderDescription)"
        )

        if window.firstResponder === self {
            TairiLog.write(
                "workspace canvas emptySelection handoff complete workspace=\(selectedWorkspaceID.uuidString) responder=container reused=true"
            )
            return
        }

        if window.makeFirstResponder(self) {
            TairiLog.write(
                "workspace canvas emptySelection handoff complete workspace=\(selectedWorkspaceID.uuidString) responder=container reused=false"
            )
            return
        }

        if let contentView = window.contentView, window.firstResponder !== contentView, window.makeFirstResponder(contentView) {
            TairiLog.write(
                "workspace canvas emptySelection handoff complete workspace=\(selectedWorkspaceID.uuidString) responder=contentView reused=false"
            )
            return
        }

        let fallbackAccepted = window.makeFirstResponder(nil)
        TairiLog.write(
            "workspace canvas emptySelection handoff fallback workspace=\(selectedWorkspaceID.uuidString) accepted=\(fallbackAccepted)"
        )
    }

    private func scheduleEmptySelectionHeartbeat(
        selectedWorkspaceID: UUID,
        reason: String,
        delay: TimeInterval
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard self.pendingEmptySelectionHeartbeatWorkspaceID == selectedWorkspaceID else { return }
            guard self.currentSelectedWorkspaceID == selectedWorkspaceID else { return }
            guard self.currentSelectedTileID == nil else { return }

            let windowNumber = self.window?.windowNumber ?? -1
            let firstResponderDescription: String
            if let firstResponder = self.window?.firstResponder as? NSView {
                firstResponderDescription = TairiLog.objectID(firstResponder)
            } else {
                firstResponderDescription = String(describing: self.window?.firstResponder)
            }

            TairiLog.write(
                "workspace canvas emptySelection heartbeat workspace=\(selectedWorkspaceID.uuidString) reason=\(reason) delay=\(String(format: "%.2f", delay)) window=\(windowNumber) firstResponder=\(firstResponderDescription)"
            )
        }
    }

    private func startKeyboardReorderMonitors() {
        guard keyDownMonitor == nil else { return }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyboardReorderKeyDown(event) ?? event
        }
    }

    private func handleKeyboardReorderKeyDown(_ event: NSEvent) -> NSEvent? {
        handleKeyboardReorderShortcut(event) ? nil : event
    }

    private func handleKeyboardReorderShortcut(_ event: NSEvent) -> Bool {
        guard keyboardReorderEventsAreEligible,
            !isGhosttySurfaceFirstResponder,
            let tileID = keyboardReorderTileID(),
            let direction = TairiHotkeys.tileReorderDirection(for: event)
        else {
            return false
        }

        _ = documentView.handleKeyboardTileReorder(direction, from: tileID)
        return true
    }

    private func keyboardReorderTileID() -> UUID? {
        guard let firstResponderView = window?.firstResponder as? NSView else {
            return currentSelectedTileID
        }

        var ancestor: NSView? = firstResponderView
        while let view = ancestor {
            if let tileHostView = view as? WorkspaceTileHostView {
                return tileHostView.representedTileID
            }
            if view === self {
                break
            }
            ancestor = view.superview
        }

        return currentSelectedTileID
    }

    private var keyboardReorderEventsAreEligible: Bool {
        guard currentCanvasZoomMode != .overview,
            currentSelectedTileID != nil,
            let window,
            window.isKeyWindow
        else {
            return false
        }

        guard let firstResponderView = window.firstResponder as? NSView else {
            return false
        }

        return firstResponderView.isDescendant(of: self)
    }

    private var isGhosttySurfaceFirstResponder: Bool {
        (window?.firstResponder as? GhosttySurfaceView) != nil
    }
}
