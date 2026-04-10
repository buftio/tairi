import AppKit

struct WorkspaceTileHeaderDragPreview {
    let image: NSImage
    let frame: NSRect
}

final class WorkspaceTileHeaderInteractionView: NSView, NSDraggingSource {
    var tileID: UUID?
    var onSelect: (() -> Void)?
    var canBeginDrag: (() -> Bool)?
    var onBeginDrag: (() -> Void)?
    var onEndDrag: (() -> Void)?
    var dragPreviewProvider: (() -> WorkspaceTileHeaderDragPreview?)?

    private var mouseDownPoint: NSPoint?
    private var isDraggingTile = false

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        isDraggingTile = false
    }

    override func mouseUp(with event: NSEvent) {
        if mouseDownPoint != nil, !isDraggingTile {
            onSelect?()
        }
        mouseDownPoint = nil
        isDraggingTile = false
        super.mouseUp(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownPoint,
            !isDraggingTile,
            canBeginDrag?() == true,
            let tileID,
            let dragPreview = dragPreviewProvider?()
        else {
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        let deltaX = location.x - mouseDownPoint.x
        let deltaY = location.y - mouseDownPoint.y
        guard hypot(deltaX, deltaY) >= 4 else { return }

        isDraggingTile = true
        onBeginDrag?()

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(tileID.uuidString, forType: workspaceTileDragType)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(dragPreview.frame, contents: dragPreview.image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        onEndDrag?()
        mouseDownPoint = nil
        isDraggingTile = false
    }
}
