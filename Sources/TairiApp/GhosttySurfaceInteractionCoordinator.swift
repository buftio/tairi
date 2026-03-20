import AppKit

@MainActor
final class GhosttySurfaceInteractionCoordinator {
    private let runtime: GhosttyRuntime
    private weak var documentView: WorkspaceCanvasDocumentView?
    private let snapshotImageProvider: () -> NSImage?

    init(
        runtime: GhosttyRuntime,
        documentView: WorkspaceCanvasDocumentView,
        snapshotImageProvider: @escaping () -> NSImage?
    ) {
        self.runtime = runtime
        self.documentView = documentView
        self.snapshotImageProvider = snapshotImageProvider
    }

    func handleOverviewClick(tileID: UUID) -> Bool {
        documentView?.handleTileOverviewClick(tileID) == true
    }

    func handleHorizontalScroll(_ event: NSEvent) -> Bool {
        documentView?.handleHorizontalScrollGesture(event) == true
    }

    func handleMagnify(_ event: NSEvent, preferredTileID: UUID?) -> Bool {
        documentView?.handleMagnify(event, preferredTileID: preferredTileID) == true
    }

    func handleZoomKeyCommand(
        _ command: WorkspaceCanvasZoomController.Command,
        preferredTileID: UUID?
    ) -> Bool {
        documentView?.handleZoomKeyCommand(command, preferredTileID: preferredTileID) == true
    }

    func handleTileKeyNavigation(offset: Int, from tileID: UUID) -> Bool {
        documentView?.handleTileKeyNavigation(offset: offset, from: tileID) == true
    }

    func handleWorkspaceKeyNavigation(offset: Int, from tileID: UUID) -> Bool {
        documentView?.handleWorkspaceKeyNavigation(offset: offset, from: tileID) == true
    }

    func closeContext(for tileID: UUID) -> GhosttySurfaceView.TileCloseContext? {
        guard let documentView else { return nil }
        let workspaceID = runtime.store.workspaceID(containing: tileID) ?? runtime.store.selectedWorkspaceID
        return GhosttySurfaceView.TileCloseContext(
            preferredVisibleMidX: documentView.visibleMidX(forWorkspaceID: workspaceID),
            stripLeadingInset: documentView.currentStripLeadingInset,
            snapshotImage: snapshotImageProvider()
        )
    }
}
