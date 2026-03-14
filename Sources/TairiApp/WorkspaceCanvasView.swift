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
    private var currentSelectedWorkspaceID: UUID?
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

        guard !hasStabilizedInitialViewport,
              scrollView.contentView.bounds.width > 0,
              scrollView.contentView.bounds.height > 0,
              let currentSelectedWorkspaceID else {
            return
        }

        documentView.scrollWorkspaceToVisible(
            currentSelectedWorkspaceID,
            preserveHorizontalOrigin: false,
            animated: false
        )
        hasStabilizedInitialViewport = true
    }

    func update(
        workspaces: [WorkspaceStore.Workspace],
        selectedWorkspaceID: UUID,
        selectedTileID: UUID?,
        allTileIDs: Set<UUID>,
        canvasTransition: WorkspaceInteractionController.CanvasTransition?,
        sidebarHidden: Bool
    ) {
        currentSelectedWorkspaceID = selectedWorkspaceID
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

        if lastSelectedWorkspaceID != selectedWorkspaceID || lastSelectedTileID != selectedTileID {
            documentView.scrollWorkspaceToVisible(
                selectedWorkspaceID,
                preserveHorizontalOrigin: true,
                animated: !TairiEnvironment.isUITesting
            )
        }

        documentView.layoutSubtreeIfNeeded()
        if lastSidebarHidden == true, !sidebarHidden {
            documentView.ensureSelectedTileClearsSidebar(animated: !TairiEnvironment.isUITesting)
        }

        lastSelectedTileID = selectedTileID
        lastSelectedWorkspaceID = selectedWorkspaceID
        lastSidebarHidden = sidebarHidden
    }
}

@MainActor
final class WorkspaceCanvasDocumentView: NSView {
    private enum Metrics {
        static let workspacePeek: CGFloat = 72
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
    private var lastVerticalScrollEventAt = Date.distantPast
    private var lastDiscreteVerticalNavigationAt = Date.distantPast
    private var verticalScrollAccumulator: CGFloat = 0
    private var didNavigateDuringCurrentScrollGesture = false
    private var isSidebarHidden = false

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
                guard let tileView = tileViews[tile.id] else { continue }
                tileView.frame = NSRect(
                    x: x,
                    y: rowOriginY + WorkspaceCanvasLayoutMetrics.verticalPadding,
                    width: tile.width,
                    height: tileHeight
                )

                if tileIndex < workspace.tiles.count - 1, let handle = resizeHandles[tile.id] {
                    let handleCenterX = x + tile.width + (WorkspaceCanvasLayoutMetrics.tileSpacing / 2)
                    handle.frame = NSRect(
                        x: handleCenterX - (WorkspaceCanvasLayoutMetrics.resizeHandleWidth / 2),
                        y: rowOriginY + WorkspaceCanvasLayoutMetrics.verticalPadding + WorkspaceCanvasLayoutMetrics.resizeHandleInset,
                        width: WorkspaceCanvasLayoutMetrics.resizeHandleWidth,
                        height: max(tileHeight - (WorkspaceCanvasLayoutMetrics.resizeHandleInset * 2), 72)
                    )
                }

                x += tile.width + WorkspaceCanvasLayoutMetrics.tileSpacing
            }
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

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                clipView.animator().setBoundsOrigin(targetOrigin)
            } completionHandler: { [weak scrollView = enclosingScrollView] in
                Task { @MainActor in
                    if let scrollView {
                        scrollView.reflectScrolledClipView(clipView)
                    }
                }
            }
        } else {
            clipView.setBoundsOrigin(targetOrigin)
            enclosingScrollView?.reflectScrolledClipView(clipView)
        }
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
