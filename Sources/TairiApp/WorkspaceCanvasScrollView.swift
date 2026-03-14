import AppKit

@MainActor
final class WorkspaceCanvasScrollView: NSScrollView {
    weak var canvasDocumentView: WorkspaceCanvasDocumentView?

    override func scrollWheel(with event: NSEvent) {
        if canvasDocumentView?.handleScrollWheel(event) == true {
            return
        }
        super.scrollWheel(with: event)
    }
}
