import AppKit

final class WorkspaceTileHeaderInteractionView: NSView {
    var tileID: UUID?
    var onSelect: (() -> Void)?
    var canBeginDrag: (() -> Bool)?
    var onBeginDrag: ((NSPoint) -> Void)?
    var onContinueDrag: ((NSPoint) -> Void)?
    var onEndDrag: ((NSPoint) -> Void)?

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

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownPoint, canBeginDrag?() == true else {
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        let deltaX = location.x - mouseDownPoint.x
        let deltaY = location.y - mouseDownPoint.y
        if !isDraggingTile {
            guard hypot(deltaX, deltaY) >= 4 else { return }
            isDraggingTile = true
            onBeginDrag?(event.locationInWindow)
        }

        onContinueDrag?(event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingTile {
            onEndDrag?(event.locationInWindow)
        } else if mouseDownPoint != nil {
            onSelect?()
        }
        mouseDownPoint = nil
        isDraggingTile = false
        super.mouseUp(with: event)
    }
}
